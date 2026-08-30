import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/errors/failure.dart';
import 'package:mobile_app/features/pairing/domain/config_push_apply.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/smb/smb_photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';
import 'package:mobile_app/services/storage/secure_credential_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// In-memory [FlutterSecureStorage] stand-in, mirroring the pattern already
/// used in `test/features/sources/sources_providers_test.dart`.
_MockSecureStorage _fakeSecureStorage() {
  final storage = _MockSecureStorage();
  final store = <String, String>{};
  when(() => storage.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => store[invocation.namedArguments[#key] as String],
  );
  when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
    (invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        store.remove(key);
      } else {
        store[key] = value;
      }
    },
  );
  when(() => storage.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async => store.remove(invocation.namedArguments[#key] as String),
  );
  when(() => storage.readAll()).thenAnswer((_) async => Map<String, String>.from(store));
  return storage;
}

/// [applyDecryptedConfigPush] takes a [WidgetRef] (matching its real call
/// site in `pairing_route_screens.dart`, a `ConsumerWidget`), which - unlike
/// a plain [Ref] - can only be obtained by actually pumping a widget tree.
/// This pumps a throwaway [Consumer] under a [ProviderScope] with the same
/// overrides `sources_providers_test.dart` uses, and hands back both the
/// captured [WidgetRef] and the [ProviderContainer] backing it so
/// assertions can read provider state directly afterwards.
class _Fixture {
  _Fixture(this.ref, this.container);

  final WidgetRef ref;
  final ProviderContainer container;
}

Future<_Fixture> _pumpFixture(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  late WidgetRef capturedRef;
  late ProviderContainer capturedContainer;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sourcesSharedPreferencesProvider.overrideWithValue(SharedPreferences.getInstance()),
        secureCredentialStoreProvider.overrideWithValue(SecureCredentialStore(storage: _fakeSecureStorage())),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          capturedContainer = ProviderScope.containerOf(context);
          return const SizedBox.shrink();
        }),
      ),
    ),
  );
  await tester.pump();

  // Let the seeded MockPhotoSource-only initial state settle first, so
  // `sourcesProvider`'s `add()` below always starts from a known baseline.
  await capturedContainer.read(sourcesProvider.future);

  return _Fixture(capturedRef, capturedContainer);
}

void main() {
  group('applyDecryptedConfigPush', () {
    testWidgets('valid SMB payload registers a new SMB source', (tester) async {
      final fixture = await _pumpFixture(tester);

      final plaintext = jsonEncode({
        'type': 'smb',
        'host': 'nas.local',
        'share': 'Photos',
        'username': 'frank',
        'password': 's3cret',
      });

      final result = await applyDecryptedConfigPush(
        plaintext,
        ref: fixture.ref,
        senderLabel: 'Handy XY',
      );

      expect(result.isOk, isTrue);

      final sources = fixture.container.read(sourcesProvider).valueOrNull;
      expect(sources, isNotNull);
      final added = sources!.where((s) => s.type == SourceType.smb).cast<SmbPhotoSource>().toList();
      expect(added, hasLength(1));
      expect(added.single.config.host, 'nas.local');
      expect(added.single.config.share, 'Photos');
      expect(added.single.config.username, 'frank');
      expect(added.single.config.password, 's3cret');
      expect(added.single.displayName, contains('Handy XY'));
    });

    testWidgets('unknown payload type returns Unsupported without registering anything', (tester) async {
      final fixture = await _pumpFixture(tester);
      final before = fixture.container.read(sourcesProvider).valueOrNull!.length;

      final plaintext = jsonEncode({'type': 'nextcloud', 'host': 'example.com'});

      final result = await applyDecryptedConfigPush(plaintext, ref: fixture.ref);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<Unsupported>());
      expect(fixture.container.read(sourcesProvider).valueOrNull!.length, before);
    });

    testWidgets('missing type field returns Unsupported', (tester) async {
      final fixture = await _pumpFixture(tester);
      final result = await applyDecryptedConfigPush(jsonEncode({'host': 'nas.local'}), ref: fixture.ref);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<Unsupported>());
    });

    testWidgets('corrupt JSON returns Unsupported without throwing', (tester) async {
      final fixture = await _pumpFixture(tester);
      final result = await applyDecryptedConfigPush('{not valid json', ref: fixture.ref);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<Unsupported>());
    });

    testWidgets('a JSON array (not an object) returns Unsupported', (tester) async {
      final fixture = await _pumpFixture(tester);
      final result = await applyDecryptedConfigPush(jsonEncode([1, 2, 3]), ref: fixture.ref);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<Unsupported>());
    });

    testWidgets('SMB payload missing host/share returns Unsupported', (tester) async {
      final fixture = await _pumpFixture(tester);
      final plaintext = jsonEncode({'type': 'smb', 'username': 'frank'});

      final result = await applyDecryptedConfigPush(plaintext, ref: fixture.ref);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<Unsupported>());
    });
  });
}
