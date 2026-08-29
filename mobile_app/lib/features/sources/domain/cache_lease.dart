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
/// This class is a placeholder: it has no wiring to a real cache manager
/// yet (that lives in a later milestone). It exists now so [PhotoSource]
/// consumers and the slideshow engine can already be written against the
/// concept and the shape of the API doesn't need to change later.
class CacheLease {
  CacheLease(this.itemId) : _released = false;

  /// Id of the [PhotoItem] (or its cache key) this lease pins.
  final String itemId;

  bool _released;

  /// Whether [release] has already been called.
  bool get isReleased => _released;

  /// Releases the lease, allowing the cache manager to evict the underlying
  /// file again once no other lease references it. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    // TODO(cache): forward to ImageCacheManager.decrementPin(itemId) once
    // that component exists.
  }
}
