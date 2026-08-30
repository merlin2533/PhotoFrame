import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/local/local_folder_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/features/sources/smb/smb_photo_source.dart';
import 'package:mobile_app/features/sources/state/sources_providers.dart';
import 'package:mobile_app/services/storage/secure_credential_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'sources_v1';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// An in-memory [FlutterSecureStorage] stand-in shared by a whole test's
/// [ProviderContainer]s, mirroring the pattern already used in
/// `test/features/pairing/config_push_crypto_test.dart`.
_MockSecureStorage _fakeSecureStorage([Map<String, String>? backing]) {
  final storage = _MockSecureStorage();
  final store = backing ?? <String, String>{};
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
    (invocation) async {
      store.remove(invocation.namedArguments[#key] as String);
    },
  );
  when(() => storage.readAll()).thenAnswer((_) async => Map<String, String>.from(store));
  return storage;
}

ProviderContainer _makeContainer({
  required Future<SharedPreferences> prefs,
  required SecureCredentialStore credentialStore,
}) {
  final container = ProviderContainer(
    overrides: [
      sourcesSharedPreferencesProvider.overrideWithValue(prefs),
      secureCredentialStoreProvider.overrideWithValue(credentialStore),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourcesController', () {
    test('first run (no persisted key) seeds a single MockPhotoSource and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferences.getInstance();
      final credentialStore = SecureCredentialStore(storage: _fakeSecureStorage());
      final container = _makeContainer(prefs: prefs, credentialStore: credentialStore);

      final sources = await container.read(sourcesProvider.future);

      expect(sources, hasLength(1));
      expect(sources.single, isA<MockPhotoSource>());

      final resolvedPrefs = await prefs;
      final raw = resolvedPrefs.getString(_prefsKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List<dynamic>;
      expect(decoded, hasLength(1));
      expect((decoded.single as Map)['type'], 'mock');
    });

    test('build() loads a persisted SMB descriptor and re-attaches its password', () async {
      SharedPreferences.setMockInitialValues({
        _prefsKey: jsonEncode([
          {
            'type': 'smb',
            'id': 'src-smb-1',
            'displayName': 'My NAS',
            'config': {
              'host': 'nas.local',
              'share': 'Photos',
              'domain': '',
              'username': 'alice',
              'rootPath': '',
            },
          },
        ]),
      });
      final prefs = SharedPreferences.getInstance();
      final backing = <String, String>{'source_cred_src-smb-1_password': 'hunter2'};
      final credentialStore = SecureCredentialStore(storage: _fakeSecureStorage(backing));
      final container = _makeContainer(prefs: prefs, credentialStore: credentialStore);

      final sources = await container.read(sourcesProvider.future);

      expect(sources, hasLength(1));
      final source = sources.single as SmbPhotoSource;
      expect(source.id, 'src-smb-1');
      expect(source.displayName, 'My NAS');
      expect(source.config.host, 'nas.local');
      expect(source.config.password, 'hunter2');
    });

    test('build() prunes orphaned credentials using the actually-restored ids', () async {
      SharedPreferences.setMockInitialValues({
        _prefsKey: jsonEncode([
          {
            'type': 'local',
            'id': 'src-keep',
            'displayName': 'Kept',
            'config': {'rootPath': '/mnt/keep'},
          },
        ]),
      });
      final prefs = SharedPreferences.getInstance();
      final backing = <String, String>{
        'source_cred_src-keep_password': 'irrelevant-for-local-but-present',
        'source_cred_src-orphan_password': 'should-be-pruned',
      };
      final credentialStore = SecureCredentialStore(storage: _fakeSecureStorage(backing));
      final container = _makeContainer(prefs: prefs, credentialStore: credentialStore);

      await container.read(sourcesProvider.future);
      // pruneOrphans is fire-and-forget (unawaited) inside build() - flush
      // the microtask queue so its single readAll()+delete() round-trip has
      // actually completed before asserting.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backing.containsKey('source_cred_src-orphan_password'), isFalse);
      expect(backing.containsKey('source_cred_src-keep_password'), isTrue);
    });

    test('add() persists the new descriptor so a fresh controller instance restores it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferences.getInstance();
      final credentialStore = SecureCredentialStore(storage: _fakeSecureStorage());
      final container1 = _makeContainer(prefs: prefs, credentialStore: credentialStore);

      // Drain the first-run mock seed before adding a real source, so the
      // persisted list ends up with exactly the two expected entries.
      await container1.read(sourcesProvider.future);

      final localSource = LocalFolderSource(id: 'src-local-1', rootPath: '/mnt/frame');
      await container1.read(sourcesProvider.notifier).add(localSource);

      final container2 = _makeContainer(prefs: prefs, credentialStore: credentialStore);
      final sources2 = await container2.read(sourcesProvider.future);

      expect(sources2.map((s) => s.id), containsAll(<String>['src-local-1']));
      final restoredLocal = sources2.firstWhere((s) => s.id == 'src-local-1') as LocalFolderSource;
      expect(restoredLocal.rootPath, '/mnt/frame');
    });

    test('removeById() drops the descriptor and deletes stored credentials', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferences.getInstance();
      final backing = <String, String>{};
      final credentialStore = SecureCredentialStore(storage: _fakeSecureStorage(backing));
      final container = _makeContainer(prefs: prefs, credentialStore: credentialStore);

      await container.read(sourcesProvider.future);

      const config = SmbSourceConfig(host: 'nas.local', share: 'Photos', password: 'hunter2');
      final smbSource = SmbPhotoSource(id: 'src-smb-2', config: config);
      await credentialStore.write('src-smb-2', 'password', 'hunter2');
      await container.read(sourcesProvider.notifier).add(smbSource);

      expect(backing.containsKey('source_cred_src-smb-2_password'), isTrue);

      await container.read(sourcesProvider.notifier).removeById('src-smb-2');
      // deleteAllForSource is fire-and-forget inside removeById() - flush
      // the microtask queue before asserting.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final sources = container.read(sourcesProvider).valueOrNull ?? const <PhotoSource>[];
      expect(sources.any((s) => s.id == 'src-smb-2'), isFalse);
      expect(backing.containsKey('source_cred_src-smb-2_password'), isFalse);

      final resolvedPrefs = await prefs;
      final raw = resolvedPrefs.getString(_prefsKey);
      final decoded = jsonDecode(raw!) as List<dynamic>;
      expect(decoded.any((d) => (d as Map)['id'] == 'src-smb-2'), isFalse);
    });

    test('an explicitly-emptied source list stays empty on the next build (no re-seeding)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferences.getInstance();
      final credentialStore = SecureCredentialStore(storage: _fakeSecureStorage());
      final container1 = _makeContainer(prefs: prefs, credentialStore: credentialStore);

      final seeded = await container1.read(sourcesProvider.future);
      final seededId = seeded.single.id;
      await container1.read(sourcesProvider.notifier).removeById(seededId);

      final container2 = _makeContainer(prefs: prefs, credentialStore: credentialStore);
      final sources2 = await container2.read(sourcesProvider.future);

      expect(sources2, isEmpty);
    });
  });
}
