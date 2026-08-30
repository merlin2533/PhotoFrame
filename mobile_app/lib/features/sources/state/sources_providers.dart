import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../services/storage/secure_credential_store.dart';
import '../domain/photo_source.dart';
import '../domain/source_descriptor.dart';
import '../mock/mock_photo_source.dart';

const String _prefsKey = 'sources_v1';

/// Shared [SecureCredentialStore] instance for source-form widgets (SMB
/// password, Nextcloud app/share password, ...) - see that class's doc
/// comment for why credentials never go through `shared_preferences`.
final Provider<SecureCredentialStore> secureCredentialStoreProvider =
    Provider<SecureCredentialStore>((ref) => SecureCredentialStore());

/// Generates stable ids for newly configured [PhotoSource] instances.
/// Exposed as a provider (rather than a bare top-level `Uuid()`) purely so
/// tests can override it deterministically if ever needed.
final Provider<Uuid> sourceIdGeneratorProvider = Provider<Uuid>((ref) => const Uuid());

/// Loads (and lazily provides) the [SharedPreferences] instance used to
/// persist the non-secret source configuration (see [SourceDescriptor]).
/// Overridden in tests with `SharedPreferences.setMockInitialValues`.
///
/// Deliberately a *separate* provider from `settings_providers.dart`'s
/// identically-shaped `sharedPreferencesProvider` (rather than importing that
/// one) - `features/sources` and `features/settings` are siblings with no
/// existing dependency between them, and `SharedPreferences.getInstance()`
/// itself is a cheap, memoized singleton on the plugin side, so having two
/// thin provider wrappers around it costs nothing at runtime while keeping
/// the features decoupled.
final Provider<Future<SharedPreferences>> sourcesSharedPreferencesProvider =
    Provider<Future<SharedPreferences>>((ref) => SharedPreferences.getInstance());

/// Registered [PhotoSource] instances the app currently knows about.
///
/// Backed by a JSON array of [SourceDescriptor]s in `shared_preferences`
/// (key `sources_v1`, mirroring `AppSettingsController`'s `app_settings_v1`
/// single-blob pattern) plus, per source, a password loaded separately from
/// [SecureCredentialStore] - see `source_descriptor.dart` for the
/// descriptor<->instance mapping and why passwords never appear in the
/// descriptor JSON.
///
/// On a genuinely first run (no `sources_v1` key yet, i.e. this device has
/// never had a source configured), the registry seeds itself with a single
/// [MockPhotoSource] - exactly as before this class persisted anything - so
/// the Settings/Sources UI and the slideshow screen have something real to
/// list and render out of the box, and immediately persists that seed so it
/// isn't silently re-created every restart. Once the user has configured (or
/// removed) anything, the persisted list - even if empty - is authoritative
/// and no further seeding happens.
class SourcesController extends AsyncNotifier<List<PhotoSource>> {
  SharedPreferences? _prefs;

  @override
  Future<List<PhotoSource>> build() async {
    ref.onDispose(() {
      final current = state.valueOrNull;
      if (current == null) return;
      for (final source in current) {
        // Fire-and-forget: dispose() is async but Notifier.onDispose isn't.
        unawaited(source.dispose());
      }
    });

    final prefs = await ref.watch(sourcesSharedPreferencesProvider);
    _prefs = prefs;
    final credentialStore = ref.read(secureCredentialStoreProvider);

    List<PhotoSource> sources;
    if (!prefs.containsKey(_prefsKey)) {
      // First run on this device - seed with the historical default so the
      // UI isn't empty, and persist it immediately (see class doc comment).
      sources = [MockPhotoSource()];
      await _saveDescriptors(prefs, sources);
    } else {
      final descriptors = _loadDescriptors(prefs);
      sources = [];
      for (final descriptor in descriptors) {
        final password = await credentialStore.read(descriptor.id, 'password');
        sources.add(fromDescriptor(descriptor, password: password));
      }
    }

    // Now that the actually-restored ids are known (not just whatever was
    // present at this exact moment - the pre-persistence stopgap this
    // replaces), reclaim any credential left behind by a source that no
    // longer exists (removed on another install, a crash mid-`removeById`,
    // ...).
    unawaited(credentialStore.pruneOrphans(sources.map((s) => s.id).toSet()));

    return sources;
  }

  List<SourceDescriptor> _loadDescriptors(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => SourceDescriptor.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on FormatException {
      // Corrupt/old-format value - fall back to an empty list rather than
      // crash the whole app on startup.
      return [];
    }
  }

  Future<void> _saveDescriptors(SharedPreferences prefs, List<PhotoSource> sources) async {
    final descriptors = sources.map((s) => s.toDescriptor().toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(descriptors));
  }

  Future<SharedPreferences> _prefsInstance() async {
    final cached = _prefs;
    if (cached != null) return cached;
    final prefs = await ref.read(sourcesSharedPreferencesProvider);
    _prefs = prefs;
    return prefs;
  }

  Future<void> add(PhotoSource source) async {
    final current = state.valueOrNull ?? const <PhotoSource>[];
    final updated = [...current, source];
    state = AsyncValue.data(updated);
    await _saveDescriptors(await _prefsInstance(), updated);
  }

  Future<void> removeById(String id) async {
    final current = state.valueOrNull ?? const <PhotoSource>[];
    final removed = current.where((s) => s.id == id).toList();
    final updated = current.where((s) => s.id != id).toList();
    state = AsyncValue.data(updated);
    await _saveDescriptors(await _prefsInstance(), updated);
    for (final source in removed) {
      unawaited(source.dispose());
      // Best-effort: also drop any stored credentials for this source so
      // they don't linger in the secure keychain after the source itself
      // is gone.
      unawaited(ref.read(secureCredentialStoreProvider).deleteAllForSource(source.id));
    }
  }
}

final AsyncNotifierProvider<SourcesController, List<PhotoSource>> sourcesProvider =
    AsyncNotifierProvider<SourcesController, List<PhotoSource>>(
  SourcesController.new,
);
