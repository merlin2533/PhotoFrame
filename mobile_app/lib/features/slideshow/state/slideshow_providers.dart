import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
