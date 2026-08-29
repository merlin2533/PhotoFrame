import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_app/services/relay/relay_api_client.dart';
import 'package:mobile_app/services/relay/relay_token_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// Minimal hand-written [HttpClientAdapter] that serves canned JSON
/// responses keyed by "METHOD path", so [RelayApiClient] can be exercised
/// without a real relay server or network access. Registered directly on
/// the client's Dio instance instead of mocking [RelayApiClient] itself,
/// per the "mockable via interfaces... hand-written dio adapter mock"
/// guidance for this client.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _CannedResponse> responses = {};

  void when(String method, String path, {required int statusCode, Object? body}) {
    responses['$method $path'] = _CannedResponse(statusCode, body);
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    final canned = responses[key];
    if (canned == null) {
      throw StateError('No canned response registered for $key');
    }
    final payload = canned.body == null ? '' : jsonEncode(canned.body);
    return ResponseBody.fromString(
      payload,
      canned.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _CannedResponse {
  _CannedResponse(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('RelayApiClient', () {
    late _FakeAdapter adapter;
    late RelayApiClient client;
    late RelayTokenStorage tokenStorage;

    setUp(() {
      final mockStorage = _MockSecureStorage();
      final backing = <String, String>{'relay_device_token': 'device-token-123'};
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (i) async => backing[i.namedArguments[#key] as String],
      );
      when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
        (i) async {
          final key = i.namedArguments[#key] as String;
          final value = i.namedArguments[#value] as String?;
          if (value == null) {
            backing.remove(key);
          } else {
            backing[key] = value;
          }
        },
      );
      when(() => mockStorage.delete(key: any(named: 'key'))).thenAnswer((i) async {
        backing.remove(i.namedArguments[#key] as String);
      });

      tokenStorage = RelayTokenStorage(storage: mockStorage);
      adapter = _FakeAdapter();
      client = RelayApiClient(baseUrl: 'https://relay.example.com', tokenStorage: tokenStorage);
      client.dioClient.httpClientAdapter = adapter;
    });

    test('createPairingCode maps a successful response including fp/fpReason', () async {
      adapter.when('POST', '/pairing/create-code', statusCode: 201, body: {
        'pairingId': 'pairing-1',
        'code': 'ABCD1234',
        'expiresAt': '2026-01-01T00:00:00.000Z',
        'fp': null,
        'fpReason': 'creating frame has no public_key yet',
      });

      final result = await client.createPairingCode(pairingName: 'My Frame');
      expect(result.isOk, isTrue);
      final created = result.valueOrNull!;
      expect(created.pairingId, 'pairing-1');
      expect(created.code, 'ABCD1234');
      expect(created.fingerprint, isNull);
      expect(created.fingerprintReason, 'creating frame has no public_key yet');
    });

    test('getPairing maps camelCase member fields', () async {
      adapter.when('GET', '/pairing/pairing-1', statusCode: 200, body: {
        'pairing': {'id': 'pairing-1', 'name': 'Wohnzimmer'},
        'members': [
          {
            'frameId': 'frame-a',
            'role': 'owner',
            'joinedAt': '2026-01-01T00:00:00.000Z',
            'keyFingerprint': 'ABCD1234',
          },
          {
            'frameId': 'frame-b',
            'role': 'member',
            'joinedAt': '2026-01-02T00:00:00.000Z',
            'keyFingerprint': null,
          },
        ],
      });

      final result = await client.getPairing('pairing-1');
      expect(result.isOk, isTrue);
      final details = result.valueOrNull!;
      expect(details.name, 'Wohnzimmer');
      expect(details.members, hasLength(2));
      expect(details.members[0].frameId, 'frame-a');
      expect(details.members[0].isOwner, isTrue);
      expect(details.members[0].keyFingerprint, 'ABCD1234');
      expect(details.members[1].keyFingerprint, isNull);
    });

    test('a 403 response maps to a PermissionDenied failure', () async {
      adapter.when('DELETE', '/pairing/pairing-1/members/frame-b', statusCode: 403, body: {
        'error': 'only the pairing owner can remove members',
      });

      final result = await client.removeMember('pairing-1', 'frame-b');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull.runtimeType.toString(), 'PermissionDenied');
      expect(result.failureOrNull!.message, 'only the pairing owner can remove members');
    });

    test('a 404 response maps to a NotFound failure', () async {
      adapter.when('DELETE', '/pairing/pairing-1/members/frame-x', statusCode: 404, body: {
        'error': 'that frame is not a member of this pairing',
      });

      final result = await client.removeMember('pairing-1', 'frame-x');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull.runtimeType.toString(), 'NotFound');
    });

    test('recoverFrame tolerates a missing fp field without throwing', () async {
      adapter.when('POST', '/frames/frame-1/recover', statusCode: 200, body: {
        'frameId': 'frame-1',
        'deviceToken': 'new-device-token',
      });

      final result = await client.recoverFrame(frameId: 'frame-1', newPublicKey: 'x' * 32);
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.fingerprint, isNull);
    });

    test('recoverFrame passes through a present fp field', () async {
      adapter.when('POST', '/frames/frame-1/recover', statusCode: 200, body: {
        'frameId': 'frame-1',
        'deviceToken': 'new-device-token',
        'fp': 'ZZZZ9999',
      });

      final result = await client.recoverFrame(frameId: 'frame-1', newPublicKey: 'x' * 32);
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.fingerprint, 'ZZZZ9999');
    });
  });
}
