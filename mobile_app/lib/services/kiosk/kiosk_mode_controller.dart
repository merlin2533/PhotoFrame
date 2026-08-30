import 'package:flutter/services.dart';

/// Injectable seam around the platform kiosk MethodChannel
/// ("photoframe/kiosk"), analogous to `WakelockController` in
/// `../../features/slideshow/domain/always_on_controller.dart` - lets
/// callers (and tests) avoid a hard dependency on a real platform channel.
///
/// See docs/DECISIONS.md ADR-004 for why this exists at all: Android kiosk
/// behaviour on this app is "register as Home app" (see AndroidManifest.xml)
/// combined with screen pinning ("Lock Task Mode") entered/left through this
/// controller around the slideshow's lifecycle.
abstract class KioskModeController {
  /// Requests screen pinning (Android `startLockTask()`). Honest limits,
  /// documented here rather than only in the settings UI so any future
  /// caller sees them too:
  ///
  /// - This app is not a Device Owner/enterprise MDM tool, so it only ever
  ///   gets "unprivileged" Lock Task Mode. Android still shows a small
  ///   "leave pinning" affordance at the top of the screen in that mode -
  ///   that is platform behaviour and cannot be fully suppressed from here.
  /// - This call can fail (e.g. `IllegalStateException` on the Android
  ///   side if the activity isn't in a state that allows entering Lock Task
  ///   Mode, or simply no-op on a platform without this channel, such as
  ///   iOS/desktop/tests). Implementations must swallow such failures -
  ///   entering kiosk mode is a best-effort enhancement, never something the
  ///   slideshow should crash or blank over.
  Future<void> start();

  /// Requests leaving screen pinning (Android `stopLockTask()`). Like
  /// [start], must never throw - calling this while pinning was never
  /// active (or on a platform without support) is expected to be a no-op.
  Future<void> stop();
}

/// Real [KioskModeController] backed by the "photoframe/kiosk" MethodChannel
/// hosted by `MainActivity.kt` on Android. Only ever instantiated by
/// production wiring (e.g. a Riverpod provider) - unit/widget tests inject a
/// fake/mock [KioskModeController] instead, since there is no real Android
/// host to exercise `startLockTask()`/`stopLockTask()` against in this
/// environment.
class MethodChannelKioskModeController implements KioskModeController {
  MethodChannelKioskModeController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('photoframe/kiosk');

  final MethodChannel _channel;

  @override
  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('startKioskMode');
    } on MissingPluginException {
      // No platform handler registered - e.g. iOS/desktop/`flutter test`.
      // Kiosk mode is an Android-only enhancement (ADR-004); silently no-op
      // rather than surfacing a platform-not-supported error to the UI.
    } on PlatformException {
      // `startLockTask()` threw on the Android side (see doc comment on
      // `KioskModeController.start`). Best-effort only - never propagate.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopKioskMode');
    } on MissingPluginException {
      // See `start` - no platform handler registered.
    } on PlatformException {
      // `stopLockTask()` threw (e.g. pinning was never active) - harmless.
    }
  }
}
