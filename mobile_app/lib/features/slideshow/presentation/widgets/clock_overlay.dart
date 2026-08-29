import 'dart:async';

import 'package:flutter/material.dart';

/// Live clock text, no positioning/decoration - the raw content also reused
/// by `slideshow_screen.dart` when it combines the clock with
/// [WeatherOverlayContent] into one info-bar pill (see that screen's build
/// method and `weather_overlay.dart`'s doc comment for the positioning
/// rationale).
class ClockText extends StatefulWidget {
  const ClockText({super.key});

  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
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
  const ClockOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 16,
      bottom: 16,
      child: InfoBarPill(child: ClockText()),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
