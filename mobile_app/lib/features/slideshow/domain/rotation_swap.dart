import '../../index/working_set_pool.dart';
import 'daily_selection.dart';

/// Default share of the rotation pool that is swapped out each day, in percent.
/// The live value is `AppSettings.rotationSwapPercent`; this is the default.
const int defaultRotationSwapPercent = 5;

/// App preferences key holding the day (`yyyy-MM-dd`) of the last daily swap.
const String rotationSwapDayPrefsKey = 'rotation_swap_day_v1';

/// Number of photos the daily swap replaces for a pool of [poolLength] photos:
/// [percent] of the pool, rounded down. At least 1 once the pool has more than
/// one photo, and never the whole pool, so the rotation keeps going. A
/// [percent] of 0 means no daily swap at all, so the result is 0.
int rotationSwapSize(int poolLength,
    {int percent = defaultRotationSwapPercent}) {
  if (poolLength <= 1 || percent <= 0) return 0;
  final size = poolLength * percent ~/ 100;
  if (size < 1) return 1;
  return size >= poolLength ? poolLength - 1 : size;
}

/// The [count] entries that entered the pool first, by the calendar day of
/// [PoolEntry.addedToPoolAt]. Entries of the same day keep their pool order.
List<PoolEntry> oldestEntries(List<PoolEntry> entries, int count) {
  final indexed = [
    for (var i = 0; i < entries.length; i++)
      (i, DailySelection.dayKey(entries[i].addedToPoolAt)),
  ]..sort((a, b) {
      final byDay = a.$2.compareTo(b.$2);
      return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
    });
  return [for (final (i, _) in indexed.take(count)) entries[i]];
}

/// Whether the daily swap has not run yet on [today] (a `yyyy-MM-dd` day key).
/// [lastSwapDay] is the day of the last swap, or `null` when none ran.
bool swapDue({required String? lastSwapDay, required String today}) =>
    lastSwapDay != today;

/// Removes the [count] oldest entries from [pool] and returns them. The pool
/// always keeps at least one entry.
List<PoolEntry> swapOutOldest(WorkingSetPool pool, int count) {
  final keep = pool.entries.length - 1;
  final victims = oldestEntries(pool.entries, count);
  final removed = victims.length > keep ? victims.take(keep).toList() : victims;
  for (final entry in removed) {
    pool.remove(entry.sourceId, entry.itemId);
  }
  return removed;
}

/// The first [count] of [candidates] that [skip] does not reject, in order.
List<T> nextReplacements<T>({
  required Iterable<T> candidates,
  required bool Function(T candidate) skip,
  required int count,
}) {
  final picked = <T>[];
  for (final candidate in candidates) {
    if (picked.length >= count) break;
    if (!skip(candidate)) picked.add(candidate);
  }
  return picked;
}

/// Whether more photos may be downloaded: the cache holds [cachedBytes], below
/// [limitBytes] (`AppSettings.cacheLimitBytes`). The cache limit is the only
/// thing that stops the growth of the rotation pool.
bool downloadsAllowed({required int cachedBytes, required int limitBytes}) =>
    cachedBytes < limitBytes;
