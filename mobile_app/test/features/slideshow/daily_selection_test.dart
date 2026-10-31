import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/slideshow/domain/daily_selection.dart';

void main() {
  final eligible = List<String>.generate(100, (i) => 'p$i');
  String keyOf(String s) => s;

  test('everything fits: returns all eligible in order', () {
    final picked = DailySelection.pick(
      eligible: eligible.take(5).toList(),
      keyOf: keyOf,
      count: 10,
      today: '2026-10-31',
    );
    expect(picked, eligible.take(5).toList());
  });

  test('new day draws count random photos', () {
    final picked = DailySelection.pick(
      eligible: eligible,
      keyOf: keyOf,
      count: 10,
      today: '2026-10-31',
      savedDay: '2026-10-30',
      savedKeys: const ['p1', 'p2'],
      random: Random(1),
    );
    expect(picked.length, 10);
  });

  test('same day keeps the saved selection that still exists', () {
    final picked = DailySelection.pick(
      eligible: eligible,
      keyOf: keyOf,
      count: 10,
      today: '2026-10-31',
      savedDay: '2026-10-31',
      savedKeys: const ['p7', 'gone', 'p3'],
    );
    expect(picked, ['p7', 'p3']);
  });

  test('same day with no saved photo left draws a new sample', () {
    final picked = DailySelection.pick(
      eligible: eligible,
      keyOf: keyOf,
      count: 10,
      today: '2026-10-31',
      savedDay: '2026-10-31',
      savedKeys: const ['gone'],
      random: Random(2),
    );
    expect(picked.length, 10);
  });

  test('dayKey is zero-padded', () {
    expect(DailySelection.dayKey(DateTime(2026, 3, 4)), '2026-03-04');
  });
}
