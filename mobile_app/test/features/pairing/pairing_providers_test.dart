import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pairing/data/relay_pairing_repository.dart';
import 'package:mobile_app/features/pairing/state/pairing_providers.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/services/relay/relay_api_client.dart';
import 'package:mobile_app/services/relay/relay_token_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// In-memory [FlutterSecureStorage] stand-in - mirrors the pattern already
/// used in `test/features/sources/sources_providers_test.dart` - so these
/// tests never touch the real (platform-channel-backed) secure storage,
/// which isn't available in a plain `flutter_test` environment.
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
  return storage;
}

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(SharedPreferences.getInstance()),
      relayTokenStorageProvider.overrideWithValue(RelayTokenStorage(storage: _fakeSecureStorage())),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('relayApiClientProvider', () {
    test('is null when no relay server URL is configured', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer();
      await container.read(settingsProvider.future);

      expect(container.read(relayApiClientProvider), isNull);
    });

    test('builds a RelayApiClient once a relay server URL is configured', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer();
      await container.read(settingsProvider.future);

      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(relayServerUrl: 'https://relay.example.com'),
          );

      final client = container.read(relayApiClientProvider);
      expect(client, isA<RelayApiClient>());
      expect(client!.baseUrl, 'https://relay.example.com');
    });
  });

  group('pairingRepositoryProvider', () {
    test('is null when no relay server URL is configured', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer();
      await container.read(settingsProvider.future);

      expect(container.read(pairingRepositoryProvider), isNull);
    });

    test('builds a RelayPairingRepository once a relay server URL is configured', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer();
      await container.read(settingsProvider.future);

      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(relayServerUrl: 'https://relay.example.com'),
          );

      expect(container.read(pairingRepositoryProvider), isA<RelayPairingRepository>());
    });
  });

  group('relaySocketClientProvider', () {
    test('resolves to null when no relay server URL is configured', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer();
      await container.read(settingsProvider.future);

      final socketClient = await container.read(relaySocketClientProvider.future);
      expect(socketClient, isNull);
    });

    test('resolves to null when a relay URL is set but no device token exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer();
      await container.read(settingsProvider.future);
      await container.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(relayServerUrl: 'https://relay.example.com'),
          );

      // No frame has ever been registered on this fresh device (secure
      // storage starts empty), so there is no device token to authenticate
      // a socket connection with.
      final socketClient = await container.read(relaySocketClientProvider.future);
      expect(socketClient, isNull);
    });
  });
}
