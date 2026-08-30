import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists per-[PhotoSource] secrets (SMB share password, Nextcloud app
/// password/share-link password, ...) in the platform keychain/keystore via
/// [FlutterSecureStorage], instead of `shared_preferences` (plain-text KV
/// storage - see `AppSettingsController`/`app_settings.dart`, which is
/// correct for non-secret settings but must never hold credentials).
///
/// Mirrors the existing `RelayTokenStorage` pattern
/// (`lib/services/relay/relay_token_storage.dart`): a thin, injectable
/// wrapper around one [FlutterSecureStorage] instance so config-form widgets
/// and tests don't talk to the platform keychain directly. Kept as its own
/// class (rather than reusing `RelayTokenStorage`, which has a fixed,
/// relay-specific key set) because source credentials are keyed dynamically
/// by `(sourceId, field)` - there can be an arbitrary number of configured
/// SMB/Nextcloud sources, each with its own secret(s).
class SecureCredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _keyPrefix = 'source_cred_';

  String _key(String sourceId, String field) => '$_keyPrefix${sourceId}_$field';

  /// Stores [value] for [field] of the source identified by [sourceId] (e.g.
  /// `write(sourceId, 'password', enteredPassword)`).
  Future<void> write(String sourceId, String field, String value) {
    return _storage.write(key: _key(sourceId, field), value: value);
  }

  /// Reads back a previously-[write]-ten value, or `null` if unset.
  Future<String?> read(String sourceId, String field) {
    return _storage.read(key: _key(sourceId, field));
  }

  /// Deletes a single field's stored value.
  Future<void> delete(String sourceId, String field) {
    return _storage.delete(key: _key(sourceId, field));
  }

  /// Deletes every stored field for [sourceId] (e.g. when the source is
  /// removed from `sourcesProvider`). [FlutterSecureStorage] has no
  /// prefix-delete primitive, so this reads all keys and removes the ones
  /// belonging to this source.
  Future<void> deleteAllForSource(String sourceId) async {
    final all = await _storage.readAll();
    final prefix = '$_keyPrefix${sourceId}_';
    for (final key in all.keys) {
      if (key.startsWith(prefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  /// Deletes every stored credential whose source id is NOT in [knownIds].
  ///
  /// Source configuration is not yet persisted across app restarts (see
  /// `SourcesController` - a later milestone), but each saved config form
  /// already writes its password under a freshly generated source id. Until
  /// that persistence lands, every restart followed by re-configuring a
  /// source leaves the previous id's credential behind forever - this is
  /// the stopgap that reclaims those orphans on the next startup, called
  /// with whatever ids `SourcesController` currently knows about (an empty
  /// set today, since nothing is loaded back yet - so this currently prunes
  /// everything stale on every start, which is exactly the desired
  /// behaviour until real persistence exists).
  Future<void> pruneOrphans(Set<String> knownIds) async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (!key.startsWith(_keyPrefix)) continue;
      final rest = key.substring(_keyPrefix.length);
      final sourceId = rest.contains('_') ? rest.substring(0, rest.indexOf('_')) : rest;
      if (!knownIds.contains(sourceId)) {
        await _storage.delete(key: key);
      }
    }
  }
}
