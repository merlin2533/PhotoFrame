// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PhotoFrame';

  @override
  String commonError(String message) {
    return 'Error: $message';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get settingsGroupSlideshow => 'Slideshow';

  @override
  String get settingsGroupContent => 'Content';

  @override
  String get settingsGroupSharing => 'Sharing';

  @override
  String get settingsGroupGeneral => 'General';

  @override
  String get settingsSlideshowTitle => 'Slideshow';

  @override
  String get settingsSlideshowSubtitle =>
      'Interval, overlays, display mode, transitions';

  @override
  String get settingsAlwaysOnTitle => 'Always-on mode';

  @override
  String get settingsAlwaysOnSubtitle => 'Keep the screen on permanently';

  @override
  String get settingsNightModeTitle => 'Night mode';

  @override
  String get settingsNightModeSubtitle => 'Schedule, dim amount';

  @override
  String get settingsWeatherTitle => 'Weather';

  @override
  String get settingsWeatherSubtitle => 'Overlay on/off, location';

  @override
  String get settingsSourcesTitle => 'Sources';

  @override
  String get settingsSourcesSubtitle => 'Manage folders, shares, Nextcloud';

  @override
  String get settingsCacheTitle => 'Cache management';

  @override
  String get settingsCacheSubtitle => 'Storage used, limit, clear cache';

  @override
  String get settingsPoolTitle => 'Pool/Index';

  @override
  String get settingsPoolSubtitle => 'Working set, refill interval, new images';

  @override
  String get settingsSharingTitle => 'Sharing/Relay';

  @override
  String get settingsSharingSubtitle => 'Relay server URL, pairing';

  @override
  String get settingsAccessibilityTitle => 'Accessibility';

  @override
  String get settingsAutostartHelpTitle => 'Autostart on this phone brand';

  @override
  String get settingsAutostartHelpSubtitle =>
      'Xiaomi, Huawei, Samsung, OnePlus & co.';

  @override
  String get settingsReplayOnboardingTitle => 'Show setup guide again';

  @override
  String get cacheScreenTitle => 'Cache management';

  @override
  String get cacheUsedStorageLabel => 'Storage used';

  @override
  String cacheUsedOfLimit(String used, String limit) {
    return '$used of $limit used';
  }

  @override
  String cacheLimitLabel(String limit) {
    return 'Cache limit: $limit';
  }

  @override
  String get cacheLimitDeviceCapHint =>
      'The limit is additionally capped against the device\'s actually free storage (at least 1 GB/10% reserve).';

  @override
  String get cacheClearButton => 'Clear cache';

  @override
  String get cacheClearedSnackbar => 'Cache cleared';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingAddSourceCta => 'Add source';

  @override
  String get onboardingWelcomeTitle => 'Welcome to PhotoFrame';

  @override
  String get onboardingWelcomeBody =>
      'PhotoFrame turns this device into a digital photo frame: it shows pictures from your folders (e.g. network share, Nextcloud, or local storage) as an endless slideshow and can share photos with other frames. This short guide sets the device up in a few steps.';

  @override
  String get onboardingAlwaysOnTitle => 'Always-on mode: screen stays on';

  @override
  String get onboardingAlwaysOnBody =>
      'A photo frame should stay lit at all times - so PhotoFrame can prevent the screen from turning off or the device from locking. This is the app\'s core feature, but it noticeably costs battery.';

  @override
  String get onboardingAlwaysOnRecommendation =>
      'Recommendation: only use always-on mode while permanently connected to a charger (e.g. wall-mounted). You can later choose between \"always on\", \"only during slideshow\" and a schedule (combined with night mode) in Settings.';

  @override
  String get onboardingAndroidHomeAppTitle => 'Set up as home screen';

  @override
  String get onboardingAndroidHomeAppSkippedBody =>
      'This step only applies to Android devices and is skipped on this device.';

  @override
  String get onboardingAndroidHomeAppBody =>
      'So PhotoFrame appears automatically after every restart, you can set it as the default home screen (home app/launcher): Android settings -> Apps -> Default apps -> Home app -> select PhotoFrame.';

  @override
  String get onboardingOpenAndroidSettings => 'Open Android settings';

  @override
  String get onboardingBatteryOptTitle => 'Exempt from battery optimization';

  @override
  String get onboardingBatteryOptBody =>
      'Android likes to stop background app activity to save battery - this can slow down the slideshow or delay image updates. Exempt PhotoFrame from optimization under \"Battery -> Don\'t optimize\"/\"Ignore battery optimization\" so it keeps running reliably.';

  @override
  String get onboardingOpenAppSettings => 'Open app settings';

  @override
  String get onboardingIosGuidedAccessTitle => 'iOS: Guided Access';

  @override
  String get onboardingIosGuidedAccessBody =>
      'iOS fundamentally does not allow apps to autostart or run a real kiosk mode. The honest, reliable option on iPhone/iPad is the built-in \"Guided Access\" (Settings -> Accessibility -> enable Guided Access, then triple-click the side button while PhotoFrame is open). This has to be manually restarted after every device reboot - that\'s a platform limitation, not a restriction of this app.';

  @override
  String get onboardingAutostartHintsTitle =>
      'Android manufacturers: allow autostart';

  @override
  String get onboardingAutostartHintsIntro =>
      'Many Android manufacturers throttle background apps with their own mechanisms in addition to Android\'s own settings. If PhotoFrame doesn\'t start reliably after a reboot or the slideshow freezes, check the following depending on your manufacturer:';

  @override
  String get onboardingAutostartXiaomi =>
      'Xiaomi / MIUI: In the \"Security\" app, allow PhotoFrame under \"Autostart\" management.';

  @override
  String get onboardingAutostartHuawei =>
      'Huawei / EMUI: Mark PhotoFrame as protected under \"Protected apps\" / the battery manager so it isn\'t killed.';

  @override
  String get onboardingAutostartSamsung =>
      'Samsung: Add PhotoFrame under Battery -> \"Unmonitored apps\" so Samsung doesn\'t automatically close the app.';

  @override
  String get onboardingAutostartOnePlusOppoVivo =>
      'OnePlus / OPPO / Vivo: Whitelist PhotoFrame in the battery/autostart settings (often called \"Autostart manager\" or \"Battery optimization\").';

  @override
  String get onboardingAutostartOutro =>
      'The exact menu labels differ slightly depending on the Android version and manufacturer skin. This page deliberately does not open manufacturer-specific settings automatically, since their paths change too often - use your device\'s app/battery settings instead.';

  @override
  String get onboardingAddSourceTitle => 'Add a source';

  @override
  String get onboardingAddSourceBody =>
      'Almost done! Now add an image source (e.g. a local folder, a network share, or Nextcloud) so the slideshow can start. You can also do this later at any time via Settings -> Sources.';

  @override
  String get onboardingAndroidOnlyStepBody =>
      'This step only applies to Android devices and is skipped on this device.';
}
