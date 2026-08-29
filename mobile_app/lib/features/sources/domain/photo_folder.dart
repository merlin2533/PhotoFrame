/// A folder/album exposed by a [PhotoSource].
///
/// [id] is source-relative and only unique within that source; call sites
/// that need a globally unique key should combine it with the owning
/// source's id (see `MediaIndexEntry.sourceId`).
class PhotoFolder {
  const PhotoFolder({
    required this.id,
    required this.name,
    required this.path,
    this.parentId,
  });

  /// Source-relative identifier (e.g. a SMB path hash, a Nextcloud file id).
  final String id;

  /// Display name, e.g. the last path segment.
  final String name;

  /// Full source-relative path, e.g. `/Photos/2024/Summer`.
  final String path;

  /// Id of the parent folder, or `null` for a root folder.
  final String? parentId;

  @override
  bool operator ==(Object other) =>
      other is PhotoFolder &&
      other.id == id &&
      other.name == name &&
      other.path == path &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(id, name, path, parentId);

  @override
  String toString() => 'PhotoFolder(id: $id, path: $path)';
}
