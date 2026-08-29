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

/// Drives the slideshow: decides which item is currently shown, advances on
/// a timer, and pulls the next candidates from a [WorkingSetPool] via a
/// [ShuffleBag] so items rotate fairly without immediate repeats.
///
/// Prefetching concept (not implemented here, intentionally): a real
/// implementation should, on every advance, kick off
/// `source.fetchToCache(nextItem)` for the *upcoming* one or two items
/// (not just the current one) so the image is already decoded/cached by
/// the time it needs to be displayed, and should hold a `CacheLease` on it
/// for the duration it is likely to be shown so the (future)
/// `ImageCacheManager`'s LRU eviction can't remove it mid-display. That
/// wiring belongs in the UI/controller layer once `ImageCacheManager`
/// exists; this engine only exposes [currentItem] and timing, and leaves a
/// clear seam (see [onAdvance]) for a caller to trigger prefetch of
/// upcoming items.
class SlideshowEngine {
  SlideshowEngine({
    required WorkingSetPool pool,
    required Map<String, PhotoSource> sources,
    required ItemResolver resolveItem,
    SlideshowConfig config = const SlideshowConfig(),
  })  : _pool = pool,
        _sources = sources,
        _resolveItem = resolveItem,
        _config = config {
    if (pool.entries.isEmpty) {
      throw ArgumentError.value(pool, 'pool', 'must not be empty to start a slideshow');
    }
    _shuffleBag = ShuffleBag<PoolEntry>(
      pool.entries,
      noRepeatWindow: _config.noRepeatWindow,
      keyOf: (entry) => entry.key,
    );
  }

  WorkingSetPool _pool;
  final Map<String, PhotoSource> _sources;
  final ItemResolver _resolveItem;
  SlideshowConfig _config;

  late ShuffleBag<PoolEntry> _shuffleBag;

  Timer? _timer;
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

  Future<void> _advance() async {
    final entry = _shuffleBag.next();
    final item = await _resolveItem(entry);
    if (item == null) {
      // Resolution failed (e.g. item vanished from its source); try the
      // next candidate rather than getting stuck on a dead entry.
      _pool.remove(entry.sourceId, entry.itemId);
      _shuffleBag.updateItems(_pool.entries);
      if (_pool.entries.isEmpty) {
        _currentEntry = null;
        _currentItem = null;
        _currentItemController.add(null);
        return;
      }
      return _advance();
    }

    _pool.registerShown(entry.sourceId, entry.itemId);
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
