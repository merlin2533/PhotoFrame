import '../../slideshow/domain/always_on_controller.dart';
import '../../slideshow/domain/night_schedule.dart';
import '../../slideshow/domain/slideshow_config.dart';

/// Visual transition played between slideshow items.
enum SlideshowTransition { fade, slide, zoom, slideUp, blurFade, flip, none }

/// How many photos are shown on screen at once.
enum SlideLayout { single, grid2x2 }

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
    this.intervalSeconds = 30,
    this.showSourceLabel = false,
    this.showCaptionOverlay = false,
    this.showImageDetails = true,
    this.slideLayout = SlideLayout.single,
    this.imageDetailsOnRight = false,
    this.showClock = true,
    this.clockAtTop = true,
    this.displayMode = DisplayMode.blurredBackdrop,
    this.transition = SlideshowTransition.fade,
    this.kenBurnsEnabled = false,
    this.portraitPairLayoutEnabled = false,
    // Always-on / Dauer-Modus
    this.alwaysOnMode = AlwaysOnMode.always,
    // Kiosk/Autostart (ADR-004)
    this.kioskModeEnabled = false,
    // Night mode
    this.nightSchedule = const NightSchedule.disabled(),
    // Ambient dimming (time window + optional light sensor)
    this.ambientDimEnabled = false,
    this.dimStartMinutes = 22 * 60,
    this.dimEndMinutes = 6 * 60,
    this.onlyPreparedPhotos = true,
    // Cache
    this.cacheLimitBytes = 500 * 1024 * 1024,
    // Working-set pool
    this.poolTargetSize = 1000,
    this.poolRefillIntervalHours = 3,
    this.indexRefreshHours = 48,
    this.selectionCount = 1000,
    this.smallPhotoBatchSize = 5,
    this.poolNewImageQuota = 0.2,
    // Favorites / date filter (P2)
    this.favoritesOnlyMode = false,
    this.disabledSourceIds = const [],
    this.textScale = 1.0,
    this.highContrast = false,
    this.preferOnThisDayEnabled = false,
    this.onThisDayQuota = 0.1,
    // Sharing/Relay (URL only - pairing logic lives elsewhere)
    this.relayServerUrl,
    // Slideshow-lock PIN (optional, guards long-press -> settings)
    this.settingsPin,
    // Language
    this.languageCode,
    // Onboarding
    this.onboardingCompleted = false,
    // Weather overlay
    this.weatherEnabled = false,
    this.weatherLatitude,
    this.weatherLongitude,
    this.weatherLocationLabel,
    // Error reporting (GlitchTip)
    this.sendErrorReports = true,
  });

  // --- Slideshow ------------------------------------------------------
  final int intervalSeconds;
  final bool showSourceLabel;

  /// Photo date (and folder name) as a small caption at the bottom left,
  /// see `widgets/caption_overlay.dart`.
  final bool showCaptionOverlay;

  /// Folder and date of the shown photo at the bottom edge.
  final bool showImageDetails;

  /// `false` = bottom left (default), `true` = bottom right.
  final bool imageDetailsOnRight;

  /// Single photo, or four photos in a 2x2 grid.
  final SlideLayout slideLayout;
  final bool showClock;

  /// Clock in the top-left corner instead of the bottom-left one.
  final bool clockAtTop;
  final DisplayMode displayMode;
  final SlideshowTransition transition;
  final bool kenBurnsEnabled;
  final bool portraitPairLayoutEnabled;

  // --- Always-on / "Dauer-Modus" --------------------------------------
  final AlwaysOnMode alwaysOnMode;

  // --- Kiosk/Autostart (ADR-004) -----------------------------------------
  /// Whether the user has opted into kiosk behaviour: register the app as
  /// selectable as the device's Home app (see AndroidManifest.xml) and
  /// activate screen pinning (`startLockTask()`, via
  /// `KioskModeController`) while the slideshow is showing. Off by default -
  /// this changes system-level behaviour (Home button interception) that a
  /// user must explicitly opt into, not something to silently switch on.
  /// Android-only; has no effect on iOS (see ADR-004/`kiosk_settings_screen.dart`).
  final bool kioskModeEnabled;

  // --- Night mode -------------------------------------------------------
  final NightSchedule nightSchedule;

  // --- Ambient dimming ----------------------------------------------------
  /// Whether the screen is dimmed with a black overlay inside the time
  /// window below. Off by default.
  final bool ambientDimEnabled;

  /// Start of the dimming window, minutes since midnight (default 22:00).
  /// See `isWithinDimWindow` in `services/ambient/ambient_dim_controller.dart`.
  final int dimStartMinutes;

  /// End of the dimming window, minutes since midnight (default 06:00).
  /// The window may cross midnight.
  final int dimEndMinutes;

  /// Show only photos that have a checked, screen-sized copy on the device.
  /// Never shows raw downloads, which can be damaged (default on).
  final bool onlyPreparedPhotos;

  // --- Cache ------------------------------------------------------------
  final int cacheLimitBytes;

  // --- Working-set pool ---------------------------------------------------
  final int poolTargetSize;
  final int poolRefillIntervalHours;

  /// How often the saved photo index is rebuilt from the sources.
  final int indexRefreshHours;

  /// How many random photos are drawn each day (100-5000).
  final int selectionCount;

  /// How many photos are queued per batch when screen-sized copies are
  /// prepared (1-50). Photos in a batch are scaled one after the other.
  final int smallPhotoBatchSize;
  final double poolNewImageQuota;

  // --- Favorites / date filter (P2) ---------------------------------------

  /// When enabled, the working set is populated only from favorited items
  /// (see `FavoritesStore`/`playlists/playlist.dart`'s `favoritesOnly`
  /// filter) instead of the full configured sources. An additional mode on
  /// top of - not a replacement for - the default "all configured sources"
  /// behaviour.
  final bool favoritesOnlyMode;

  /// Ids of sources the user switched off: they stay configured but are
  /// skipped by the slideshow.
  final List<String> disabledSourceIds;

  /// Multiplier for all text (accessibility), 1.0 = system size.
  final double textScale;

  /// Stronger contrast for text and overlays.
  final bool highContrast;

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

  // --- Language ---------------------------------------------------------
  /// User-chosen UI language (`'de'`, `'en'`), or `null` to follow the
  /// system locale (falling back to `'de'` if the system locale isn't among
  /// [AppLocalizations.supportedLocales] - see `app.dart`'s locale
  /// resolution). Independent of [AppLocalizations]'s own list of ARB
  /// locales - this only picks which of those is actually used.
  final String? languageCode;

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

  // --- Error reporting ----------------------------------------------------
  /// Whether recovered and uncaught errors are sent to GlitchTip (see
  /// `core/observability/error_reporter.dart` and docs/PRIVACY.md). On by
  /// default; when off, the reporter sends nothing.
  final bool sendErrorReports;

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
    bool? showCaptionOverlay,
    bool? showImageDetails,
    bool? imageDetailsOnRight,
    SlideLayout? slideLayout,
    bool? showClock,
    bool? clockAtTop,
    DisplayMode? displayMode,
    SlideshowTransition? transition,
    bool? kenBurnsEnabled,
    bool? portraitPairLayoutEnabled,
    AlwaysOnMode? alwaysOnMode,
    bool? kioskModeEnabled,
    NightSchedule? nightSchedule,
    bool? ambientDimEnabled,
    int? dimStartMinutes,
    int? dimEndMinutes,
    bool? onlyPreparedPhotos,
    int? cacheLimitBytes,
    int? poolTargetSize,
    int? poolRefillIntervalHours,
    int? indexRefreshHours,
    int? selectionCount,
    int? smallPhotoBatchSize,
    double? poolNewImageQuota,
    bool? favoritesOnlyMode,
    List<String>? disabledSourceIds,
    double? textScale,
    bool? highContrast,
    bool? preferOnThisDayEnabled,
    double? onThisDayQuota,
    String? relayServerUrl,
    bool clearRelayServerUrl = false,
    String? settingsPin,
    bool clearSettingsPin = false,
    String? languageCode,
    bool clearLanguageCode = false,
    bool? onboardingCompleted,
    bool? weatherEnabled,
    double? weatherLatitude,
    double? weatherLongitude,
    String? weatherLocationLabel,
    bool clearWeatherLocation = false,
    bool? sendErrorReports,
  }) {
    return AppSettings(
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      showSourceLabel: showSourceLabel ?? this.showSourceLabel,
      showCaptionOverlay: showCaptionOverlay ?? this.showCaptionOverlay,
      showImageDetails: showImageDetails ?? this.showImageDetails,
      imageDetailsOnRight: imageDetailsOnRight ?? this.imageDetailsOnRight,
      slideLayout: slideLayout ?? this.slideLayout,
      showClock: showClock ?? this.showClock,
      clockAtTop: clockAtTop ?? this.clockAtTop,
      displayMode: displayMode ?? this.displayMode,
      transition: transition ?? this.transition,
      kenBurnsEnabled: kenBurnsEnabled ?? this.kenBurnsEnabled,
      portraitPairLayoutEnabled:
          portraitPairLayoutEnabled ?? this.portraitPairLayoutEnabled,
      alwaysOnMode: alwaysOnMode ?? this.alwaysOnMode,
      kioskModeEnabled: kioskModeEnabled ?? this.kioskModeEnabled,
      nightSchedule: nightSchedule ?? this.nightSchedule,
      ambientDimEnabled: ambientDimEnabled ?? this.ambientDimEnabled,
      dimStartMinutes: dimStartMinutes ?? this.dimStartMinutes,
      dimEndMinutes: dimEndMinutes ?? this.dimEndMinutes,
      onlyPreparedPhotos: onlyPreparedPhotos ?? this.onlyPreparedPhotos,
      cacheLimitBytes: cacheLimitBytes ?? this.cacheLimitBytes,
      poolTargetSize: poolTargetSize ?? this.poolTargetSize,
      poolRefillIntervalHours:
          poolRefillIntervalHours ?? this.poolRefillIntervalHours,
      indexRefreshHours: indexRefreshHours ?? this.indexRefreshHours,
      selectionCount: selectionCount ?? this.selectionCount,
      smallPhotoBatchSize: smallPhotoBatchSize ?? this.smallPhotoBatchSize,
      poolNewImageQuota: poolNewImageQuota ?? this.poolNewImageQuota,
      favoritesOnlyMode: favoritesOnlyMode ?? this.favoritesOnlyMode,
      disabledSourceIds: disabledSourceIds ?? this.disabledSourceIds,
      textScale: textScale ?? this.textScale,
      highContrast: highContrast ?? this.highContrast,
      preferOnThisDayEnabled:
          preferOnThisDayEnabled ?? this.preferOnThisDayEnabled,
      onThisDayQuota: onThisDayQuota ?? this.onThisDayQuota,
      relayServerUrl:
          clearRelayServerUrl ? null : (relayServerUrl ?? this.relayServerUrl),
      settingsPin: clearSettingsPin ? null : (settingsPin ?? this.settingsPin),
      languageCode:
          clearLanguageCode ? null : (languageCode ?? this.languageCode),
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      weatherEnabled: weatherEnabled ?? this.weatherEnabled,
      weatherLatitude: clearWeatherLocation
          ? null
          : (weatherLatitude ?? this.weatherLatitude),
      weatherLongitude: clearWeatherLocation
          ? null
          : (weatherLongitude ?? this.weatherLongitude),
      weatherLocationLabel: clearWeatherLocation
          ? null
          : (weatherLocationLabel ?? this.weatherLocationLabel),
      sendErrorReports: sendErrorReports ?? this.sendErrorReports,
    );
  }

  Map<String, dynamic> toJson() => {
        'intervalSeconds': intervalSeconds,
        'showSourceLabel': showSourceLabel,
        'showCaptionOverlay': showCaptionOverlay,
        'showImageDetails': showImageDetails,
        'imageDetailsOnRight': imageDetailsOnRight,
        'slideLayout': slideLayout.name,
        'showClock': showClock,
        'clockAtTop': clockAtTop,
        'displayMode': displayMode.name,
        'transition': transition.name,
        'kenBurnsEnabled': kenBurnsEnabled,
        'portraitPairLayoutEnabled': portraitPairLayoutEnabled,
        'alwaysOnMode': alwaysOnMode.name,
        'kioskModeEnabled': kioskModeEnabled,
        'nightSchedule': nightSchedule.toJson(),
        'ambientDimEnabled': ambientDimEnabled,
        'dimStartMinutes': dimStartMinutes,
        'dimEndMinutes': dimEndMinutes,
        'onlyPreparedPhotos': onlyPreparedPhotos,
        'cacheLimitBytes': cacheLimitBytes,
        'poolTargetSize': poolTargetSize,
        'poolRefillIntervalHours': poolRefillIntervalHours,
        'indexRefreshHours': indexRefreshHours,
        'selectionCount': selectionCount,
        'smallPhotoBatchSize': smallPhotoBatchSize,
        'poolNewImageQuota': poolNewImageQuota,
        'favoritesOnlyMode': favoritesOnlyMode,
        'disabledSourceIds': disabledSourceIds,
        'textScale': textScale,
        'highContrast': highContrast,
        'preferOnThisDayEnabled': preferOnThisDayEnabled,
        'onThisDayQuota': onThisDayQuota,
        'relayServerUrl': relayServerUrl,
        'settingsPin': settingsPin,
        'languageCode': languageCode,
        'onboardingCompleted': onboardingCompleted,
        'weatherEnabled': weatherEnabled,
        'weatherLatitude': weatherLatitude,
        'weatherLongitude': weatherLongitude,
        'weatherLocationLabel': weatherLocationLabel,
        'sendErrorReports': sendErrorReports,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      intervalSeconds: json['intervalSeconds'] as int? ?? 10,
      showSourceLabel: json['showSourceLabel'] as bool? ?? false,
      showCaptionOverlay: json['showCaptionOverlay'] as bool? ?? false,
      showImageDetails: json['showImageDetails'] as bool? ?? true,
      imageDetailsOnRight: json['imageDetailsOnRight'] as bool? ?? false,
      slideLayout: SlideLayout.values.firstWhere(
        (l) => l.name == json['slideLayout'],
        orElse: () => SlideLayout.single,
      ),
      showClock: json['showClock'] as bool? ?? true,
      clockAtTop: json['clockAtTop'] as bool? ?? true,
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
      kioskModeEnabled: json['kioskModeEnabled'] as bool? ?? false,
      nightSchedule: json['nightSchedule'] is Map
          ? NightSchedule.fromJson(
              Map<String, dynamic>.from(json['nightSchedule'] as Map))
          : const NightSchedule.disabled(),
      ambientDimEnabled: json['ambientDimEnabled'] as bool? ?? false,
      dimStartMinutes: json['dimStartMinutes'] as int? ?? 22 * 60,
      dimEndMinutes: json['dimEndMinutes'] as int? ?? 6 * 60,
      onlyPreparedPhotos: json['onlyPreparedPhotos'] as bool? ?? true,
      cacheLimitBytes: json['cacheLimitBytes'] as int? ?? 500 * 1024 * 1024,
      poolTargetSize: json['poolTargetSize'] as int? ?? 1000,
      poolRefillIntervalHours: json['poolRefillIntervalHours'] as int? ?? 3,
      indexRefreshHours: json['indexRefreshHours'] as int? ?? 48,
      selectionCount: json['selectionCount'] as int? ?? 1000,
      smallPhotoBatchSize: json['smallPhotoBatchSize'] as int? ?? 5,
      poolNewImageQuota: (json['poolNewImageQuota'] as num?)?.toDouble() ?? 0.2,
      favoritesOnlyMode: json['favoritesOnlyMode'] as bool? ?? false,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      highContrast: json['highContrast'] as bool? ?? false,
      disabledSourceIds:
          (json['disabledSourceIds'] as List?)?.whereType<String>().toList() ??
              const [],
      preferOnThisDayEnabled: json['preferOnThisDayEnabled'] as bool? ?? false,
      onThisDayQuota: (json['onThisDayQuota'] as num?)?.toDouble() ?? 0.1,
      relayServerUrl: json['relayServerUrl'] as String?,
      settingsPin: json['settingsPin'] as String?,
      languageCode: json['languageCode'] as String?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      weatherEnabled: json['weatherEnabled'] as bool? ?? false,
      weatherLatitude: (json['weatherLatitude'] as num?)?.toDouble(),
      weatherLongitude: (json['weatherLongitude'] as num?)?.toDouble(),
      weatherLocationLabel: json['weatherLocationLabel'] as String?,
      sendErrorReports: json['sendErrorReports'] as bool? ?? true,
    );
  }
}
