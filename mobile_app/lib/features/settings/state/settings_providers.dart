import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/observability/error_reporter.dart';
import '../../../services/cache/image_cache_manager.dart';
import '../../../services/weather/weather_client.dart';
import '../domain/app_settings.dart';

const String _prefsKey = 'app_settings_v1';

/// Loads (and lazily provides) the [SharedPreferences] instance used to
/// persist [AppSettings]. Overridden in tests with
/// `SharedPreferences.setMockInitialValues`.
final Provider<Future<SharedPreferences>> sharedPreferencesProvider =
    Provider<Future<SharedPreferences>>(
        (ref) => SharedPreferences.getInstance());

/// Reads the persisted "Fehlerberichte senden" switch synchronously from
/// already-loaded [prefs]. Used by `main.dart` before the Riverpod tree
/// exists, so that error reporting honours the switch from the first error.
/// Falls back to the default (on) for missing or unreadable settings.
bool readSendErrorReportsSetting(SharedPreferences prefs) {
  final raw = prefs.getString(_prefsKey);
  if (raw == null) return const AppSettings().sendErrorReports;
  try {
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>)
        .sendErrorReports;
  } on Object {
    return const AppSettings().sendErrorReports;
  }
}

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
    setErrorReportingEnabled(settings.sendErrorReports);
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

  AppSettings get _current => state.value ?? const AppSettings();

  /// Applies [updater] to the current settings and persists the result.
  ///
  /// Named `updateSettings` (not `update`) to avoid colliding with
  /// `AsyncNotifierBase.update`, which has an incompatible signature.
  Future<void> updateSettings(
      AppSettings Function(AppSettings current) updater) {
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

/// Fraction of [AppSettings.cacheLimitBytes] reserved for the thumbnail
/// tier, with the remainder going to the full-image tier - see
/// `ImageCacheManager`'s "zweistufig" (two-tier) design. No specific ratio
/// is documented in `docs/PLAN.md`, so this is a deliberately simple,
/// provisional split: thumbnails are much smaller than full images, so a
/// relatively small share is enough to hold many of them.
const double _thumbnailCacheShare = 0.15;

int _thumbnailLimitBytesFor(int totalLimitBytes) =>
    (totalLimitBytes * _thumbnailCacheShare).round();

int _fullLimitBytesFor(int totalLimitBytes) =>
    totalLimitBytes - _thumbnailLimitBytesFor(totalLimitBytes);

/// Single, app-lifetime [ImageCacheManager] instance, sized from the
/// persisted [AppSettings.cacheLimitBytes] and kept in sync with it via
/// [Ref.listen] so moving the cache-limit slider in
/// `cache_settings_screen.dart` immediately re-enforces the new limit
/// (evicting over-budget entries) without recreating the manager - which
/// would otherwise forget in-memory pin/offline-reserve state for no
/// reason.
final Provider<ImageCacheManager> imageCacheManagerProvider =
    Provider<ImageCacheManager>((ref) {
  final initialLimit = ref.read(settingsProvider).value?.cacheLimitBytes ??
      const AppSettings().cacheLimitBytes;
  final manager = ImageCacheManager(
    thumbnailLimitBytes: _thumbnailLimitBytesFor(initialLimit),
    fullLimitBytes: _fullLimitBytesFor(initialLimit),
  );

  ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
    final limit = next.value?.cacheLimitBytes;
    if (limit == null || limit == previous?.value?.cacheLimitBytes) return;
    unawaited(manager.setLimitBytes(
        CacheTier.thumbnail, _thumbnailLimitBytesFor(limit)));
    unawaited(manager.setLimitBytes(CacheTier.full, _fullLimitBytesFor(limit)));
  });

  return manager;
});

// --- Weather ---------------------------------------------------------------

/// Single, app-lifetime [WeatherClient] instance so its in-memory
/// last-reading cache (see `weather_client.dart`) is actually shared across
/// widget rebuilds/remounts instead of refetching every time the overlay or
/// settings screen is built.
final Provider<WeatherClient> weatherClientProvider =
    Provider<WeatherClient>((ref) {
  return WeatherClient();
});
