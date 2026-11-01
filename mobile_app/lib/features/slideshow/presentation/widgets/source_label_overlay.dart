import 'package:flutter/material.dart';

import 'overlay_text_panel.dart';

/// Caption panel naming the source/folder an item came from. Always
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
      child: IgnorePointer(
        child: OverlayTextPanel(
          child: Text(label, style: overlayTextStyle),
        ),
      ),
    );
  }
}
