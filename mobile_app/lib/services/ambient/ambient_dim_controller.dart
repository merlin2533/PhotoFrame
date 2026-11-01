/// Pure Dart logic for ambient dimming. No Flutter or platform imports, so it
/// is unit-testable without a device.
///
/// Maps ambient light (lux) to a black overlay opacity in `0..maxOpacity`
/// with hysteresis:
///  * Switches to "dark" when lux drops below [darkLux].
///  * Switches back to "bright" only when lux rises above [brightLux], so
///    the overlay does not flicker around a single threshold.
///  * While dark, opacity falls linearly from [maxOpacity] at 0 lux to 0 at
///    [brightLux]. While bright, opacity is 0.
class AmbientDimController {
  AmbientDimController({
    this.darkLux = 5,
    this.brightLux = 20,
    this.maxOpacity = 0.8,
  })  : assert(darkLux >= 0),
        assert(brightLux > darkLux),
        assert(maxOpacity >= 0 && maxOpacity <= 1);

  final double darkLux;
  final double brightLux;
  final double maxOpacity;

  bool _dark = false;
  double _opacity = 0;

  /// Whether the controller is currently in the dark (dimming) state.
  bool get isDark => _dark;

  /// The opacity computed by the last [update] call (0 before any update).
  double get opacity => _opacity;

  /// Feeds one lux reading and returns the new opacity. A `NaN` reading is
  /// ignored and returns the previous opacity unchanged.
  double update(double lux) {
    if (lux.isNaN) return _opacity;
    if (_dark) {
      if (lux > brightLux) _dark = false;
    } else {
      if (lux < darkLux) _dark = true;
    }
    _opacity = _dark ? _mapLuxToOpacity(lux) : 0;
    return _opacity;
  }

  /// Back to the initial bright state with zero opacity.
  void reset() {
    _dark = false;
    _opacity = 0;
  }

  double _mapLuxToOpacity(double lux) {
    final fraction = (lux / brightLux).clamp(0.0, 1.0);
    return maxOpacity * (1 - fraction);
  }
}

/// Whether [now] lies inside the dimming window `[startMinutes, endMinutes)`.
///
/// Minutes are minutes since local midnight (`hour * 60 + minute`), 0..1439.
/// The window may cross midnight: with start 22:00 and end 06:00, 23:00 and
/// 05:00 are inside, 12:00 is outside. If [startMinutes] equals
/// [endMinutes] the window is empty and this returns `false`.
bool isWithinDimWindow(
  DateTime now, {
  required int startMinutes,
  required int endMinutes,
}) {
  final minutes = now.hour * 60 + now.minute;
  if (startMinutes == endMinutes) return false;
  if (startMinutes < endMinutes) {
    return minutes >= startMinutes && minutes < endMinutes;
  }
  // Crosses midnight.
  return minutes >= startMinutes || minutes < endMinutes;
}
