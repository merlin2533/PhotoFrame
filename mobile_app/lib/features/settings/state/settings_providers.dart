import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/weather/weather_client.dart';
import '../domain/app_settings.dart';

const String _prefsKey = 'app_settings_v1';

/// Loads (and lazily provides) the [SharedPreferences] instance used to
/// persist [AppSettings]. Overridden in tests with
/// `SharedPreferences.setMockInitialValues`.
final Provider<Future<SharedPreferences>> sharedPreferencesProvider =
    Provider<Future<SharedPreferences>>((ref) => SharedPreferences.getInstance());

/// Owns the persisted [AppSettings] and exposes mutation helpers. Backed by
/// a single JSON blob in `shared_preferences` (see [AppSettings] doc
/// comment for why this is a plain KV blob rather than a database table).
class AppSettingsController extends AsyncNotifier<AppSettings> {
  SharedPreferences? _prefs;

  @override
  Future<AppSettings> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider);
    _prefs = prefs;
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // Corrupt/old-format value - fall back to defaults rather than crash
      // the whole app on startup.
      return const AppSettings();
    }
  }

  Future<void> _persist(AppSettings settings) async {
    state = AsyncValue.data(settings);
    SharedPreferences prefs;
    final cached = _prefs;
    if (cached != null) {
      prefs = cached;
    } else {
      prefs = await ref.read(sharedPreferencesProvider);
      _prefs = prefs;
    }
    await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
  }

  AppSettings get _current => state.valueOrNull ?? const AppSettings();

  /// Applies [updater] to the current settings and persists the result.
  ///
  /// Named `updateSettings` (not `update`) to avoid colliding with
  /// `AsyncNotifierBase.update`, which has an incompatible signature.
  Future<void> updateSettings(AppSettings Function(AppSettings current) updater) {
    return _persist(updater(_current));
  }

  Future<void> markOnboardingCompleted() {
    return updateSettings((s) => s.copyWith(onboardingCompleted: true));
  }

  Future<void> resetOnboarding() {
    return updateSettings((s) => s.copyWith(onboardingCompleted: false));
  }
}

final AsyncNotifierProvider<AppSettingsController, AppSettings>
    settingsProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

// --- Cache info -----------------------------------------------------------

/// Snapshot of cache usage shown in the cache-management settings page.
///
/// TODO(parallel-agent/ImageCacheManager): replace this placeholder with a
/// provider that reads real numbers from `ImageCacheManager` once that
/// service lands (see `docs/PLAN.md` -> `services/cache/image_cache_manager.dart`).
/// The settings UI only depends on this simple data shape, so wiring the
/// real implementation later is a one-provider change.
class CacheInfo {
  const CacheInfo({required this.usedBytes, required this.limitBytes});

  final int usedBytes;
  final int limitBytes;

  double get usedFraction =>
      limitBytes <= 0 ? 0 : (usedBytes / limitBytes).clamp(0, 1).toDouble();
}

// --- Weather ---------------------------------------------------------------

/// Single, app-lifetime [WeatherClient] instance so its in-memory
/// last-reading cache (see `weather_client.dart`) is actually shared across
/// widget rebuilds/remounts instead of refetching every time the overlay or
/// settings screen is built.
final Provider<WeatherClient> weatherClientProvider = Provider<WeatherClient>((ref) {
  return WeatherClient();
});

final Provider<CacheInfo> cacheInfoProvider = Provider<CacheInfo>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
  // Placeholder usage value until ImageCacheManager exists - see class doc
  // comment above.
  const placeholderUsedBytes = 128 * 1024 * 1024;
  return CacheInfo(
    usedBytes: placeholderUsedBytes,
    limitBytes: settings.cacheLimitBytes,
  );
});
