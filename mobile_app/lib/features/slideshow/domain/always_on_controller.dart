import 'package:wakelock_plus/wakelock_plus.dart';

import 'night_schedule.dart';

/// Injectable seam around the platform wakelock API (`wakelock_plus`), so
/// [AlwaysOnController] can be unit-tested (with a fake/mock implementation)
/// without touching a real platform channel.
abstract class WakelockController {
  Future<void> enable();
  Future<void> disable();
}

/// Real [WakelockController] backed by the `wakelock_plus` plugin. Only
/// ever instantiated by production wiring (e.g. a Riverpod provider) - unit
/// tests inject a fake/mock [WakelockController] instead.
class WakelockPlusController implements WakelockController {
  const WakelockPlusController();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// The three ways the app can decide whether to keep the screen awake.
enum AlwaysOnMode {
  /// Keep the screen on at all times, regardless of whether the slideshow is
  /// actually running. Highest power draw - the settings UI should
  /// recommend this only while the device stays on a charger.
  always,

  /// Keep the screen on only while the slideshow is actively running
  /// (default). The screen is allowed to sleep normally otherwise (e.g. the
  /// user backed out to settings/sources).
  duringSlideshowOnly,

  /// Like [duringSlideshowOnly], but additionally respects the configured
  /// [NightSchedule]: while the slideshow is running during the night
  /// window, the screen is allowed to sleep (saving power) instead of being
  /// forced awake.
  scheduled,
}

/// Decides whether the display should be kept awake ("Dauer-Modus") and
/// applies that decision through an injected [WakelockController].
///
/// This class holds only state and pure decision logic - the constructor
/// makes no platform call. A caller must explicitly trigger evaluation via
/// [applyInitialState], [onSlideshowStarted], [onSlideshowStopped],
/// [updateMode], [updateNightSchedule], or [tick]. That keeps it trivially
/// unit-testable with a fake [WakelockController].
class AlwaysOnController {
  AlwaysOnController({
    required WakelockController wakelock,
    AlwaysOnMode mode = AlwaysOnMode.duringSlideshowOnly,
    NightSchedule nightSchedule = const NightSchedule.disabled(),
  })  : _wakelock = wakelock,
        _mode = mode,
        _nightSchedule = nightSchedule;

  final WakelockController _wakelock;
  AlwaysOnMode _mode;
  NightSchedule _nightSchedule;
  bool _slideshowRunning = false;

  /// Last state actually applied to [WakelockController]. Starts `false`
  /// since a freshly-constructed controller has made no platform call yet
  /// and the OS default (no held wakelock) is already "off" - so the first
  /// [_apply] call must not fire a redundant `disable()` just because
  /// nothing has been applied yet.
  bool _lastApplied = false;

  AlwaysOnMode get mode => _mode;
  NightSchedule get nightSchedule => _nightSchedule;
  bool get isSlideshowRunning => _slideshowRunning;

  /// Whether the wakelock is currently believed to be enabled. Useful for
  /// tests and for a settings UI showing current status.
  bool get isWakelockActive => _lastApplied;

  /// Call once after construction (e.g. from a provider's build method) to
  /// apply whatever the initial computed state should be. Kept separate
  /// from the constructor so construction itself never has side effects.
  Future<void> applyInitialState({DateTime? now}) => _apply(now: now);

  Future<void> updateMode(AlwaysOnMode mode, {DateTime? now}) async {
    _mode = mode;
    await _apply(now: now);
  }

  Future<void> updateNightSchedule(NightSchedule schedule, {DateTime? now}) async {
    _nightSchedule = schedule;
    await _apply(now: now);
  }

  Future<void> onSlideshowStarted({DateTime? now}) async {
    _slideshowRunning = true;
    await _apply(now: now);
  }

  Future<void> onSlideshowStopped({DateTime? now}) async {
    _slideshowRunning = false;
    await _apply(now: now);
  }

  /// Re-evaluates the schedule-based decision. Intended to be called
  /// periodically (e.g. every minute) by a caller-owned timer so
  /// [AlwaysOnMode.scheduled] transitions in/out of the night window even
  /// while nothing else changes.
  Future<void> tick({DateTime? now}) => _apply(now: now);

  bool _computeShouldBeAwake({DateTime? now}) {
    switch (_mode) {
      case AlwaysOnMode.always:
        return true;
      case AlwaysOnMode.duringSlideshowOnly:
        return _slideshowRunning;
      case AlwaysOnMode.scheduled:
        if (!_slideshowRunning) return false;
        final effectiveNow = now ?? DateTime.now();
        return !_nightSchedule.isNightAt(effectiveNow);
    }
  }

  Future<void> _apply({DateTime? now}) async {
    final shouldBeAwake = _computeShouldBeAwake(now: now);
    if (shouldBeAwake == _lastApplied) return;
    _lastApplied = shouldBeAwake;
    if (shouldBeAwake) {
      await _wakelock.enable();
    } else {
      await _wakelock.disable();
    }
  }

  /// Releases the wakelock (if held) and clears applied state. The
  /// controller must not be used after calling this.
  Future<void> dispose() async {
    if (_lastApplied) {
      await _wakelock.disable();
    }
    _lastApplied = false;
  }
}
