import 'dart:async';

import '../../index/working_set_pool.dart';
import '../../sources/domain/photo_item.dart';
import '../../sources/domain/photo_source.dart';
import 'shuffle_bag.dart';
import 'slideshow_config.dart';

/// Signature used by [SlideshowEngine] to resolve a [PoolEntry] (which only
/// carries `sourceId`/`itemId`) to the full [PhotoItem] metadata needed to
/// render it. Kept as an injected function rather than a hard dependency on
/// a specific index/cache implementation, since that piece (the real media
/// index, likely backed by drift) doesn't exist yet in this scaffold.
typedef ItemResolver = Future<PhotoItem?> Function(PoolEntry entry);

/// How many upcoming photos the slideshow prepares ahead of time, so they are
/// already in the cache when they are shown.
const int upcomingPhotoCount = 3;

/// Drives the slideshow: decides which item is currently shown, advances on
/// a timer, and pulls the next candidates from a [WorkingSetPool] via a
/// [ShuffleBag] so items rotate fairly without immediate repeats.
///
/// Prefetching: the screen asks [upcomingEntries] for the next
/// [upcomingPhotoCount] entries and prepares them (see `_prefetchNext` in
/// `slideshow_screen.dart`). The engine itself does no I/O.
class SlideshowEngine {
  SlideshowEngine({
    required WorkingSetPool pool,
    required Map<String, PhotoSource> sources,
    required ItemResolver resolveItem,
    SlideshowConfig config = const SlideshowConfig(),
    this.isCached,
  })  : _pool = pool,
        _sources = sources,
        _resolveItem = resolveItem,
        _config = config {
    if (pool.entries.isEmpty) {
      throw ArgumentError.value(
          pool, 'pool', 'must not be empty to start a slideshow');
    }
    _shuffleBag = ShuffleBag<PoolEntry>(
      pool.entries,
      noRepeatWindow: _config.noRepeatWindow,
      keyOf: (entry) => entry.key,
    );
  }

  /// Synchronous check whether the photo of [entry] can be shown right away
  /// (it is already on disk). It must not do any I/O. When it is `null`, every
  /// entry counts as cached and the order is never changed.
  ///
  /// When the entry due next is not cached and at least one cached entry is in
  /// the pool, the next cached entry is shown instead. The skipped entry stays
  /// in the pool and is queued again, so it comes up later.
  final bool Function(PoolEntry entry)? isCached;

  WorkingSetPool _pool;
  final Map<String, PhotoSource> _sources;
  final ItemResolver _resolveItem;
  SlideshowConfig _config;

  late ShuffleBag<PoolEntry> _shuffleBag;

  /// Entries already drawn from [_shuffleBag] but not shown yet, in show order.
  /// Filled by [upcomingEntries] and consumed first by [_advance].
  final List<PoolEntry> _lookahead = [];

  Timer? _timer;
  final List<_Shown> _history = [];
  static const _maxHistory = 50;
  PhotoItem? _currentItem;
  PoolEntry? _currentEntry;

  final StreamController<PhotoItem?> _currentItemController =
      StreamController<PhotoItem?>.broadcast();

  /// Emits every time [currentItem] changes (including the initial item
  /// once [start] has resolved it).
  Stream<PhotoItem?> get currentItemChanges => _currentItemController.stream;

  /// The item currently meant to be displayed, or `null` before [start] has
  /// resolved the first item.
  PhotoItem? get currentItem => _currentItem;

  SlideshowConfig get config => _config;

  bool get isRunning => _timer != null;

  /// The next [count] entries the slideshow will show, in show order, without
  /// showing them. The engine draws them ahead into a buffer that [_advance]
  /// consumes first, so the order returned here is the order it will use.
  List<PoolEntry> upcomingEntries(int count) {
    while (_lookahead.length < count) {
      _lookahead.add(_shuffleBag.next());
    }
    return List.unmodifiable(_lookahead.take(count));
  }

  /// Looks up the [PhotoSource] backing the currently shown item, if any.
  PhotoSource? get currentSource =>
      _currentEntry == null ? null : _sources[_currentEntry!.sourceId];

  /// Applies a new configuration. If [config.interval] changed while
  /// running, the timer is restarted with the new interval; if
  /// [config.noRepeatWindow] changed, a fresh [ShuffleBag] is created
  /// (losing recent-history state, which is an acceptable trade-off for a
  /// user-initiated settings change).
  void updateConfig(SlideshowConfig config) {
    final noRepeatChanged = config.noRepeatWindow != _config.noRepeatWindow;
    final wasRunning = isRunning;
    _config = config;

    if (noRepeatChanged) {
      _shuffleBag = ShuffleBag<PoolEntry>(
        _pool.entries,
        noRepeatWindow: _config.noRepeatWindow,
        keyOf: (entry) => entry.key,
      );
      _lookahead.clear();
    }

    if (wasRunning) {
      stop();
      start();
    }
  }

  /// Call when the [WorkingSetPool]'s contents changed (refill/eviction) so
  /// the shuffle bag draws from the up-to-date working set.
  void refreshPool(WorkingSetPool pool) {
    _pool = pool;
    _shuffleBag.updateItems(pool.entries);
    final keys = pool.entries.map((entry) => entry.key).toSet();
    _lookahead.removeWhere((entry) => !keys.contains(entry.key));
  }

  /// Starts the slideshow: immediately resolves and shows the first item,
  /// then advances every [SlideshowConfig.interval].
  Future<void> start() async {
    if (isRunning) return;
    await _advance();
    _timer = Timer.periodic(_config.interval, (_) => _advance());
  }

  /// Stops automatic advancing. [currentItem] is left as-is so the UI can
  /// keep showing the last item (e.g. while paused).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Manually advances to the next item, resetting the automatic timer's
  /// countdown when running.
  Future<void> skipToNext() async {
    final wasRunning = isRunning;
    if (wasRunning) {
      _timer?.cancel();
      _timer = null;
    }
    await _advance();
    if (wasRunning) {
      _timer = Timer.periodic(_config.interval, (_) => _advance());
    }
  }

  /// Steps back to the photo shown before the current one. Does nothing at
  /// the start of the history.
  Future<void> showPrevious() async {
    if (_history.isEmpty) return;
    final wasRunning = isRunning;
    if (wasRunning) {
      _timer?.cancel();
      _timer = null;
    }
    final previous = _history.removeLast();
    _currentEntry = previous.entry;
    _currentItem = previous.item;
    _currentItemController.add(previous.item);
    if (wasRunning) {
      _timer = Timer.periodic(_config.interval, (_) => _advance());
    }
  }

  /// The next entry in show order, from the lookahead buffer or the bag.
  PoolEntry _takeInOrder() =>
      _lookahead.isNotEmpty ? _lookahead.removeAt(0) : _shuffleBag.next();

  /// Chooses the entry to show next. If the entry due next is not cached, the
  /// next cached entry is returned instead, and the skipped one is queued again
  /// at the end of the lookahead, so it stays in the pool for later. When
  /// nothing in the pool is cached, the entry due next is returned unchanged.
  ///
  /// Synchronous and in-memory only: the [isCached] check does no I/O.
  PoolEntry _takeNextEntry() {
    final first = _takeInOrder();
    final isCached = this.isCached;
    if (isCached == null || isCached(first)) return first;
    if (!_pool.entries.any(isCached)) return first;

    final cachedIndex = _lookahead.indexWhere(isCached);
    if (cachedIndex >= 0) {
      final cached = _lookahead.removeAt(cachedIndex);
      _lookahead.add(first);
      return cached;
    }
    // The cached entry is not buffered yet: draw from the bag. Entries drawn
    // on the way are buffered in order, so they are not lost. A full cycle
    // over the pool reaches every entry, so the loop bound is generous.
    final bagDraws = _pool.entries.length * 2;
    for (var i = 0; i < bagDraws; i++) {
      final candidate = _shuffleBag.next();
      if (isCached(candidate)) {
        _lookahead.add(first);
        return candidate;
      }
      if (candidate.key != first.key &&
          !_lookahead.any((other) => other.key == candidate.key)) {
        _lookahead.add(candidate);
      }
    }
    return first;
  }

  Future<void> _advance() async {
    final entry = _takeNextEntry();
    final item = await _resolveItem(entry);
    if (item == null) {
      // Resolution failed (e.g. item vanished from its source); try the
      // next candidate rather than getting stuck on a dead entry.
      _pool.remove(entry.sourceId, entry.itemId);
      _lookahead.removeWhere((other) => other.key == entry.key);
      // ShuffleBag rejects an empty list, so an emptied pool is handled first.
      if (_pool.entries.isEmpty) {
        _lookahead.clear();
        _currentEntry = null;
        _currentItem = null;
        _currentItemController.add(null);
        return;
      }
      _shuffleBag.updateItems(_pool.entries);
      return _advance();
    }

    _pool.registerShown(entry.sourceId, entry.itemId);
    final shownEntry = _currentEntry;
    final shownItem = _currentItem;
    if (shownEntry != null && shownItem != null) {
      _history.add(_Shown(shownEntry, shownItem));
      if (_history.length > _maxHistory) _history.removeAt(0);
    }
    _currentEntry = entry;
    _currentItem = item;
    _currentItemController.add(item);
  }

  /// Releases the timer and stream resources. The engine must not be used
  /// after calling this.
  Future<void> dispose() async {
    stop();
    await _currentItemController.close();
  }
}

class _Shown {
  const _Shown(this.entry, this.item);

  final PoolEntry entry;
  final PhotoItem item;
}
