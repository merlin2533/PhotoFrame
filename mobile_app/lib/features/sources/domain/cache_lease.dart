/// A pin on a cached file that prevents the (future) `ImageCacheManager`
/// from evicting it via LRU while it is actively being shown.
///
/// Concept: `ImageCacheManager` keeps a pin counter per cached file. When
/// the slideshow (or any other consumer) is about to display an image, it
/// calls something like `cacheManager.acquireLease(item)` which increments
/// the counter and returns a [CacheLease]. When the image is no longer
/// displayed, the consumer calls [release] which decrements the counter.
/// LRU eviction only ever considers entries whose pin counter is zero, so a
/// picture currently on screen (or pre-fetched and about to be shown) is
/// never deleted out from under the UI.
///
/// `ImageCacheManager` (see `lib/services/cache/image_cache_manager.dart`)
/// now implements this concept for real: `acquire(key)` increments a pin
/// counter and hands back a [CacheLease] wired via [onRelease] to decrement
/// it again. The optional-callback shape keeps this class free of any
/// import/dependency on the cache manager itself (which lives in
/// `services/`, a layer above `features/sources/domain/`), and keeps it
/// usable standalone (e.g. in tests) with [onRelease] simply omitted.
class CacheLease {
  CacheLease(this.itemId, {void Function()? onRelease})
      : _onRelease = onRelease,
        _released = false;

  /// Id of the [PhotoItem] (or its cache key) this lease pins.
  final String itemId;

  final void Function()? _onRelease;

  bool _released;

  /// Whether [release] has already been called.
  bool get isReleased => _released;

  /// Releases the lease, allowing the cache manager to evict the underlying
  /// file again once no other lease references it. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    _onRelease?.call();
  }
}
