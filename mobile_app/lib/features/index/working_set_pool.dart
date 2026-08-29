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
}
