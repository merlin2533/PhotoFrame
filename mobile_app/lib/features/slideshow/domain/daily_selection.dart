import 'dart:math';

/// Picks the photos for one day from everything eligible.
///
/// Within a day the same selection is kept, so the slideshow does not
/// reshuffle on every start or refresh. On a new day a fresh random sample of
/// [count] photos is drawn. Photos that vanished from their source since the
/// selection was saved are dropped; if none of the saved photos is left, a new
/// sample is drawn.
class DailySelection {
  const DailySelection._();

  static List<T> pick<T>({
    required List<T> eligible,
    required String Function(T item) keyOf,
    required int count,
    required String today,
    String? savedDay,
    List<String> savedKeys = const [],
    Random? random,
  }) {
    if (eligible.length <= count) return List<T>.of(eligible);

    if (savedDay == today && savedKeys.isNotEmpty) {
      final byKey = {for (final item in eligible) keyOf(item): item};
      final kept = [
        for (final key in savedKeys)
          if (byKey.containsKey(key)) byKey[key] as T,
      ];
      if (kept.isNotEmpty) return kept.take(count).toList(growable: false);
    }

    final shuffled = List<T>.of(eligible)..shuffle(random ?? Random());
    return shuffled.take(count).toList(growable: false);
  }

  static String dayKey(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
