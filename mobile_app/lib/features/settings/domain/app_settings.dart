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
    // Sharing/Relay (URL only - pairing logic lives elsewhere)
    this.relayServerUrl,
    // Slideshow-lock PIN (optional, guards long-press -> settings)
    this.settingsPin,
    // Onboarding
    this.onboardingCompleted = false,
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

  // --- Sharing/Relay ------------------------------------------------------
  final String? relayServerUrl;

  // --- Slideshow lock -----------------------------------------------------
  final String? settingsPin;

  // --- Onboarding -----------------------------------------------------
  final bool onboardingCompleted;

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
    String? relayServerUrl,
    bool clearRelayServerUrl = false,
    String? settingsPin,
    bool clearSettingsPin = false,
    bool? onboardingCompleted,
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
      relayServerUrl:
          clearRelayServerUrl ? null : (relayServerUrl ?? this.relayServerUrl),
      settingsPin: clearSettingsPin ? null : (settingsPin ?? this.settingsPin),
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
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
        'relayServerUrl': relayServerUrl,
        'settingsPin': settingsPin,
        'onboardingCompleted': onboardingCompleted,
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
      relayServerUrl: json['relayServerUrl'] as String?,
      settingsPin: json['settingsPin'] as String?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    );
  }
}
