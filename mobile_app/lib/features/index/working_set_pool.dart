import 'media_index_entry.dart';

/// Bookkeeping record for one item that has been admitted into the
/// slideshow's "working set" - the bounded pool of items actually eligible
/// to be shown, as opposed to the full (potentially huge) index of
/// everything discovered across all sources.
///
/// Mirrors the future `pool_entries` persistence table (drift); this class
/// is the plain in-memory stand-in used until that table exists.
class PoolEntry {
  PoolEntry({
    required this.sourceId,
    required this.itemId,
    required this.addedToPoolAt,
    this.shownCount = 0,
    this.lastShownAt,
  });

  /// Id of the [PhotoSource] the underlying item belongs to.
  final String sourceId;

  /// Source-relative id of the underlying `PhotoItem`/`MediaIndexEntry`.
  final String itemId;

  /// When this entry was added to the working set.
  final DateTime addedToPoolAt;

  /// How many times this entry has been shown by the slideshow since being
  /// added to the pool.
  int shownCount;

  /// When this entry was last shown, or `null` if never shown.
  DateTime? lastShownAt;

  /// Composite key uniquely identifying this entry within a pool.
  String get key => '$sourceId::$itemId';

  @override
  String toString() =>
      'PoolEntry(key: $key, shownCount: $shownCount, lastShownAt: $lastShownAt)';
}

/// Interface for a bounded, curated pool of items eligible for display in
/// the slideshow, drawn from the (much larger) full media index.
///
/// The working set exists so that:
///  - the slideshow doesn't need to hold/consider the entire index at once,
///  - recently-discovered items get a fair, boosted chance of being shown
///    ("new image quota") instead of being drowned out by a huge back
///    catalogue,
///  - per-item show counts can be tracked to drive fair rotation (see
///    `ShuffleBag`, which operates on top of a pool's current entries).
///
/// This is a pure interface/in-memory reference implementation: no
/// persistence is wired up yet (a later milestone backs it with drift).
abstract class WorkingSetPool {
  /// Target number of entries the pool tries to maintain. Default per the
  /// product plan is 1000; a concrete implementation may refill/evict
  /// entries to stay near this size.
  static const int defaultTargetSize = 1000;

  /// Fraction of the pool that should be reserved for "new" entries, where
  /// new means either never shown (`shownCount == 0`) or discovered within
  /// the last 30 days. Default per the product plan is 0.2 (20%).
  static const double defaultNewImageQuota = 0.2;

  /// Age threshold, in days, under which an entry counts as "new" for the
  /// purposes of [defaultNewImageQuota], independent of [PoolEntry.shownCount].
  static const int newItemMaxAgeDays = 30;

  /// Current target size for this pool instance.
  int get targetSize;

  /// Current new-image quota for this pool instance, in the range `[0, 1]`.
  double get newImageQuota;

  /// All entries currently in the pool.
  List<PoolEntry> get entries;

  /// Entries considered "new" under the rule documented on
  /// [defaultNewImageQuota]: `shownCount == 0` OR added to the pool less
  /// than [newItemMaxAgeDays] days ago.
  List<PoolEntry> get newEntries;

  /// Adds an entry to the pool if not already present. Returns `true` if it
  /// was newly added, `false` if it already existed.
  bool add(PoolEntry entry);

  /// Removes the entry identified by [sourceId]/[itemId], if present.
  void remove(String sourceId, String itemId);

  /// Records that the entry identified by [sourceId]/[itemId] was shown:
  /// increments its `shownCount` and updates `lastShownAt` to [shownAt]
  /// (defaults to now).
  void registerShown(String sourceId, String itemId, {DateTime? shownAt});

  /// Whether the pool currently needs refilling (i.e. below [targetSize]).
  bool get needsRefill;

  /// Fills the pool up towards [targetSize] from [candidates] (typically the
  /// output of a media-index crawl), returning the number of entries
  /// actually added.
  ///
  /// Admission policy (see docs/PLAN.md "Arbeitsmenge (Working-Set-Pool) &
  /// Auffüll-Job"): at least [newImageQuota] of the *newly filled slots*
  /// (not of the whole pool) are reserved for "new" candidates where
  /// possible. A [MediaIndexEntry] doesn't carry its own
  /// "discovered/added-to-index-at" timestamp (only [MediaIndexEntry.mtime]
  /// and [MediaIndexEntry.lastSeenAt], the latter updated on every crawl) -
  /// as a documented design decision, this implementation treats a
  /// candidate as "new" for quota purposes when its [MediaIndexEntry.mtime]
  /// is within [WorkingSetPool.newItemMaxAgeDays] days of now, i.e. a
  /// recently taken/modified photo. This is a reasonable proxy for "recently
  /// added to the source" without requiring a schema change to
  /// [MediaIndexEntry].
  ///
  /// Candidates already present in the pool are skipped. If there aren't
  /// enough candidates (of either kind) to reach [targetSize], the pool
  /// simply ends up smaller than [targetSize] - per the plan, this is
  /// **not** an error state.
  int refill(List<MediaIndexEntry> candidates);

  /// Removes every entry that has been shown at least once since it was
  /// added (`shownCount >= 1`) and immediately attempts to backfill the
  /// freed slots from [candidates], using the same admission policy as
  /// [refill]. Returns the number of entries added back.
  ///
  /// Callers should pass candidates that exclude items they know were just
  /// evicted here if they want genuinely fresh replacements rather than an
  /// item cycling straight back in - this method itself doesn't try to
  /// exclude "candidates that happen to match what was just removed", since
  /// it has no opinion on where the candidate list came from.
  ///
  /// Per docs/PLAN.md this is not an error state when there aren't enough
  /// fresh candidates: the pool is simply left smaller.
  int replaceExhausted(List<MediaIndexEntry> candidates);

  /// Signals that an immediate, out-of-schedule refill is warranted instead
  /// of waiting for the next scheduled `pool_maintenance_job` run - the
  /// explicit architecture-review finding captured in docs/PLAN.md: with a
  /// short slideshow [currentInterval] and a pool that's almost entirely
  /// been shown already (`shownCount >= 1` for at least [exhaustionThreshold]
  /// of entries), waiting for an hourly/daily scheduled refill would mean
  /// visibly-too-early repeats.
  bool needsUrgentRefill({
    required Duration currentInterval,
    Duration shortIntervalThreshold = const Duration(seconds: 30),
    double exhaustionThreshold = 0.9,
  });
}

/// Simple in-memory [WorkingSetPool] implementation. Not persisted; a
/// process restart loses all pool state. Good enough for driving the
/// slideshow engine in this scaffolding step and for unit tests.
class InMemoryWorkingSetPool implements WorkingSetPool {
  InMemoryWorkingSetPool({
    int targetSize = WorkingSetPool.defaultTargetSize,
    double newImageQuota = WorkingSetPool.defaultNewImageQuota,
  })  : _targetSize = targetSize,
        _newImageQuota = newImageQuota;

  final int _targetSize;
  final double _newImageQuota;

  final Map<String, PoolEntry> _entriesByKey = {};

  @override
  int get targetSize => _targetSize;

  @override
  double get newImageQuota => _newImageQuota;

  @override
  List<PoolEntry> get entries => List.unmodifiable(_entriesByKey.values);

  @override
  List<PoolEntry> get newEntries {
    final cutoff = DateTime.now().subtract(
      const Duration(days: WorkingSetPool.newItemMaxAgeDays),
    );
    return _entriesByKey.values
        .where((e) => e.shownCount == 0 || e.addedToPoolAt.isAfter(cutoff))
        .toList(growable: false);
  }

  @override
  bool add(PoolEntry entry) {
    if (_entriesByKey.containsKey(entry.key)) return false;
    _entriesByKey[entry.key] = entry;
    return true;
  }

  @override
  void remove(String sourceId, String itemId) {
    _entriesByKey.remove('$sourceId::$itemId');
  }

  @override
  void registerShown(String sourceId, String itemId, {DateTime? shownAt}) {
    final entry = _entriesByKey['$sourceId::$itemId'];
    if (entry == null) return;
    entry.shownCount += 1;
    entry.lastShownAt = shownAt ?? DateTime.now();
  }

  @override
  bool get needsRefill => _entriesByKey.length < _targetSize;

  bool _isNewCandidate(MediaIndexEntry candidate, DateTime now) {
    return now.difference(candidate.mtime).inDays <= WorkingSetPool.newItemMaxAgeDays;
  }

  String _candidateKey(MediaIndexEntry candidate) => '${candidate.sourceId}::${candidate.path}';

  void _admit(MediaIndexEntry candidate, DateTime now) {
    add(
      PoolEntry(
        sourceId: candidate.sourceId,
        itemId: candidate.path,
        addedToPoolAt: now,
      ),
    );
  }

  @override
  int refill(List<MediaIndexEntry> candidates) {
    final slotsToFill = _targetSize - _entriesByKey.length;
    if (slotsToFill <= 0) return 0;

    final now = DateTime.now();
    final newCandidates = <MediaIndexEntry>[];
    final oldCandidates = <MediaIndexEntry>[];
    for (final candidate in candidates) {
      if (_entriesByKey.containsKey(_candidateKey(candidate))) continue;
      if (_isNewCandidate(candidate, now)) {
        newCandidates.add(candidate);
      } else {
        oldCandidates.add(candidate);
      }
    }

    // At least `newImageQuota` of the newly-filled slots are reserved for
    // "new" candidates where available (ceil so a small non-zero quota on a
    // small refill still reserves at least one slot rather than rounding
    // down to zero).
    final reservedNewSlots = (slotsToFill * _newImageQuota).ceil().clamp(0, slotsToFill);

    var added = 0;
    var newIndex = 0;
    var oldIndex = 0;

    while (added < reservedNewSlots && newIndex < newCandidates.length) {
      _admit(newCandidates[newIndex], now);
      newIndex++;
      added++;
    }

    // Fill the rest of the available slots from whatever candidates remain,
    // preferring "old" ones first so any leftover "new" candidates stay
    // available for a future refill's quota rather than being consumed here
    // as generic filler.
    while (added < slotsToFill && oldIndex < oldCandidates.length) {
      _admit(oldCandidates[oldIndex], now);
      oldIndex++;
      added++;
    }
    while (added < slotsToFill && newIndex < newCandidates.length) {
      _admit(newCandidates[newIndex], now);
      newIndex++;
      added++;
    }

    return added;
  }

  @override
  int replaceExhausted(List<MediaIndexEntry> candidates) {
    final exhausted = _entriesByKey.values.where((e) => e.shownCount >= 1).toList(growable: false);
    for (final entry in exhausted) {
      remove(entry.sourceId, entry.itemId);
    }
    if (exhausted.isEmpty) return 0;
    return refill(candidates);
  }

  @override
  bool needsUrgentRefill({
    required Duration currentInterval,
    Duration shortIntervalThreshold = const Duration(seconds: 30),
    double exhaustionThreshold = 0.9,
  }) {
    if (_entriesByKey.isEmpty) return false;
    if (currentInterval > shortIntervalThreshold) return false;
    final shownCount = _entriesByKey.values.where((e) => e.shownCount >= 1).length;
    final shownFraction = shownCount / _entriesByKey.length;
    return shownFraction >= exhaustionThreshold;
  }
}
