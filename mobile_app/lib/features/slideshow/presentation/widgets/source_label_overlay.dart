import 'package:flutter/material.dart';

/// Small pill overlay naming the source/folder an item came from. Always
/// bottom-right per `docs/PLAN.md` ("Ordnername immer unten rechts
/// einblendbar"); visibility is controlled by the caller via
/// `AppSettings.showSourceLabel`.
class SourceLabelOverlay extends StatelessWidget {
  const SourceLabelOverlay({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: _OverlayPill(child: Text(label, style: const TextStyle(color: Colors.white))),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.child});

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
