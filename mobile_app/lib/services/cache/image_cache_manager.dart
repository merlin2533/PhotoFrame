import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../features/sources/domain/cache_lease.dart';

/// Which cache tier an entry belongs to - see docs/PLAN.md "ImageCacheManager
/// (zweistufig)": a small thumbnail cache for fast previews/overlays, and a
/// separate full-image cache for what's actually being displayed full-screen.
enum CacheTier { thumbnail, full }

class _CacheEntry {
  _CacheEntry({
    required this.key,
    required this.file,
    required this.sizeBytes,
  });

  final String key;
  File file;
  int sizeBytes;

  /// Pin counter - see [CacheLease]. While `> 0`, LRU eviction must never
  /// remove this entry (this was the exact bug flagged in architecture
  /// review: a currently-displayed image being evicted mid-display).
  int pinCount = 0;

  /// Whether this entry is one of the "last N successfully displayed"
  /// images kept as an offline reserve (see
  /// [ImageCacheManager.recordSuccessfullyDisplayed]). Independent of
  /// [pinCount]: an entry can be an offline reserve without currently being
  /// pinned, and vice versa.
  bool isOfflineReserve = false;

  bool get isEvictable => pinCount <= 0 && !isOfflineReserve;
}

/// One tier's bookkeeping: an LRU-ordered map (insertion/access order via
/// [LinkedHashMap], re-keyed on every access to move an entry to the
/// "most recently used" end) plus a running byte total.
class _TierStore {
  _TierStore(this.limitBytes);

  int limitBytes;

  /// Ordered least-recently-used (front) to most-recently-used (back).
  final LinkedHashMap<String, _CacheEntry> _entries = LinkedHashMap();

  int _totalBytes = 0;
  int get totalBytes => _totalBytes;

  _CacheEntry? get(String key) => _entries[key];

  void touch(String key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry; // re-insert at the MRU end
    }
  }

  void put(_CacheEntry entry) {
    final existing = _entries.remove(entry.key);
    if (existing != null) {
      _totalBytes -= existing.sizeBytes;
    }
    _entries[entry.key] = entry;
    _totalBytes += entry.sizeBytes;
  }

  _CacheEntry? removeKey(String key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _totalBytes -= entry.sizeBytes;
    }
    return entry;
  }

  Iterable<_CacheEntry> get entriesLruFirst => _entries.values;
}

/// Two-tier (thumbnail + full-image) on-disk image cache with LRU eviction,
/// a pin-counter ("lease") mechanism that protects currently-displayed/
/// prefetched images from eviction, and a small "offline reserve" of the
/// last N successfully displayed images that survive eviction even when not
/// pinned (see docs/PLAN.md "ImageCacheManager").
///
/// Disk-space awareness: rather than depending on `path_provider`/a real
/// platform API for free disk space (which can't be exercised in a plain
/// `flutter test` unit test), the actual free-space check is injected via
/// [getFreeDiskSpaceBytes]. Real platform wiring (statvfs on
/// Android/iOS via `path_provider` + a platform channel, or a plugin) is a
/// TODO for whoever wires this into the UI/settings layer - this class only
/// needs *a* number to cap against, not to know how it was obtained.
class ImageCacheManager {
  ImageCacheManager({
    required int thumbnailLimitBytes,
    required int fullLimitBytes,
    this.offlineReserveCount = 5,
    Future<int> Function()? getFreeDiskSpaceBytes,
    this.minFreeSpaceReserveBytes = 1024 * 1024 * 1024, // 1 GB, per plan
  })  : _configuredLimits = {
          CacheTier.thumbnail: thumbnailLimitBytes,
          CacheTier.full: fullLimitBytes,
        },
        _getFreeDiskSpaceBytes = getFreeDiskSpaceBytes,
        _tiers = {
          CacheTier.thumbnail: _TierStore(thumbnailLimitBytes),
          CacheTier.full: _TierStore(fullLimitBytes),
        };

  /// How many of the most recently *successfully displayed* images (across
  /// both tiers, tracked per-key) are protected from eviction as an offline
  /// reserve, independent of pinning. Per docs/PLAN.md: "die zuletzt
  /// erfolgreich angezeigten N Bilder werden nie evicted".
  final int offlineReserveCount;

  /// Minimum free disk space to always leave untouched, on top of whatever
  /// the configured limit is - mirrors docs/PLAN.md's "Reserve von
  /// mindestens 1 GB bzw. 10% freiem Speicher" (the 10%-of-free-space side
  /// of that rule is left to the caller/UI, which knows total disk size;
  /// this class only enforces the fixed floor since that's all it can do
  /// with just a free-bytes number).
  final int minFreeSpaceReserveBytes;

  final Map<CacheTier, int> _configuredLimits;
  final Future<int> Function()? _getFreeDiskSpaceBytes;
  final Map<CacheTier, _TierStore> _tiers;

  final Queue<_ReserveSlot> _offlineReserveQueue = Queue<_ReserveSlot>();

  int configuredLimitBytes(CacheTier tier) => _configuredLimits[tier]!;

  /// Updates the configured limit for [tier] (e.g. the user moved the
  /// cache-size slider in settings) and immediately enforces it.
  Future<void> setLimitBytes(CacheTier tier, int limitBytes) async {
    _configuredLimits[tier] = limitBytes;
    _tiers[tier]!.limitBytes = limitBytes;
    await _enforceLimit(tier);
  }

  /// The limit actually enforced right now for [tier]: the smaller of the
  /// configured limit and (free disk space - [minFreeSpaceReserveBytes]),
  /// when [getFreeDiskSpaceBytes] was supplied. Never negative.
  Future<int> effectiveLimitBytes(CacheTier tier) async {
    final configured = _configuredLimits[tier]!;
    final getFree = _getFreeDiskSpaceBytes;
    if (getFree == null) return configured;
    final free = await getFree();
    final diskCapped = free - minFreeSpaceReserveBytes;
    if (diskCapped < 0) return 0;
    return configured < diskCapped ? configured : diskCapped;
  }

  int currentSizeBytes(CacheTier tier) => _tiers[tier]!.totalBytes;

  /// Registers [file] (already fetched to local storage, e.g. via
  /// `PhotoSource.fetchToCache`) under [key] in [tier], then enforces the
  /// tier's size limit (evicting other, unprotected entries as needed).
  Future<void> put(String key, File file, {required CacheTier tier}) async {
    final store = _tiers[tier]!;
    int size;
    try {
      size = await file.length();
    } on FileSystemException {
      size = 0;
    }
    final existing = store.get(key);
    final pendingKey = _pendingKey(tier, key);
    final pendingPinCount = _pendingPins.remove(pendingKey) ?? 0;
    final entry = _CacheEntry(key: key, file: file, sizeBytes: size)
      ..pinCount = (existing?.pinCount ?? 0) + pendingPinCount
      ..isOfflineReserve = existing?.isOfflineReserve ?? false;
    store.put(entry);
    await _enforceLimit(tier);
  }

  /// Acquires a pin on [key] in [tier], returning a [CacheLease]. While at
  /// least one lease on a key is outstanding, LRU eviction will never
  /// remove it. Safe to call even if [key] isn't cached (yet) - the pin is
  /// still tracked so a `put` that races with an in-flight fetch doesn't
  /// get evicted before the caller manages to use it; calling on an unknown
  /// key otherwise has no effect on cache contents.
  CacheLease acquire(String key, {CacheTier tier = CacheTier.full}) {
    final store = _tiers[tier]!;
    final entry = store.get(key);
    if (entry != null) {
      entry.pinCount++;
      store.touch(key);
    } else {
      _pendingPins.update(
        _pendingKey(tier, key),
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    return CacheLease(key, onRelease: () => _release(tier, key));
  }

  final Map<String, int> _pendingPins = {};

  String _pendingKey(CacheTier tier, String key) => '${tier.name}::$key';

  void _release(CacheTier tier, String key) {
    final store = _tiers[tier]!;
    final entry = store.get(key);
    if (entry != null) {
      if (entry.pinCount > 0) entry.pinCount--;
      return;
    }
    final pendingKey = _pendingKey(tier, key);
    final pending = _pendingPins[pendingKey];
    if (pending != null) {
      if (pending <= 1) {
        _pendingPins.remove(pendingKey);
      } else {
        _pendingPins[pendingKey] = pending - 1;
      }
    }
  }

  /// Current pin count for [key] in [tier] - exposed mainly for tests.
  int pinCountOf(String key, {CacheTier tier = CacheTier.full}) {
    return _tiers[tier]!.get(key)?.pinCount ?? _pendingPins[_pendingKey(tier, key)] ?? 0;
  }

  /// Marks [key] as having just been successfully displayed, adding it to
  /// the fixed-size offline-reserve queue (per tier) so it survives
  /// eviction even without an active [CacheLease] - protection against "all
  /// sources unreachable" scenarios per docs/PLAN.md. When the queue for
  /// [tier] exceeds [offlineReserveCount], the oldest reserved entry loses
  /// its reserve flag (it remains evictable going forward, unless pinned).
  void recordSuccessfullyDisplayed(String key, {CacheTier tier = CacheTier.full}) {
    final store = _tiers[tier]!;
    final entry = store.get(key);
    if (entry == null) return;

    entry.isOfflineReserve = true;
    _offlineReserveQueue.addLast(_ReserveSlot(tier, key));

    while (_offlineReserveQueue.length > offlineReserveCount) {
      final oldest = _offlineReserveQueue.removeFirst();
      final oldestEntry = _tiers[oldest.tier]!.get(oldest.key);
      // Only clear the flag if this dequeue wasn't superseded by a more
      // recent re-display of the same key still later in the queue.
      final stillReserved = _offlineReserveQueue.any(
        (slot) => slot.tier == oldest.tier && slot.key == oldest.key,
      );
      if (oldestEntry != null && !stillReserved) {
        oldestEntry.isOfflineReserve = false;
      }
    }
  }

  bool isOfflineReserve(String key, {CacheTier tier = CacheTier.full}) {
    return _tiers[tier]!.get(key)?.isOfflineReserve ?? false;
  }

  bool contains(String key, {CacheTier tier = CacheTier.full}) {
    return _tiers[tier]!.get(key) != null;
  }

  /// Evicts least-recently-used, unprotected (`pinCount == 0` and not an
  /// offline reserve) entries in [tier] until it fits within
  /// [effectiveLimitBytes]. If every remaining entry is protected, stops
  /// even if still over limit - a manager can't evict what it's forbidden
  /// to evict; that's a deliberate trade-off documented in the class doc
  /// comment, not a bug.
  Future<void> _enforceLimit(CacheTier tier) async {
    final store = _tiers[tier]!;
    final limit = await effectiveLimitBytes(tier);
    if (store.totalBytes <= limit) return;

    // Iterate LRU-first; evict eligible entries until under limit or nothing
    // left to evict.
    final candidates = store.entriesLruFirst.toList(growable: false);
    for (final entry in candidates) {
      if (store.totalBytes <= limit) break;
      if (!entry.isEvictable) continue;
      store.removeKey(entry.key);
      unawaited(_deleteFileQuietly(entry.file));
    }
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort: a failed delete shouldn't crash cache bookkeeping. The
      // entry is already removed from tracking either way.
    }
  }

  /// Clears everything in [tier] (or both tiers if `null`), regardless of
  /// pin/reserve status - used by the "clear cache" settings action, which
  /// is an explicit user request and should not be silently blocked by
  /// pins/reserves the user has no visibility into.
  Future<void> clear({CacheTier? tier}) async {
    final tiersToClear = tier == null ? _tiers.keys.toList() : [tier];
    for (final t in tiersToClear) {
      final store = _tiers[t]!;
      final entries = store.entriesLruFirst.toList(growable: false);
      for (final entry in entries) {
        store.removeKey(entry.key);
        unawaited(_deleteFileQuietly(entry.file));
      }
    }
    _offlineReserveQueue.removeWhere((slot) => tiersToClear.contains(slot.tier));
  }
}

class _ReserveSlot {
  const _ReserveSlot(this.tier, this.key);
  final CacheTier tier;
  final String key;
}
