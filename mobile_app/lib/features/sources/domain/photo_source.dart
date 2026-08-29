import 'dart:io';

import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/result.dart';
import 'photo_folder.dart';
import 'photo_item.dart';

/// Kind of backing store a [PhotoSource] talks to.
enum SourceType {
  smb,
  nextcloud,
  local,
  sharedAlbum,
  mock,
}

/// Result of a [PhotoSource.testConnection] probe.
class ConnectionStatus {
  const ConnectionStatus({
    required this.reachable,
    this.latency,
    this.detail,
  });

  /// Whether the source responded successfully within the timeout.
  final bool reachable;

  /// Round-trip time of the probe, when measured.
  final Duration? latency;

  /// Optional human-readable detail (server version, share name, ...).
  final String? detail;

  @override
  String toString() =>
      'ConnectionStatus(reachable: $reachable, latency: $latency, detail: $detail)';
}

/// Abstraction over a place photos can be discovered and fetched from
/// (a local folder, an SMB share, a Nextcloud instance, a mock source for
/// tests/dev, ...).
///
/// Implementations are expected to be reasonably long-lived: create one per
/// configured source, call [dispose] when the source is removed/the app
/// shuts down.
abstract class PhotoSource {
  /// Stable identifier for this configured source instance (not the same as
  /// [SourceType] - there can be several sources of the same type).
  String get id;

  /// User-facing name shown in source pickers/settings.
  String get displayName;

  SourceType get type;

  /// Probes whether the source is currently reachable/usable, e.g. to
  /// validate credentials right after configuration or to surface a
  /// connectivity warning in settings.
  Future<Result<ConnectionStatus>> testConnection({
    Duration timeout = const Duration(seconds: 8),
  });

  /// Lists the immediate child folders of [parent] (or root folders when
  /// `null`), as a stream so large/slow sources can report results
  /// incrementally rather than blocking until everything is enumerated.
  ///
  /// Pass [token] to allow the caller to abort a long-running listing
  /// (e.g. the user navigated away).
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  });

  /// Lists the images contained in [folder]. When [recursive] is true,
  /// subfolders are traversed as well; when false, only direct children are
  /// returned.
  Stream<Result<PhotoItem>> listImages(
    PhotoFolder folder, {
    bool recursive = true,
    CancellationToken? token,
  });

  /// Downloads/copies [item] into the local cache and returns the resulting
  /// [File]. Implementations should be safe to call repeatedly for the same
  /// item (e.g. returning the already-cached file without re-downloading).
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token});

  /// Emits an event whenever the source's content may have changed (new
  /// photos added, folder renamed, ...).
  ///
  /// IMPORTANT / honesty note: most backing stores this app targets (SMB
  /// shares, WebDAV/Nextcloud without a push API, Android SAF folders) do
  /// not offer a real push/notification mechanism. For those sources this
  /// stream is expected to stay empty for the source's entire lifetime -
  /// callers must not assume it ever emits, and should keep relying on
  /// periodic polling (e.g. re-running [listImages] on a timer) to notice
  /// new content. Only a source with genuine push support (e.g. a future
  /// relay/server integration with websockets) would emit here.
  Stream<void> get changes;

  /// Releases any resources held by this source (open connections, file
  /// watchers, ...). After calling this, the instance must not be used
  /// again.
  Future<void> dispose();
}
