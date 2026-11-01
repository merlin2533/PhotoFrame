import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/slideshow/domain/transition_picker.dart';

void main() {
  test('never picks the same effect twice in a row', () {
    final picker = TransitionPicker(random: Random(1));
    SlideshowTransition? previous;
    for (var i = 0; i < 500; i++) {
      final picked = picker.next();
      expect(picked, isNot(previous), reason: 'pick $i repeats $previous');
      previous = picked;
    }
  });

  test('uses every animated effect and never none or random', () {
    final picker = TransitionPicker(random: Random(2));
    final seen = <SlideshowTransition>{};
    for (var i = 0; i < 500; i++) {
      seen.add(picker.next());
    }
    expect(seen, equals(TransitionPicker.pool.toSet()));
    expect(TransitionPicker.pool, isNot(contains(SlideshowTransition.none)));
    expect(TransitionPicker.pool, isNot(contains(SlideshowTransition.random)));
  });
}
