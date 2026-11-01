import 'package:flutter/material.dart';

/// Text style for the slide captions: white, 16 logical pixels, so the text
/// stays readable on any photo.
const TextStyle overlayTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w500,
  height: 1.25,
);

/// Solid dark panel behind a caption. Semi-transparent black (about 70 %
/// opacity) gives white text enough contrast on bright and dark photos alike.
class OverlayTextPanel extends StatelessWidget {
  const OverlayTextPanel({super.key, required this.child});

  /// Usually a [Text] styled with [overlayTextStyle].
  final Widget child;

  /// Background color of every caption panel.
  static const Color backgroundColor = Color(0xB3000000);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
