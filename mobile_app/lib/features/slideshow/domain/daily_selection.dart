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
    String Function(T item)? folderOf,
    int perFolder = 2,
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

    if (folderOf != null) {
      return balancedSample(
        eligible: eligible,
        folderOf: folderOf,
        count: count,
        perFolder: perFolder,
        random: random,
      );
    }
    final shuffled = List<T>.of(eligible)..shuffle(random ?? Random());
    return shuffled.take(count).toList(growable: false);
  }

  /// Round-robin over folders: take up to [perFolder] photos from each folder,
  /// then again from each folder, until [count] is reached. Each folder is
  /// shuffled first, so the picks inside a folder are random too.
  static List<T> balancedSample<T>({
    required List<T> eligible,
    required String Function(T item) folderOf,
    required int count,
    int perFolder = 2,
    Random? random,
  }) {
    final rnd = random ?? Random();
    final byFolder = <String, List<T>>{};
    for (final item in eligible) {
      byFolder.putIfAbsent(folderOf(item), () => []).add(item);
    }
    final folders = byFolder.values.toList()..shuffle(rnd);
    for (final list in folders) {
      list.shuffle(rnd);
    }
    final picked = <T>[];
    var offset = 0;
    while (picked.length < count && folders.any((f) => offset < f.length)) {
      for (final folder in folders) {
        for (var k = 0; k < perFolder; k++) {
          final index = offset + k;
          if (index < folder.length && picked.length < count) {
            picked.add(folder[index]);
          }
        }
      }
      offset += perFolder;
    }
    return picked;
  }

  static String dayKey(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
