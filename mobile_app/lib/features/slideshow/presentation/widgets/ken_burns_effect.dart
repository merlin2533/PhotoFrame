import 'dart:math';

import 'package:flutter/material.dart';

/// Wraps [child] with a slow, continuous zoom/pan ("Ken Burns effect") over
/// [duration]. Meant to wrap exactly one displayed slide - give it a `key`
/// that changes per slide (e.g. `ValueKey(item.id)`, matching the key
/// already used for [SlideRenderer] in `slideshow_screen.dart`) so Flutter
/// tears down and recreates the whole [State] - and with it, the
/// [AnimationController] and randomized start/end alignment - for every new
/// image, rather than a single animation looping/jumping across images.
///
/// Purely a presentation-layer effect: whether it is used at all is decided
/// by the caller via `EffectiveVisualSettings.kenBurnsEnabled` (see
/// `effective_visual_settings.dart`), which also accounts for the
/// "Bewegung reduzieren" accessibility signal.
class KenBurnsEffect extends StatefulWidget {
  const KenBurnsEffect({
    super.key,
    required this.child,
    required this.duration,
  });

  final Widget child;

  /// How long the zoom/pan takes to complete. Typically the slideshow's
  /// configured per-image interval, so the effect finishes roughly when the
  /// image is about to change.
  final Duration duration;

  @override
  State<KenBurnsEffect> createState() => _KenBurnsEffectState();
}

class _KenBurnsEffectState extends State<KenBurnsEffect>
    with SingleTickerProviderStateMixin {
  static const double _minZoom = 1.0;
  static const double _maxZoom = 1.15;

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<Alignment> _alignment;

  @override
  void initState() {
    super.initState();
    // Guard against a pathologically short/zero interval making the zoom
    // imperceptible or the controller misbehave.
    final effectiveDuration =
        widget.duration < const Duration(seconds: 2) ? const Duration(seconds: 8) : widget.duration;

    _controller = AnimationController(vsync: this, duration: effectiveDuration)..forward();

    _scale = Tween<double>(begin: _minZoom, end: _maxZoom).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Randomize the pan direction per instance (i.e. per slide, given this
    // widget is recreated per `key`) so consecutive images don't all zoom
    // toward the exact same corner.
    final random = Random();
    _alignment = AlignmentTween(
      begin: _randomAlignment(random),
      end: _randomAlignment(random),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  static Alignment _randomAlignment(Random random) {
    // Bias toward the edges/corners (rather than dead-center, which would
    // make the pan invisible) by sampling from [-1, 1] on both axes.
    return Alignment(random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          alignment: _alignment.value,
          child: child,
        );
      },
    );
  }
}
