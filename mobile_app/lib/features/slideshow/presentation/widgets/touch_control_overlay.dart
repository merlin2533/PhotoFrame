import 'dart:async';

import 'package:flutter/material.dart';

/// Touch handling for the slideshow, per `docs/PLAN.md`:
/// - Tap: show/hide a Pause/Weiter/Info control bar (auto-hides again).
/// - Double-tap: mark favorite. Favorites don't exist yet anywhere in this
///   codebase (no `favorite` field on `PhotoItem`/`MediaIndexEntry`, no
///   persistence) - implementing real favoriting is out of scope for this
///   milestone, so this only shows a "kommt später" acknowledgement rather
///   than silently doing nothing.
/// - Long-press: open Settings (optionally PIN-gated, see [onOpenSettings]).
///
/// Note: the plan also mentions a "Zurück" (previous) control, but
/// `SlideshowEngine` only exposes forward navigation (`skipToNext`) - no
/// history/back-buffer exists to go to a previous item. That control is
/// therefore omitted here rather than wired to a no-op; going back would
/// need an engine change, tracked as a follow-up.
class TouchControlOverlay extends StatefulWidget {
  const TouchControlOverlay({
    super.key,
    required this.child,
    required this.isPaused,
    required this.onTogglePause,
    required this.onNext,
    required this.onShowInfo,
    required this.onOpenSettings,
  });

  final Widget child;
  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onShowInfo;
  final VoidCallback onOpenSettings;

  @override
  State<TouchControlOverlay> createState() => _TouchControlOverlayState();
}

class _TouchControlOverlayState extends State<TouchControlOverlay> {
  bool _controlsVisible = false;
  Timer? _hideTimer;

  void _showControlsTemporarily() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showControlsTemporarily,
      onDoubleTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favoriten kommen später')),
        );
      },
      onLongPress: widget.onOpenSettings,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_controlsVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ControlBar(
                isPaused: widget.isPaused,
                onTogglePause: widget.onTogglePause,
                onNext: widget.onNext,
                onShowInfo: widget.onShowInfo,
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.isPaused,
    required this.onTogglePause,
    required this.onNext,
    required this.onShowInfo,
  });

  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.black.withOpacity(0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white),
            onPressed: onTogglePause,
            tooltip: isPaused ? 'Weiter' : 'Pause',
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            onPressed: onNext,
            tooltip: 'Nächstes Bild',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: onShowInfo,
            tooltip: 'Info',
          ),
        ],
      ),
    );
  }
}
