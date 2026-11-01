import 'dart:async';

import 'package:flutter_test/flutter_test.dart' hide Timeout;
import 'package:mobile_app/core/errors/failure.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/smb/smb_photo_source.dart';
import 'package:mocktail/mocktail.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';

class _MockSmbConnect extends Mock implements SmbConnect {}

class _MockSmbFile extends Mock implements SmbFile {}

class _MockTransport extends Mock implements SmbTransport {}

const _root = PhotoFolder(id: '', name: '', path: '');
const _config = SmbSourceConfig(host: 'nas', share: 'Photos');

/// A fake connection whose transport close can be observed. The folder
/// listing is empty unless a test overrides [listFiles] or [file].
class _Fake {
  _Fake() {
    when(() => connect.transport).thenReturn(transport);
    when(() => transport.close()).thenAnswer((_) async {});
    when(() => connect.file(any())).thenAnswer((_) async => folder);
    when(() => connect.listFiles(any())).thenAnswer((_) async => <SmbFile>[]);
  }

  final connect = _MockSmbConnect();
  final transport = _MockTransport();
  final folder = _MockSmbFile();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_MockSmbFile());
  });

  group('SmbPhotoSource connection handling', () {
    test('concurrent callers share one in-flight connect', () async {
      final fake = _Fake();
      final gate = Completer<SmbConnect>();
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        connector: (_) {
          connectCount++;
          return gate.future;
        },
      );

      final first = source.listImages(_root).toList();
      final second = source.listImages(_root).toList();
      gate.complete(fake.connect);
      final results = await Future.wait([first, second]);

      expect(connectCount, 1);
      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
      await source.dispose();
    });

    test('a connection older than the max age is closed before reconnecting',
        () async {
      final first = _Fake();
      final second = _Fake();
      var now = DateTime(2026, 1, 1, 12);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        clock: () => now,
        connector: (_) async {
          connectCount++;
          return connectCount == 1 ? first.connect : second.connect;
        },
      );

      await source.listImages(_root).toList();
      now = now.add(const Duration(seconds: 61));
      await source.listImages(_root).toList();

      expect(connectCount, 2);
      verify(() => first.transport.close()).called(1);
      verifyNever(() => second.transport.close());
      await source.dispose();
    });

    test('a connect that finishes after its timeout is closed, not leaked',
        () async {
      final fake = _Fake();
      final gate = Completer<SmbConnect>();
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        connector: (_) => gate.future,
        stepTimeout: const Duration(milliseconds: 20),
      );

      final results = await source.listImages(_root).toList();
      expect(results.single.failureOrNull, isA<Timeout>());

      gate.complete(fake.connect);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => fake.transport.close()).called(1);
      await source.dispose();
    });
  });

  group('SmbPhotoSource crawl timeouts', () {
    test('a hanging directory listing yields a Timeout and drops the connection',
        () async {
      final fake = _Fake();
      final hang = Completer<SmbFile>();
      when(() => fake.connect.file(any())).thenAnswer((_) => hang.future);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        stepTimeout: const Duration(milliseconds: 20),
        connector: (_) async {
          connectCount++;
          return fake.connect;
        },
      );

      final results = await source.listImages(_root).toList();

      expect(results, hasLength(1));
      expect(results.single.failureOrNull, isA<Timeout>());
      verify(() => fake.transport.close()).called(1);

      // The next crawl must reconnect instead of reusing the dead socket.
      when(() => fake.connect.file(any())).thenAnswer((_) async => fake.folder);
      await source.listImages(_root).toList();
      expect(connectCount, 2);
      await source.dispose();
    });

    test('a listing error yields a NetworkError and drops the connection',
        () async {
      final fake = _Fake();
      when(() => fake.connect.listFiles(any()))
          .thenThrow(StateError('socket reset'));
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        connector: (_) async => fake.connect,
      );

      final results = await source.listFolders().toList();

      expect(results, hasLength(1));
      expect(results.single.failureOrNull, isA<NetworkError>());
      verify(() => fake.transport.close()).called(1);
      await source.dispose();
    });

    test('a hanging folder listing in folder enumeration also times out',
        () async {
      final fake = _Fake();
      when(() => fake.connect.listFiles(any()))
          .thenAnswer((_) => Completer<List<SmbFile>>().future);
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        stepTimeout: const Duration(milliseconds: 20),
        connector: (_) async => fake.connect,
      );

      final results = await source.listFolders().toList();

      expect(results.single.failureOrNull, isA<Timeout>());
      verify(() => fake.transport.close()).called(1);
      await source.dispose();
    });
  });
}
