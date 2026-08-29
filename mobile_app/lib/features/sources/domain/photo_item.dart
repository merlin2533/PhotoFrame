import 'media_type.dart';

/// A single photo (or, later, video) item as reported by a [PhotoSource].
///
/// This is the in-memory domain representation; `MediaIndexEntry` is the
/// (future) persisted counterpart used by the local index/cache.
class PhotoItem {
  const PhotoItem({
    required this.id,
    required this.sourceId,
    required this.folderId,
    required this.name,
    required this.mediaType,
    required this.size,
    required this.mtime,
    this.width,
    this.height,
    this.takenAt,
    this.orientation = 0,
  });

  /// Source-relative identifier, unique within [sourceId].
  final String id;

  /// Id of the [PhotoSource] this item was discovered on.
  final String sourceId;

  /// Id of the containing [PhotoFolder].
  final String folderId;

  /// File name, e.g. `IMG_0001.jpg`.
  final String name;

  final MediaType mediaType;

  /// Pixel width, when known (may require reading the file to determine).
  final int? width;

  /// Pixel height, when known.
  final int? height;

  /// Timestamp the photo was taken, from EXIF or similar metadata.
  final DateTime? takenAt;

  /// EXIF-style orientation flag (0 = unknown/normal, 1-8 per EXIF spec).
  final int orientation;

  /// File size in bytes, as reported by the source.
  final int size;

  /// Last-modified time as reported by the source.
  final DateTime mtime;

  @override
  bool operator ==(Object other) =>
      other is PhotoItem &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.folderId == folderId;

  @override
  int get hashCode => Object.hash(id, sourceId, folderId);

  @override
  String toString() => 'PhotoItem(id: $id, sourceId: $sourceId, name: $name)';
}
