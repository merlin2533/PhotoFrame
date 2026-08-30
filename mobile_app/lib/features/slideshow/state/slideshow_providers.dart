import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/kiosk/kiosk_mode_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_providers.dart';
import '../domain/always_on_controller.dart';

/// Single, app-lifetime [AlwaysOnController] wired to the real
/// [WakelockPlusController] and kept in sync with [settingsProvider]'s
/// `alwaysOnMode`/`nightSchedule`. The slideshow screen calls
/// [AlwaysOnController.onSlideshowStarted]/[AlwaysOnController.onSlideshowStopped]
/// around its own lifecycle; this provider only owns the mode/schedule sync
/// so "Dauer-Modus" settings changes take effect immediately even while a
/// slideshow is already running.
final Provider<AlwaysOnController> alwaysOnControllerProvider =
    Provider<AlwaysOnController>((ref) {
  final controller = AlwaysOnController(wakelock: const WakelockPlusController());
  ref.onDispose(() {
    unawaited(controller.dispose());
  });

  ref.listen<AsyncValue<AppSettings>>(
    settingsProvider,
    (previous, next) {
      final settings = next.valueOrNull;
      if (settings == null) return;
      unawaited(controller.updateMode(settings.alwaysOnMode));
      unawaited(controller.updateNightSchedule(settings.nightSchedule));
    },
    fireImmediately: true,
  );

  return controller;
});

/// Single, app-lifetime [KioskModeController] backed by the real
/// "photoframe/kiosk" MethodChannel. `slideshow_screen.dart` calls
/// [KioskModeController.start]/[KioskModeController.stop] around its own
/// lifecycle, gated on `AppSettings.kioskModeEnabled` - see ADR-004 and
/// `kiosk_settings_screen.dart` for the full picture. Overridden in widget
/// tests with a fake implementation so tests never touch a real platform
/// channel.
final Provider<KioskModeController> kioskModeControllerProvider =
    Provider<KioskModeController>((ref) {
  return MethodChannelKioskModeController();
});
