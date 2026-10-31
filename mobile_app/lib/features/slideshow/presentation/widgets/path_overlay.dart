import 'package:flutter/material.dart';

/// Always-visible source and file path of the shown photo, centred near the
/// bottom edge (above the system navigation bar).
class PathOverlay extends StatelessWidget {
  const PathOverlay({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 64,
      child: SafeArea(
        top: false,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
