import 'media_stable_id.dart';

/// Cache state of a [MediaIndexEntry]'s underlying file.
enum CacheState {
  /// Not fetched yet - only metadata is known.
  notCached,

  /// A fetch is currently in progress.
  fetching,

  /// The file is present in the local cache and ready to display.
  cached,

  /// The last fetch attempt failed.
  failed,
}

/// Plain, in-memory representation of one entry in the local media index.
///
/// This is a **placeholder domain model**: in a later milestone this will
/// be replaced by a generated `drift` table (see the `drift` dependency in
/// `pubspec.yaml`) backed by SQLite, with this class's fields becoming
/// columns. Keeping it as a plain Dart class for now lets the slideshow
/// engine, working-set pool, and tests be written against a stable shape
/// without depending on generated code.
///
/// Important lifecycle note on [contentHash]: it is intentionally
/// **nullable and lazily populated**. Computing a content hash requires
/// reading the full file, which is far too expensive to do for every entry
/// discovered while crawling a source (potentially thousands of files). It
/// is therefore left `null` until the first successful [fetchToCache] for
/// this entry, at which point the hash is computed from the downloaded
/// bytes and stored back onto the entry. Do not assume it is populated for
/// entries that have only been listed, never fetched.
class MediaIndexEntry {
  MediaIndexEntry({
    required this.sourceId,
    required this.path,
    required this.name,
    required this.size,
    required this.mtime,
    required this.lastSeenAt,
    this.contentHash,
    this.width,
    this.height,
    this.takenAt,
    this.orientation = 0,
    this.cacheState = CacheState.notCached,
  });

  /// Id of the [PhotoSource] this entry was discovered on.
  final String sourceId;

  /// Source-relative path of the underlying file.
  final String path;

  /// File name.
  final String name;

  /// File size in bytes, as reported by the source at discovery time.
  final int size;

  /// Last-modified time as reported by the source at discovery time.
  final DateTime mtime;

  /// Content hash (e.g. SHA-256) of the file's bytes. `null` until the file
  /// has actually been downloaded at least once - see class doc comment.
  String? contentHash;

  final int? width;
  final int? height;
  final DateTime? takenAt;
  final int orientation;

  /// Last time this entry was observed during a crawl/listing pass. Used to
  /// detect entries that have disappeared from the source (stale entries
  /// whose [lastSeenAt] falls far enough behind "now").
  DateTime lastSeenAt;

  CacheState cacheState;

  /// Stable identifier (`sourceId:pathHash`) - see [MediaStableId]. Used to
  /// key favorites, "on this day" bookkeeping, and playlist `excludeIds`.
  String get stableId => MediaStableId.compute(sourceId: sourceId, path: path);

  @override
  String toString() =>
      'MediaIndexEntry(sourceId: $sourceId, path: $path, cacheState: $cacheState)';
}
