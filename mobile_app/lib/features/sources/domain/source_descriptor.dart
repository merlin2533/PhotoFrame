import '../local/local_folder_source.dart';
import '../mock/mock_photo_source.dart';
import '../nextcloud/nextcloud_photo_source.dart';
import '../smb/smb_photo_source.dart';
import 'photo_source.dart';

/// Serializable, **non-secret** description of one configured [PhotoSource],
/// persisted as JSON in `shared_preferences` by `SourcesController` (mirrors
/// `AppSettings`'s single-JSON-blob pattern - see that class's doc comment).
///
/// [config] holds only fields safe to store in plain-text KV storage (host,
/// share name, domain, server URL, folder path, auth mode, ...). Passwords
/// and other secrets are NEVER put here - they live exclusively in
/// `SecureCredentialStore`, keyed by [id], and are loaded back separately
/// (see [fromDescriptor]).
class SourceDescriptor {
  const SourceDescriptor({
    required this.type,
    required this.id,
    required this.displayName,
    this.config = const {},
  });

  final SourceType type;
  final String id;
  final String displayName;
  final Map<String, dynamic> config;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'displayName': displayName,
        'config': config,
      };

  factory SourceDescriptor.fromJson(Map<String, dynamic> json) {
    return SourceDescriptor(
      type: SourceType.values.firstWhere(
        (t) => t.name == json['type'],
        // An unknown/future type (e.g. a descriptor written by a newer app
        // version) falls back to `mock` here; `fromDescriptor` maps that to
        // a harmless `MockPhotoSource` rather than crashing on load.
        orElse: () => SourceType.mock,
      ),
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      config: json['config'] is Map
          ? Map<String, dynamic>.from(json['config'] as Map)
          : const <String, dynamic>{},
    );
  }
}

/// Builds the concrete [PhotoSource] instance described by [descriptor],
/// re-attaching [password] (loaded separately from `SecureCredentialStore`
/// by the caller - see `SourcesController.build`) for the types that need
/// one.
///
/// Falls back to a fresh [MockPhotoSource] (same [id]/[displayName]) for
/// [SourceType.sharedAlbum] - not yet configurable via `add_source_screen`,
/// so no descriptor shape is defined for it yet - and for any type this
/// build doesn't recognize, rather than throwing during app startup over a
/// single bad/forward-incompatible descriptor.
PhotoSource fromDescriptor(SourceDescriptor descriptor, {required String? password}) {
  switch (descriptor.type) {
    case SourceType.smb:
      final config = SmbSourceConfig.fromJson(descriptor.config, password: password ?? '');
      return SmbPhotoSource(id: descriptor.id, config: config, displayName: descriptor.displayName);
    case SourceType.nextcloud:
      final config = NextcloudSourceConfig.fromJson(descriptor.config, password: password ?? '');
      return NextcloudPhotoSource(id: descriptor.id, config: config, displayName: descriptor.displayName);
    case SourceType.local:
      return LocalFolderSource(
        id: descriptor.id,
        displayName: descriptor.displayName,
        rootPath: descriptor.config['rootPath'] as String?,
      );
    case SourceType.mock:
    case SourceType.sharedAlbum:
      return MockPhotoSource(id: descriptor.id, displayName: descriptor.displayName);
  }
}

/// Turns a live [PhotoSource] back into its persistable [SourceDescriptor],
/// the inverse of [fromDescriptor]. Used by `SourcesController` right after
/// `add()`/on every mutation, so the descriptor list in `shared_preferences`
/// always matches the in-memory source list.
extension PhotoSourceDescriptorX on PhotoSource {
  SourceDescriptor toDescriptor() {
    final source = this;
    if (source is SmbPhotoSource) {
      return SourceDescriptor(
        type: SourceType.smb,
        id: source.id,
        displayName: source.displayName,
        config: source.config.toJson(),
      );
    }
    if (source is NextcloudPhotoSource) {
      return SourceDescriptor(
        type: SourceType.nextcloud,
        id: source.id,
        displayName: source.displayName,
        config: source.config.toJson(),
      );
    }
    if (source is LocalFolderSource) {
      return SourceDescriptor(
        type: SourceType.local,
        id: source.id,
        displayName: source.displayName,
        config: {'rootPath': source.rootPath ?? ''},
      );
    }
    // MockPhotoSource (and anything else not modeled above, e.g. a future
    // SharedAlbumPhotoSource) - persisted as a bare mock descriptor so it at
    // least survives a restart as *something* rather than silently vanishing;
    // see `fromDescriptor`'s doc comment for the corresponding fallback.
    return SourceDescriptor(type: SourceType.mock, id: source.id, displayName: source.displayName);
  }
}
