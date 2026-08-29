/// How a [NightSchedule] decides whether "night" (dimmed/quiet) behaviour is
/// currently active.
enum NightScheduleMode {
  /// Never active - the slideshow behaves the same around the clock.
  disabled,

  /// Active between a fixed [NightSchedule.startHour]/[NightSchedule.startMinute]
  /// and [NightSchedule.endHour]/[NightSchedule.endMinute], every day.
  fixedRange,

  /// Active between local sunset and sunrise.
  ///
  /// NOTE (design decision): a fully offline, location-aware sunrise/sunset
  /// calculation needs the device's latitude/longitude, which this
  /// milestone does not plumb through (no location permission flow exists
  /// yet). Rather than block this feature on that separate piece of work,
  /// [isNightAt] falls back to a fixed approximate window (20:00-07:00) for
  /// this mode, clearly marked below. Wiring real geolocation + a solar
  /// calculation (e.g. NOAA's algorithm) is left as a follow-up once
  /// location permissions are designed.
  sunsetSunrise,
}

/// User-configurable schedule describing when "night mode" (screen dimming,
/// and - combined with [AlwaysOnMode.scheduled] - allowing the display to
/// sleep) should be active.
class NightSchedule {
  const NightSchedule({
    this.mode = NightScheduleMode.disabled,
    this.startHour = 22,
    this.startMinute = 0,
    this.endHour = 7,
    this.endMinute = 0,
    this.dimAmount = 0.6,
  })  : assert(startHour >= 0 && startHour < 24),
        assert(endHour >= 0 && endHour < 24),
        assert(startMinute >= 0 && startMinute < 60),
        assert(endMinute >= 0 && endMinute < 60),
        assert(dimAmount >= 0 && dimAmount <= 1);

  const NightSchedule.disabled() : this(mode: NightScheduleMode.disabled);

  /// Approximate fallback window used for [NightScheduleMode.sunsetSunrise]
  /// until real solar-position based calculation is implemented (see
  /// [NightScheduleMode.sunsetSunrise] doc comment).
  static const int _approxSunsetHour = 20;
  static const int _approxSunriseHour = 7;

  final NightScheduleMode mode;

  /// Start of the night window, used only for [NightScheduleMode.fixedRange].
  final int startHour;
  final int startMinute;

  /// End of the night window, used only for [NightScheduleMode.fixedRange].
  final int endHour;
  final int endMinute;

  /// How strongly to dim the display during the night window, `0` (no
  /// dimming) to `1` (fully dark overlay).
  final double dimAmount;

  /// Whether "night" behaviour should be active at [now].
  bool isNightAt(DateTime now) {
    switch (mode) {
      case NightScheduleMode.disabled:
        return false;
      case NightScheduleMode.fixedRange:
        return _withinMinutesRange(
          now,
          startHour: startHour,
          startMinute: startMinute,
          endHour: endHour,
          endMinute: endMinute,
        );
      case NightScheduleMode.sunsetSunrise:
        return _withinMinutesRange(
          now,
          startHour: _approxSunsetHour,
          startMinute: 0,
          endHour: _approxSunriseHour,
          endMinute: 0,
        );
    }
  }

  static bool _withinMinutesRange(
    DateTime now, {
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) {
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;
    if (startMinutes == endMinutes) return false;
    if (startMinutes < endMinutes) {
      // e.g. 01:00 - 06:00, doesn't cross midnight.
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
    // e.g. 22:00 - 07:00, crosses midnight.
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  NightSchedule copyWith({
    NightScheduleMode? mode,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    double? dimAmount,
  }) {
    return NightSchedule(
      mode: mode ?? this.mode,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      dimAmount: dimAmount ?? this.dimAmount,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'dimAmount': dimAmount,
      };

  factory NightSchedule.fromJson(Map<String, dynamic> json) {
    return NightSchedule(
      mode: NightScheduleMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => NightScheduleMode.disabled,
      ),
      startHour: json['startHour'] as int? ?? 22,
      startMinute: json['startMinute'] as int? ?? 0,
      endHour: json['endHour'] as int? ?? 7,
      endMinute: json['endMinute'] as int? ?? 0,
      dimAmount: (json['dimAmount'] as num?)?.toDouble() ?? 0.6,
    );
  }
}
