import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../../core/errors/failure.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/result.dart';
import '../domain/media_type.dart';
import '../domain/photo_folder.dart';
import '../domain/photo_item.dart';
import '../domain/photo_source.dart';

/// Signature used to pick a directory on disk, matching
/// `FilePicker.platform.getDirectoryPath`. Injectable so tests (and this
/// review, since no device/emulator is available here) don't need to touch
/// the real Storage Access Framework/native folder picker.
typedef DirectoryPicker = Future<String?> Function({String? dialogTitle});

/// [PhotoSource] backed by a folder picked directly on the device (Android
/// Storage Access Framework via `file_picker`, or a plain filesystem path on
/// other platforms, e.g. a mounted USB stick). This is the "reliable
/// fallback" source called for in docs/PLAN.md's SMB-spike section: no
/// network/protocol involved, so it degrades gracefully to
/// [PermissionDenied]/[NotFound] failures (folder revoked, USB stick pulled)
/// instead of ever crashing the slideshow.
///
/// Design notes:
///  - Folder/item ids are the POSIX-style path *relative to the configured
///    root*, with the root itself using the empty string `''`. This keeps
///    ids stable across app restarts as long as the root path itself
///    doesn't change, and lets [fetchToCache] resolve an absolute path by
///    simply joining the root with the id.
///  - [fetchToCache] does **not** copy the file into a separate app cache
///    directory: the source file already lives on local/removable storage,
///    so copying it would double disk usage for no benefit. It returns a
///    [File] pointing directly at the already-local file. If the file has
///    disappeared (USB stick pulled) between listing and fetch, this
///    surfaces as [NotFound] rather than a crash.
///  - Image detection uses an extension whitelist. GIF, common RAW formats,
///    and video files (mp4/mov/...) are recognized-but-unsupported: they are
///    excluded from [listImages] results but counted in [unsupportedCount]
///    rather than silently vanishing, so a future UI can surface "N files
///    skipped (unsupported format)".
class LocalFolderSource implements PhotoSource {
  LocalFolderSource({
    required this.id,
    String? displayName,
    String? rootPath,
    DirectoryPicker? directoryPicker,
  })  : displayName = displayName ?? 'Local Folder',
        _rootPath = rootPath,
        _directoryPicker = directoryPicker ?? _defaultDirectoryPicker;

  static Future<String?> _defaultDirectoryPicker({String? dialogTitle}) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.local;

  final DirectoryPicker _directoryPicker;

  String? _rootPath;

  /// The currently configured root folder's absolute path, or `null` if the
  /// user hasn't picked one yet.
  String? get rootPath => _rootPath;

  /// Extensions recognized as displayable images.
  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  /// Extensions recognized as media but not currently displayable. These are
  /// excluded from [listImages] but counted in [unsupportedCount] instead of
  /// being dropped without a trace.
  ///
  /// **Video clips (P2 decision):** `docs/PLAN.md` reserves
  /// `MediaType.video` on `PhotoItem` for a later "kurzer Loop wie bei
  /// Frameo" feature, but per explicit product decision that feature is
  /// *not* being built in this round - video files are treated exactly like
  /// GIF/RAW: recognized, counted here, and filtered out of [listImages]
  /// rather than surfaced as `MediaType.video` items. Should video playback
  /// be added later, only this set (and the classification below) needs to
  /// change - `MediaType.video` already exists on the model for that.
  static const Set<String> _unsupportedMediaExtensions = {
    'gif',
    // Common RAW formats.
    'raw', 'cr2', 'cr3', 'nef', 'arw', 'dng', 'raf', 'orf', 'rw2', 'srw',
    // Video formats - recognized-but-unsupported, see doc comment above.
    'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp',
  };

  int _unsupportedCount = 0;

  /// Number of files encountered during the most recent [listImages] run
  /// that matched a known-but-unsupported media extension (GIF/RAW/...).
  /// Reset at the start of every [listImages] call.
  int get unsupportedCount => _unsupportedCount;

  bool _disposed = false;

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('LocalFolderSource "$id" has already been disposed');
    }
  }

  /// Opens the platform folder picker (SAF on Android) and, if the user
  /// picked one, stores it as [rootPath]. Returns the picked path, or `null`
  /// if the user cancelled.
  Future<Result<String?>> pickRootFolder({String? dialogTitle}) async {
    _checkNotDisposed();
    try {
      final path = await _directoryPicker(dialogTitle: dialogTitle);
      if (path != null) {
        _rootPath = path;
      }
      return Result.ok(path);
    } on PlatformException catch (e) {
      return Result.err(
        PermissionDenied('Folder picker failed/was denied', cause: e),
      );
    } catch (e) {
      return Result.err(NetworkError('Folder picker failed unexpectedly', cause: e));
    }
  }

  @override
  Future<Result<ConnectionStatus>> testConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _checkNotDisposed();
    final root = _rootPath;
    if (root == null) {
      return Result.err(const NotFound('No local folder configured yet'));
    }
    final stopwatch = Stopwatch()..start();
    try {
      final dir = Directory(root);
      if (!await dir.exists().timeout(timeout)) {
        return Result.err(
          NotFound('Folder no longer exists: $root (was it removed/unmounted?)'),
        );
      }
      // Cheaply probe readability: listing lazily throws on the first
      // `moveNext()` if permission was revoked or the medium went away
      // (e.g. a USB stick pulled after the folder was granted).
      final iterator = dir.list().listen(null);
      try {
        await Future<void>.delayed(Duration.zero);
      } finally {
        await iterator.cancel();
      }
      stopwatch.stop();
      return Result.ok(
        ConnectionStatus(
          reachable: true,
          latency: stopwatch.elapsed,
          detail: 'Folder readable: $root',
        ),
      );
    } on TimeoutException {
      return Result.err(Timeout('Checking local folder "$root" timed out'));
    } on FileSystemException catch (e) {
      final denied = e.osError?.errorCode == 13 /* EACCES */;
      return Result.err(
        denied
            ? PermissionDenied('Permission denied reading folder: $root', cause: e)
            : NotFound('Folder not accessible: $root', cause: e),
      );
    } catch (e) {
      return Result.err(NetworkError('Unexpected error checking folder: $root', cause: e));
    }
  }

  String _relativeId(String rootPath, String absolutePath) {
    var rel = absolutePath.substring(rootPath.length);
    rel = rel.replaceAll('\\', '/');
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    return rel;
  }

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    final root = _rootPath;
    if (root == null) {
      yield Result.err(const NotFound('No local folder configured yet'));
      return;
    }

    final startDir = Directory(
      parent == null ? root : '$root${Platform.pathSeparator}${parent.path}',
    );

    try {
      await for (final entity in startDir.list(recursive: true, followLinks: false)) {
        token?.throwIfCancelled();
        if (entity is! Directory) continue;
        final relId = _relativeId(root, entity.path);
        if (relId.isEmpty) continue;
        final parts = relId.split('/');
        final parentId = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : null;
        yield Result.ok(
          PhotoFolder(
            id: relId,
            name: parts.last,
            path: relId,
            parentId: parentId,
          ),
        );
      }
    } on CancelledException {
      rethrow;
    } on FileSystemException catch (e) {
      final denied = e.osError?.errorCode == 13;
      yield Result.err(
        denied
            ? PermissionDenied('Permission denied listing folders under $root', cause: e)
            : NotFound('Folder not accessible: $root', cause: e),
      );
    } catch (e) {
      yield Result.err(NetworkError('Unexpected error listing folders', cause: e));
    }
  }

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }

  @override
  Stream<Result<PhotoItem>> listImages(
    PhotoFolder folder, {
    bool recursive = true,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    final root = _rootPath;
    if (root == null) {
      yield Result.err(const NotFound('No local folder configured yet'));
      return;
    }

    _unsupportedCount = 0;
    final startDir = Directory('$root${Platform.pathSeparator}${folder.path}');

    try {
      final stream = startDir.list(recursive: recursive, followLinks: false);
      await for (final entity in stream) {
        token?.throwIfCancelled();
        if (entity is! File) continue;
        final ext = _extensionOf(entity.path);
        if (ext == null) continue;

        if (_unsupportedMediaExtensions.contains(ext)) {
          _unsupportedCount++;
          continue;
        }
        if (!_imageExtensions.contains(ext)) {
          // Not an image and not a known "unsupported media" extension
          // either (e.g. .txt, .db, Thumbs.db) - silently ignored, this is
          // not a photo library asset at all.
          continue;
        }

        FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          // Vanished between listing and stat (e.g. concurrent deletion) -
          // skip rather than fail the whole listing.
          continue;
        }

        final relId = _relativeId(root, entity.path);
        final relFolder = _relativeId(root, entity.parent.path);
        yield Result.ok(
          PhotoItem(
            id: relId,
            sourceId: id,
            folderId: relFolder,
            name: entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : relId,
            mediaType: MediaType.image,
            size: stat.size,
            mtime: stat.modified,
          ),
        );
      }
    } on CancelledException {
      rethrow;
    } on FileSystemException catch (e) {
      final denied = e.osError?.errorCode == 13;
      yield Result.err(
        denied
            ? PermissionDenied('Permission denied listing images under ${folder.path}', cause: e)
            : NotFound('Folder not accessible: ${folder.path}', cause: e),
      );
    } catch (e) {
      yield Result.err(NetworkError('Unexpected error listing images', cause: e));
    }
  }

  @override
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token}) async {
    _checkNotDisposed();
    token?.throwIfCancelled();
    final root = _rootPath;
    if (root == null) {
      return Result.err(const NotFound('No local folder configured yet'));
    }
    final file = File('$root${Platform.pathSeparator}${item.id}');
    try {
      if (!await file.exists()) {
        return Result.err(
          NotFound('File no longer exists: ${item.id} (medium removed?)'),
        );
      }
      // Local source: the file is already on-device, no copy needed - see
      // class doc comment.
      return Result.ok(file);
    } on FileSystemException catch (e) {
      final denied = e.osError?.errorCode == 13;
      return Result.err(
        denied
            ? PermissionDenied('Permission denied reading file: ${item.id}', cause: e)
            : NotFound('File not accessible: ${item.id}', cause: e),
      );
    }
  }

  /// SAF/local folders never push change notifications - see the honesty
  /// note on [PhotoSource.changes].
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
