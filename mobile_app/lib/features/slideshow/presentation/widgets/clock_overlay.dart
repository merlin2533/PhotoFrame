import 'dart:async';

import 'package:flutter/material.dart';

/// Live clock text, no positioning/decoration - the raw content also reused
/// by `slideshow_screen.dart` when it combines the clock with
/// [WeatherOverlayContent] into one info-bar pill (see that screen's build
/// method and `weather_overlay.dart`'s doc comment for the positioning
/// rationale).
class ClockText extends StatefulWidget {
  const ClockText({super.key, this.now});

  /// Source of the current time, [DateTime.now] when `null`. Only tests set
  /// it, to drive the clock deterministically.
  final DateTime Function()? now;

  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = _currentTime();
    _scheduleNextMinute();
  }

  DateTime _currentTime() => widget.now?.call() ?? DateTime.now();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The display only shows hours, minutes and the date, so it changes at
  /// most once per minute. A one-shot timer aligned to the next minute
  /// boundary avoids waking the UI thread every second.
  void _scheduleNextMinute() {
    final now = _currentTime();
    final msIntoMinute = now.second * 1000 + now.millisecond;
    // Small margin so the timer does not fire just before the boundary.
    final delay = Duration(milliseconds: 60000 - msIntoMinute + 20);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = _currentTime());
      _scheduleNextMinute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    // Calm display: a large, light time with the date below it.
    const dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final date =
        '${dayNames[_now.weekday - 1]}, ${_now.day.toString().padLeft(2, '0')}.${_now.month.toString().padLeft(2, '0')}.';
    // Isolates the clock's repaints from the rest of the slideshow layers.
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w300,
              height: 1.0,
            ),
          ),
          Text(
            date,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Live clock overlay, standalone pill positioned bottom-left when
/// [SourceLabelOverlay] (see `source_label_overlay.dart`) occupies
/// bottom-right, so both can be shown at once without overlapping.
///
/// Used as-is when only the clock (not the weather overlay) is enabled; see
/// `slideshow_screen.dart` for the combined-bar case.
class ClockOverlay extends StatelessWidget {
  const ClockOverlay({super.key, this.atTop = false});

  /// Top-left corner instead of bottom-left.
  final bool atTop;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      top: atTop ? 16 : null,
      bottom: atTop ? null : 16,
      child: const InfoBarPill(child: ClockText()),
    );
  }
}

/// Shared pill decoration for the bottom-left info bar (clock/weather,
/// alone or combined) and the bottom-right source label.
class InfoBarPill extends StatelessWidget {
  const InfoBarPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
