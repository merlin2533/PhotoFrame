import 'dart:math';

import '../../settings/domain/app_settings.dart';

/// Picks the effect for the "random" transition setting.
///
/// Every pick differs from the previous one, so the same effect never runs
/// twice in a row. "none" is not part of the pool: it means no animation.
class TransitionPicker {
  TransitionPicker({Random? random}) : _random = random ?? Random();

  static const pool = [
    SlideshowTransition.fade,
    SlideshowTransition.slide,
    SlideshowTransition.zoom,
    SlideshowTransition.slideUp,
    SlideshowTransition.blurFade,
    SlideshowTransition.flip,
  ];

  final Random _random;
  SlideshowTransition? _last;

  SlideshowTransition next() {
    final candidates = [
      for (final transition in pool)
        if (transition != _last) transition,
    ];
    final picked = candidates[_random.nextInt(candidates.length)];
    _last = picked;
    return picked;
  }
}
