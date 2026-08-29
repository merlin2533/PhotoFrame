import 'dart:async';

import 'package:flutter/material.dart';

/// Touch handling for the slideshow, per `docs/PLAN.md`:
/// - Tap: show/hide a Pause/Weiter/Info/Favorit control bar (auto-hides
///   again).
/// - Double-tap: toggle favorite (see `FavoritesStore`), when
///   [onToggleFavorite] is supplied. If it isn't (e.g. no current item to
///   favorite yet), this falls back to a "kommt später"-style
///   acknowledgement rather than silently doing nothing.
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
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  final Widget child;
  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onShowInfo;
  final VoidCallback onOpenSettings;

  /// Whether the currently-shown item is favorited, per `FavoritesStore`.
  final bool isFavorite;

  /// Toggles the favorite state of the currently-shown item. `null` when
  /// there is no current item to favorite (e.g. still loading), in which
  /// case double-tap/the favorite button fall back to an acknowledgement
  /// message instead of doing nothing silently.
  final VoidCallback? onToggleFavorite;

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

  void _toggleFavorite(BuildContext context) {
    final onToggleFavorite = widget.onToggleFavorite;
    if (onToggleFavorite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Bild zum Favorisieren geladen')),
      );
      return;
    }
    final wasFavorite = widget.isFavorite;
    onToggleFavorite();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasFavorite ? 'Favorit entfernt' : 'Als Favorit markiert'),
      ),
    );
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
      onDoubleTap: () => _toggleFavorite(context),
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
                isFavorite: widget.isFavorite,
                onToggleFavorite: () => _toggleFavorite(context),
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
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onShowInfo;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.black.withValues(alpha: 0.5),
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
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.redAccent : Colors.white,
            ),
            onPressed: onToggleFavorite,
            tooltip: isFavorite ? 'Favorit entfernen' : 'Als Favorit markieren',
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
