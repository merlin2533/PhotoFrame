// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get smallPhotoPreparationTitle => 'Preparation (downscaling) enabled';

  @override
  String get smallPhotoPreparationSubtitle =>
      'Off: photos are shown unscaled; the slideshow then uses less background processing and memory.';

  @override
  String get settingsLogTitle => 'Log';

  @override
  String get settingsLogSubtitle => 'View recent notices and errors of the app';

  @override
  String get settingsErrorReportsTitle => 'Send error reports';

  @override
  String get settingsErrorReportsSubtitle =>
      'Anonymous error reports help find problems. Photos and file names are never sent.';

  @override
  String get logScreenTitle => 'Log';

  @override
  String get logEmptyState => 'No entries yet.';

  @override
  String get logCopyAction => 'Copy';

  @override
  String get logClearAction => 'Clear';

  @override
  String get logClearConfirmTitle => 'Clear log?';

  @override
  String get logClearConfirmBody => 'All entries in the log will be removed.';

  @override
  String get logCopiedMessage => 'Log copied to the clipboard.';

  @override
  String get appTitle => 'PhotoFrame';

  @override
  String get preparingTitle => 'Preparing slideshow';

  @override
  String preparingProgress(int done, int total) {
    return '$done of $total photos prepared';
  }

  @override
  String get preparingProgressUnknown => 'Preparing photos…';

  @override
  String preparingProgressQueue(int done, int total, int waiting) {
    return '$done of $total photos prepared · $waiting in queue';
  }

  @override
  String preparingDownloaded(String size) {
    return '$size downloaded';
  }

  @override
  String preparingRate(String rate) {
    return 'Speed: $rate';
  }

  @override
  String preparingConversions(int count) {
    return 'Open conversions: $count';
  }

  @override
  String preparingCacheCount(int count) {
    return '$count photos in cache';
  }

  @override
  String preparingSwapToday(int swapped, int pool) {
    return 'Swapped today: $swapped of $pool';
  }

  @override
  String preparingSwapDailyPercent(int percent) {
    return 'Daily swap: $percent %';
  }

  @override
  String preparingSwapDailyCount(int percent, int perDay) {
    return 'Daily swap: $percent % ($perDay photos per day)';
  }

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
  String get settingsKioskTitle => 'Photo frame home screen';

  @override
  String get settingsKioskSubtitle => 'Set up as home screen, pin the screen';

  @override
  String get kioskScreenTitle => 'Photo frame home screen';

  @override
  String get kioskToggleTitle => 'Use as photo frame home screen';

  @override
  String get kioskToggleSubtitle =>
      'Registers the app as a home screen and pins the screen while the slideshow runs';

  @override
  String get kioskIntro =>
      'Turns this device into a dedicated digital photo frame: PhotoFrame becomes selectable as the home screen (home app), and the screen is pinned (screen pinning) when the slideshow starts, so nobody accidentally switches to another app.';

  @override
  String get kioskExitNowButton => 'Exit screen pinning now';

  @override
  String get kioskHomeAppNote =>
      'After enabling this, the next time you press the Home button a system dialog appears letting you set PhotoFrame as the default home screen. You have to confirm that yourself - Android does not let apps confirm or bypass that dialog automatically.';

  @override
  String get kioskPinningNote =>
      'As soon as the slideshow starts, the screen is pinned (screen pinning). Since this app has no device-owner/MDM privileges, Android may show a small \"unpin\"/\"exit\" hint at the top of the screen while pinned - that is platform behaviour and cannot be fully suppressed by this app.';

  @override
  String get kioskAndroidOnlyNote =>
      'Android only. iOS has no comparable autostart mechanism for third-party apps - there, only the built-in \"Guided Access\" helps (see onboarding).';

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
  String cacheImageCount(int count) {
    return '$count images cached';
  }

  @override
  String get cacheBySourceTitle => 'By source';

  @override
  String cacheSourceUsage(int count, String size) {
    return '$count images · $size';
  }

  @override
  String get cacheUnknownSource => 'Unknown source';

  @override
  String get cacheUnknownSourceHint =>
      'Slides from sources that are no longer set up';

  @override
  String get cacheDeleteSourceTooltip => 'Delete cache of this source';

  @override
  String get cacheDeleteSourceTitle => 'Delete cache?';

  @override
  String cacheDeleteSourceBody(int count, String source) {
    return '$count prepared images of \"$source\" will be deleted. They are created again during the next index run.';
  }

  @override
  String cacheDeleteUnassignedBody(int count) {
    return '$count prepared images of sources that are no longer set up will be deleted.';
  }

  @override
  String get cacheDeleteConfirm => 'Delete';

  @override
  String cacheDeletedSnackbar(int count) {
    return '$count images deleted';
  }

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

  @override
  String get onboardingPermissionsTitle => 'Camera & photos access';

  @override
  String get onboardingPermissionsBody =>
      'PhotoFrame needs camera access to scan pairing QR codes, and access to your photos to use local images as a slideshow source. Tap below to grant access right now.';

  @override
  String get onboardingRequestCameraPermission => 'Allow camera access';

  @override
  String get onboardingRequestPhotosPermission => 'Allow photos access';

  @override
  String get onboardingPermissionStatusUnknown => 'not requested yet';

  @override
  String get onboardingPermissionStatusGranted => 'granted';

  @override
  String get onboardingPermissionStatusDenied => 'denied';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Set the app\'s language';

  @override
  String get languageScreenTitle => 'Language';

  @override
  String get languageSystemOption => 'System language';

  @override
  String get pairingSendConfigButton => 'Send configuration to device';

  @override
  String get pairingNoRelayHint =>
      'Set up a relay server first to pair devices.';

  @override
  String get pairingNoActivePairingHint => 'No pairing group connected yet.';

  @override
  String configPushConfirmSmbTitle(String senderLabel) {
    return 'Apply new SMB source from $senderLabel?';
  }

  @override
  String get slideDecodeFailed => 'Cannot be decoded';

  @override
  String rotationSwapPercentLabel(int percent) {
    return 'Daily share swapped: $percent %';
  }

  @override
  String rotationRenewalDaysLabel(int days) {
    return 'Whole pool renewed after $days days';
  }

  @override
  String get settingsCrashReportTitle => 'Send crash report';

  @override
  String get settingsCrashReportSubtitle =>
      'Sends diagnostic data to the developer. No photo names, no credentials.';

  @override
  String get crashReportConfirmTitle => 'Send crash report?';

  @override
  String get crashReportConfirmBody =>
      'Sent: the latest trace entries, app version, device model, Android version, cache count and size, cache limit, preparation switch and number of sources. No photo names, no addresses, no credentials.';

  @override
  String get crashReportConfirmCancel => 'Cancel';

  @override
  String get crashReportConfirmSend => 'Send';

  @override
  String get crashReportErrorReportsOff => 'Error reports are switched off';

  @override
  String get crashReportSent => 'Crash report sent';

  @override
  String get crashReportFailed => 'Crash report could not be sent';

  @override
  String get overlayResume => 'Resume';

  @override
  String get overlayPause => 'Pause';

  @override
  String get overlayNextPhoto => 'Next photo';

  @override
  String get overlayFavoriteRemove => 'Remove favorite';

  @override
  String get overlayFavoriteAdd => 'Mark as favorite';

  @override
  String get overlayInfo => 'Info';

  @override
  String get overlayHome => 'Home';

  @override
  String get overlaySettings => 'Settings';

  @override
  String get homeNoSourceYet => 'No source set up yet';

  @override
  String homeSourcesActive(int enabled, int total) {
    return '$enabled of $total sources active';
  }

  @override
  String get homePhotosInIndex => 'Photos in index';

  @override
  String get homeIndexStand => 'Index status';

  @override
  String get homeIndexNotBuilt => 'not built yet';

  @override
  String get homePreparedStatus => 'Downscaled';

  @override
  String homePreparedCount(int done, int total) {
    return '$done of $total';
  }

  @override
  String homePreparedRunning(int done, int total, int waiting) {
    return '$done of $total (running, $waiting waiting)';
  }

  @override
  String get homeDownloadedStatus => 'Downloaded';

  @override
  String homeDownloadedCount(int count) {
    return '$count photos';
  }

  @override
  String get homeStartSlideshow => 'Start slideshow';

  @override
  String get homeOverview => 'Overview';

  @override
  String get homeSlideshowHint =>
      'In the slideshow, you reach this page with the home icon.';

  @override
  String slideshowSettingsInterval(int seconds) {
    return 'Interval: $seconds s';
  }

  @override
  String slideshowSettingsIntervalValue(int seconds) {
    return '$seconds s';
  }

  @override
  String get slideshowSettingsOverlays => 'Overlays';

  @override
  String get slideshowSettingsShowSourceLabel => 'Show folder name/source';

  @override
  String get slideshowSettingsShowCaption => 'Show date as caption';

  @override
  String get slideshowSettingsShowCaptionSubtitle =>
      'Bottom left: capture date and folder';

  @override
  String get slideshowSettingsShowClock => 'Show clock';

  @override
  String get slideshowSettingsClockAtTop => 'Clock at top left';

  @override
  String get slideshowSettingsClockAtTopSubtitle => 'Off: bottom left';

  @override
  String get slideshowSettingsDisplayMode => 'Display mode';

  @override
  String get slideshowSettingsDisplayContain => 'Fit (contain)';

  @override
  String get slideshowSettingsDisplayCover => 'Fill (cover)';

  @override
  String get slideshowSettingsDisplayBlurred => 'Blurred background';

  @override
  String get slideshowSettingsDisplayBlurredSubtitle =>
      'Shows portrait photos without black bars';

  @override
  String get slideshowSettingsTransitions => 'Transitions';

  @override
  String get slideshowSettingsTransFade => 'Crossfade (fade)';

  @override
  String get slideshowSettingsTransSlide => 'Slide';

  @override
  String get slideshowSettingsTransZoom => 'Zoom (fade in)';

  @override
  String get slideshowSettingsTransSlideUp => 'Slide up';

  @override
  String get slideshowSettingsTransBlur => 'Blur';

  @override
  String get slideshowSettingsTransFlip => 'Flip';

  @override
  String get slideshowSettingsTransRandom =>
      'Random (a different one each time)';

  @override
  String get slideshowSettingsTransNone => 'No transition';

  @override
  String get slideshowSettingsKenBurns => 'Ken Burns effect';

  @override
  String get slideshowSettingsKenBurnsSubtitle =>
      'Slow zoom/pan over the image';

  @override
  String get slideshowSettingsPortraitPair => 'Portrait pair layout';

  @override
  String get slideshowSettingsPortraitPairSubtitle =>
      'Two consecutive portrait photos side by side';

  @override
  String get slideshowSettingsLayout => 'Layout';

  @override
  String get slideshowSettingsLayoutSingle => 'Single photo';

  @override
  String get slideshowSettingsLayoutGrid => '2×2 grid';

  @override
  String get slideshowSettingsImageDetails => 'Photo details';

  @override
  String get slideshowSettingsImageDetailsSwitch => 'Show folder and date';

  @override
  String get slideshowSettingsImageDetailsSubtitle =>
      'At the bottom of the photo: source, folder, capture date';

  @override
  String get slideshowSettingsLeft => 'Left';

  @override
  String get slideshowSettingsRight => 'Right';

  @override
  String get slideshowSettingsFavoritesAndDate => 'Favorites & date';

  @override
  String get slideshowSettingsFavoritesOnly => 'Show favorites only';

  @override
  String get slideshowSettingsFavoritesOnlySubtitle =>
      'The slideshow only uses favorite photos';

  @override
  String get slideshowSettingsOnThisDay =>
      'Prefer photos from this day in earlier years';

  @override
  String get slideshowSettingsOnThisDaySubtitle =>
      'Prefers showing photos from this day in the past';
}
