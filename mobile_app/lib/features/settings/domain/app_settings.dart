import '../../slideshow/domain/always_on_controller.dart';
import '../../slideshow/domain/night_schedule.dart';
import '../../slideshow/domain/slideshow_config.dart';

/// Visual transition played between slideshow items.
enum SlideshowTransition { fade, slide, none }

/// All persisted, user-configurable app settings, gathered in one immutable
/// value object so it can be loaded/saved as a single JSON blob in
/// `shared_preferences` (see `settings_providers.dart`).
///
/// Deliberately a plain hand-written data class (no drift/sqlite, no
/// code-gen) - the settings surface is small and changes rarely enough that
/// a single KV-stored JSON document is simpler than a database table, per
/// `docs/PLAN.md`'s "Persistenz (Settings/einfache KV): shared_preferences".
class AppSettings {
  const AppSettings({
    // Slideshow
    this.intervalSeconds = 10,
    this.showSourceLabel = false,
    this.showClock = true,
    this.displayMode = DisplayMode.contain,
    this.transition = SlideshowTransition.fade,
    this.kenBurnsEnabled = false,
    this.portraitPairLayoutEnabled = false,
    // Always-on / Dauer-Modus
    this.alwaysOnMode = AlwaysOnMode.duringSlideshowOnly,
    // Night mode
    this.nightSchedule = const NightSchedule.disabled(),
    // Cache
    this.cacheLimitBytes = 500 * 1024 * 1024,
    // Working-set pool
    this.poolTargetSize = 1000,
    this.poolRefillIntervalHours = 1,
    this.poolNewImageQuota = 0.2,
    // Favorites / date filter (P2)
    this.favoritesOnlyMode = false,
    this.preferOnThisDayEnabled = false,
    this.onThisDayQuota = 0.1,
    // Sharing/Relay (URL only - pairing logic lives elsewhere)
    this.relayServerUrl,
    // Slideshow-lock PIN (optional, guards long-press -> settings)
    this.settingsPin,
    // Onboarding
    this.onboardingCompleted = false,
    // Weather overlay
    this.weatherEnabled = false,
    this.weatherLatitude,
    this.weatherLongitude,
    this.weatherLocationLabel,
  });

  // --- Slideshow ------------------------------------------------------
  final int intervalSeconds;
  final bool showSourceLabel;
  final bool showClock;
  final DisplayMode displayMode;
  final SlideshowTransition transition;
  final bool kenBurnsEnabled;
  final bool portraitPairLayoutEnabled;

  // --- Always-on / "Dauer-Modus" --------------------------------------
  final AlwaysOnMode alwaysOnMode;

  // --- Night mode -------------------------------------------------------
  final NightSchedule nightSchedule;

  // --- Cache ------------------------------------------------------------
  final int cacheLimitBytes;

  // --- Working-set pool ---------------------------------------------------
  final int poolTargetSize;
  final int poolRefillIntervalHours;
  final double poolNewImageQuota;

  // --- Favorites / date filter (P2) ---------------------------------------

  /// When enabled, the working set is populated only from favorited items
  /// (see `FavoritesStore`/`playlists/playlist.dart`'s `favoritesOnly`
  /// filter) instead of the full configured sources. An additional mode on
  /// top of - not a replacement for - the default "all configured sources"
  /// behaviour.
  final bool favoritesOnlyMode;

  /// "Bevorzugt Bilder von diesem Tag in der Vergangenheit zeigen" -
  /// whether items matching `filterOnThisDay` (same month+day as today, any
  /// year - see `date_filter.dart`) should get a reserved share of the
  /// working-set pool's refill slots, analogous to [poolNewImageQuota].
  final bool preferOnThisDayEnabled;

  /// Fraction of a refill's *newly filled slots* reserved for "on this day"
  /// candidates when [preferOnThisDayEnabled] is `true`, in `[0, 1]`.
  ///
  /// **How this combines with [poolNewImageQuota]** (documented per task
  /// instructions, since `WorkingSetPool.refill` only natively models one
  /// reserved quota - the "new" one): the two quotas are applied as
  /// independent, non-overlapping reservations against the same pool of
  /// available refill slots, in priority order "on this day" first, then
  /// "new", then everything else:
  ///
  ///  1. `ceil(slotsToFill * onThisDayQuota)` slots are reserved for
  ///     candidates that pass `filterOnThisDay` (when
  ///     [preferOnThisDayEnabled] is on) - filled first, since a photo from
  ///     today's date in a past year is a rare, high-value match that
  ///     should not be crowded out.
  ///  2. Of the *remaining* slots, `ceil(remainingSlots * poolNewImageQuota)`
  ///     are reserved for "new" candidates, exactly as
  ///     `WorkingSetPool.refill` already does today.
  ///  3. Any slots left after both reservations are filled from whatever
  ///     candidates remain (old-first, as today), including "on this day"
  ///     or "new" candidates that didn't fit within their own reservation.
  ///
  /// A candidate can satisfy both categories (an old, rarely-shown photo
  /// that also happens to match today's date) - the priority order above
  /// means it is consumed from the "on this day" reservation first, freeing
  /// up the "new" reservation for other candidates.
  ///
  /// This composition happens at the call site that builds a refill's
  /// candidate list (splitting candidates into "on this day" vs. the rest
  /// and calling `WorkingSetPool.refill` per bucket against a shrinking
  /// slot budget), not inside `WorkingSetPool` itself - `WorkingSetPool`'s
  /// own `newImageQuota` handling is left unchanged so existing pool
  /// behaviour/tests are unaffected when this feature is off (the default).
  final double onThisDayQuota;

  // --- Sharing/Relay ------------------------------------------------------
  final String? relayServerUrl;

  // --- Slideshow lock -----------------------------------------------------
  final String? settingsPin;

  // --- Onboarding -----------------------------------------------------
  final bool onboardingCompleted;

  // --- Weather overlay --------------------------------------------------
  /// Whether the temperature/condition overlay is shown on the slideshow.
  final bool weatherEnabled;

  /// Manually-entered (default) or geolocated (opt-in) coordinates the
  /// weather overlay fetches for. Both null until the user picks/confirms a
  /// location in `weather_settings_screen.dart`.
  final double? weatherLatitude;
  final double? weatherLongitude;

  /// Human-readable label for [weatherLatitude]/[weatherLongitude], e.g.
  /// "Berlin, Deutschland" or "Aktueller Standort" - shown in settings so
  /// the user can see which location is configured without re-deriving it
  /// from raw coordinates.
  final String? weatherLocationLabel;

  Duration get interval => Duration(seconds: intervalSeconds);

  SlideshowConfig toSlideshowConfig() => SlideshowConfig(
        interval: interval,
        displayMode: displayMode,
        showClock: showClock,
        showSourceLabel: showSourceLabel,
      );

  AppSettings copyWith({
    int? intervalSeconds,
    bool? showSourceLabel,
    bool? showClock,
    DisplayMode? displayMode,
    SlideshowTransition? transition,
    bool? kenBurnsEnabled,
    bool? portraitPairLayoutEnabled,
    AlwaysOnMode? alwaysOnMode,
    NightSchedule? nightSchedule,
    int? cacheLimitBytes,
    int? poolTargetSize,
    int? poolRefillIntervalHours,
    double? poolNewImageQuota,
    bool? favoritesOnlyMode,
    bool? preferOnThisDayEnabled,
    double? onThisDayQuota,
    String? relayServerUrl,
    bool clearRelayServerUrl = false,
    String? settingsPin,
    bool clearSettingsPin = false,
    bool? onboardingCompleted,
    bool? weatherEnabled,
    double? weatherLatitude,
    double? weatherLongitude,
    String? weatherLocationLabel,
    bool clearWeatherLocation = false,
  }) {
    return AppSettings(
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      showSourceLabel: showSourceLabel ?? this.showSourceLabel,
      showClock: showClock ?? this.showClock,
      displayMode: displayMode ?? this.displayMode,
      transition: transition ?? this.transition,
      kenBurnsEnabled: kenBurnsEnabled ?? this.kenBurnsEnabled,
      portraitPairLayoutEnabled:
          portraitPairLayoutEnabled ?? this.portraitPairLayoutEnabled,
      alwaysOnMode: alwaysOnMode ?? this.alwaysOnMode,
      nightSchedule: nightSchedule ?? this.nightSchedule,
      cacheLimitBytes: cacheLimitBytes ?? this.cacheLimitBytes,
      poolTargetSize: poolTargetSize ?? this.poolTargetSize,
      poolRefillIntervalHours:
          poolRefillIntervalHours ?? this.poolRefillIntervalHours,
      poolNewImageQuota: poolNewImageQuota ?? this.poolNewImageQuota,
      favoritesOnlyMode: favoritesOnlyMode ?? this.favoritesOnlyMode,
      preferOnThisDayEnabled:
          preferOnThisDayEnabled ?? this.preferOnThisDayEnabled,
      onThisDayQuota: onThisDayQuota ?? this.onThisDayQuota,
      relayServerUrl:
          clearRelayServerUrl ? null : (relayServerUrl ?? this.relayServerUrl),
      settingsPin: clearSettingsPin ? null : (settingsPin ?? this.settingsPin),
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      weatherEnabled: weatherEnabled ?? this.weatherEnabled,
      weatherLatitude:
          clearWeatherLocation ? null : (weatherLatitude ?? this.weatherLatitude),
      weatherLongitude:
          clearWeatherLocation ? null : (weatherLongitude ?? this.weatherLongitude),
      weatherLocationLabel: clearWeatherLocation
          ? null
          : (weatherLocationLabel ?? this.weatherLocationLabel),
    );
  }

  Map<String, dynamic> toJson() => {
        'intervalSeconds': intervalSeconds,
        'showSourceLabel': showSourceLabel,
        'showClock': showClock,
        'displayMode': displayMode.name,
        'transition': transition.name,
        'kenBurnsEnabled': kenBurnsEnabled,
        'portraitPairLayoutEnabled': portraitPairLayoutEnabled,
        'alwaysOnMode': alwaysOnMode.name,
        'nightSchedule': nightSchedule.toJson(),
        'cacheLimitBytes': cacheLimitBytes,
        'poolTargetSize': poolTargetSize,
        'poolRefillIntervalHours': poolRefillIntervalHours,
        'poolNewImageQuota': poolNewImageQuota,
        'favoritesOnlyMode': favoritesOnlyMode,
        'preferOnThisDayEnabled': preferOnThisDayEnabled,
        'onThisDayQuota': onThisDayQuota,
        'relayServerUrl': relayServerUrl,
        'settingsPin': settingsPin,
        'onboardingCompleted': onboardingCompleted,
        'weatherEnabled': weatherEnabled,
        'weatherLatitude': weatherLatitude,
        'weatherLongitude': weatherLongitude,
        'weatherLocationLabel': weatherLocationLabel,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      intervalSeconds: json['intervalSeconds'] as int? ?? 10,
      showSourceLabel: json['showSourceLabel'] as bool? ?? false,
      showClock: json['showClock'] as bool? ?? true,
      displayMode: DisplayMode.values.firstWhere(
        (m) => m.name == json['displayMode'],
        orElse: () => DisplayMode.contain,
      ),
      transition: SlideshowTransition.values.firstWhere(
        (t) => t.name == json['transition'],
        orElse: () => SlideshowTransition.fade,
      ),
      kenBurnsEnabled: json['kenBurnsEnabled'] as bool? ?? false,
      portraitPairLayoutEnabled:
          json['portraitPairLayoutEnabled'] as bool? ?? false,
      alwaysOnMode: AlwaysOnMode.values.firstWhere(
        (m) => m.name == json['alwaysOnMode'],
        orElse: () => AlwaysOnMode.duringSlideshowOnly,
      ),
      nightSchedule: json['nightSchedule'] is Map
          ? NightSchedule.fromJson(
              Map<String, dynamic>.from(json['nightSchedule'] as Map))
          : const NightSchedule.disabled(),
      cacheLimitBytes: json['cacheLimitBytes'] as int? ?? 500 * 1024 * 1024,
      poolTargetSize: json['poolTargetSize'] as int? ?? 1000,
      poolRefillIntervalHours: json['poolRefillIntervalHours'] as int? ?? 1,
      poolNewImageQuota:
          (json['poolNewImageQuota'] as num?)?.toDouble() ?? 0.2,
      favoritesOnlyMode: json['favoritesOnlyMode'] as bool? ?? false,
      preferOnThisDayEnabled:
          json['preferOnThisDayEnabled'] as bool? ?? false,
      onThisDayQuota: (json['onThisDayQuota'] as num?)?.toDouble() ?? 0.1,
      relayServerUrl: json['relayServerUrl'] as String?,
      settingsPin: json['settingsPin'] as String?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      weatherEnabled: json['weatherEnabled'] as bool? ?? false,
      weatherLatitude: (json['weatherLatitude'] as num?)?.toDouble(),
      weatherLongitude: (json['weatherLongitude'] as num?)?.toDouble(),
      weatherLocationLabel: json['weatherLocationLabel'] as String?,
    );
  }
}
