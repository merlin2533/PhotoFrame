import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../../core/errors/failure.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/result.dart';
import '../domain/media_type.dart';
import '../domain/photo_folder.dart';
import '../domain/photo_item.dart';
import '../domain/photo_source.dart';
import '../domain/uploadable_photo_source.dart';
import 'nextcloud_config_form_model.dart';

/// Fully-resolved connection details for [NextcloudPhotoSource], derived
/// from a validated [NextcloudConfigFormModel] via
/// [NextcloudSourceConfig.fromForm].
///
/// Package choice: `webdav_client` (already a project dependency, see
/// pubspec.yaml) is used directly rather than hand-rolling WebDAV over raw
/// `http`. It wraps `dio`, already used elsewhere in this app for the relay
/// client, and already implements PROPFIND/GET/PUT/MKCOL XML handling
/// correctly - reimplementing that by hand would be substantially more
/// code and a second place to get WebDAV multistatus XML parsing wrong.
class NextcloudSourceConfig {
  const NextcloudSourceConfig({
    required this.davBaseUrl,
    required this.authUsername,
    required this.authPassword,
    required this.rootPath,
    required this.isShareLink,
  });

  /// Full WebDAV endpoint base, e.g.
  /// `https://cloud.example.com/remote.php/dav/files/alice` (account) or
  /// `https://cloud.example.com/public.php/webdav` (share link).
  final String davBaseUrl;

  final String authUsername;
  final String authPassword;

  /// Root folder path within the WebDAV endpoint (no leading/trailing `/`).
  final String rootPath;

  final bool isShareLink;

  /// Non-secret fields only, for persisting via `SourceDescriptor.config` -
  /// [authPassword] is deliberately NOT included; it lives solely in
  /// `SecureCredentialStore`, keyed by the owning source's id. Note
  /// [authUsername] is stored as-is even for a share link (where it holds
  /// the share token, not a real secret - see the field doc above).
  Map<String, dynamic> toJson() => {
        'davBaseUrl': davBaseUrl,
        'authUsername': authUsername,
        'rootPath': rootPath,
        'isShareLink': isShareLink,
      };

  /// Rebuilds a config from its non-secret [json] (as produced by [toJson])
  /// plus a [password] loaded separately from `SecureCredentialStore`.
  factory NextcloudSourceConfig.fromJson(Map<String, dynamic> json, {required String password}) {
    return NextcloudSourceConfig(
      davBaseUrl: json['davBaseUrl'] as String? ?? '',
      authUsername: json['authUsername'] as String? ?? '',
      authPassword: password,
      rootPath: json['rootPath'] as String? ?? '',
      isShareLink: json['isShareLink'] as bool? ?? false,
    );
  }

  factory NextcloudSourceConfig.fromForm(NextcloudConfigFormModel form) {
    final normalized = form.normalized();
    switch (normalized.authKind) {
      case NextcloudAuthKind.account:
        return NextcloudSourceConfig(
          davBaseUrl: '${normalized.serverUrl}/remote.php/dav/files/${normalized.username}',
          authUsername: normalized.username,
          authPassword: normalized.appPassword,
          rootPath: normalized.folderPath,
          isShareLink: false,
        );
      case NextcloudAuthKind.shareLink:
        return NextcloudSourceConfig(
          davBaseUrl: '${normalized.serverUrl}/public.php/webdav',
          // Nextcloud's public WebDAV endpoint expects the share token as
          // the Basic-Auth *username*, with the (optional) share password
          // as the password - see Nextcloud WebDAV API docs.
          authUsername: normalized.shareToken,
          authPassword: normalized.sharePassword,
          rootPath: normalized.folderPath,
          isShareLink: true,
        );
    }
  }
}

/// [PhotoSource] (+ [UploadablePhotoSource]) backed by a Nextcloud instance
/// over WebDAV, supporting both an authenticated account and a public share
/// link (see docs/PLAN.md "Nextcloud: Lese- UND Schreibzugriff").
class NextcloudPhotoSource implements PhotoSource, UploadablePhotoSource {
  NextcloudPhotoSource({
    required this.id,
    required NextcloudSourceConfig config,
    String? displayName,
    Directory? cacheDirectory,
  })  : _config = config,
        displayName = displayName ?? 'Nextcloud',
        _cacheDirectory = cacheDirectory {
    _client = _buildClient(config);
  }

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.nextcloud;

  NextcloudSourceConfig _config;
  final Directory? _cacheDirectory;
  late webdav.Client _client;
  bool _disposed = false;

  /// The currently active configuration, exposed so `source_descriptor.dart`
  /// can turn a live instance back into a persistable, non-secret
  /// [SourceDescriptor] via [NextcloudSourceConfig.toJson].
  NextcloudSourceConfig get config => _config;

  bool _canUpload = false;

  /// Whether the last [testConnection] determined this source (account or
  /// share link) currently has write access. `false` until the first
  /// successful [testConnection] call.
  @override
  bool get canUpload => _canUpload;

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  /// Recognized-but-unsupported extensions: GIF/RAW plus video formats.
  /// Video clips are *not* played (P2 decision - see `docs/PLAN.md`'s
  /// `MediaType.video` note and `local_folder_source.dart`'s doc comment for
  /// the full rationale); they are counted like GIF/RAW rather than
  /// surfaced as playable items.
  static const Set<String> _unsupportedMediaExtensions = {
    'gif',
    'raw', 'cr2', 'cr3', 'nef', 'arw', 'dng', 'raf', 'orf', 'rw2', 'srw',
    'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp',
  };

  int _unsupportedCount = 0;
  int get unsupportedCount => _unsupportedCount;

  webdav.Client _buildClient(NextcloudSourceConfig config) {
    return webdav.newClient(
      config.davBaseUrl,
      user: config.authUsername,
      password: config.authPassword,
    );
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('NextcloudPhotoSource "$id" has already been disposed');
    }
  }

  void updateConfig(NextcloudSourceConfig config) {
    _config = config;
    _client = _buildClient(config);
    _canUpload = false;
  }

  String _davPath(String relativePath) {
    final parts = [
      if (_config.rootPath.isNotEmpty) _config.rootPath,
      if (relativePath.isNotEmpty) relativePath,
    ];
    final joined = parts.join('/');
    return '/$joined';
  }

  Failure _mapError(Object e, {required String context}) {
    // `webdav_client` doesn't define its own exception type - failed
    // requests surface as the underlying `dio` `DioException`, with the
    // WebDAV response (if any) attached via `.response`.
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return Timeout('$context timed out', cause: e);
      }
      if (status == 401 || status == 403) {
        return AuthError('$context: authentication/permission failed (HTTP $status)', cause: e);
      }
      if (status == 404) {
        return NotFound('$context: not found (HTTP $status)', cause: e);
      }
      if (status == 507 || status == 413) {
        return QuotaExceeded('$context: quota/size limit exceeded (HTTP $status)', cause: e);
      }
      return NetworkError('$context failed (HTTP ${status ?? '?'})', cause: e);
    }
    if (e is TimeoutException) {
      return Timeout('$context timed out', cause: e);
    }
    return NetworkError('$context failed unexpectedly', cause: e);
  }

  @override
  Future<Result<ConnectionStatus>> testConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _checkNotDisposed();
    _client.setConnectTimeout(timeout.inMilliseconds);
    _client.setReceiveTimeout(timeout.inMilliseconds);
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Read-access probe: PROPFIND on the configured root.
      await _client.readDir(_davPath(''));

      // 2. Write-permission detection. Nextcloud's WebDAV PROPFIND response
      // doesn't reliably expose an `Allow`/method-capability header the way
      // a generic WebDAV OPTIONS response might, and share links in
      // particular vary permission by server configuration - so the most
      // reliable signal is a real, but fully non-destructive, write
      // attempt: PUT a small marker file, then DELETE it immediately.
      _canUpload = await _probeWriteAccess();

      stopwatch.stop();
      return Result.ok(
        ConnectionStatus(
          reachable: true,
          latency: stopwatch.elapsed,
          detail: _canUpload
              ? 'Connected, read/write access'
              : 'Connected, read-only access',
        ),
      );
    } catch (e) {
      return Result.err(_mapError(e, context: 'Nextcloud connection test'));
    }
  }

  Future<bool> _probeWriteAccess() async {
    final probePath = _davPath('.photoframe_write_probe_${DateTime.now().microsecondsSinceEpoch}');
    try {
      await _client.write(probePath, Uint8List(0));
      // Clean up immediately - this must never leave a stray file behind.
      try {
        await _client.remove(probePath);
      } catch (_) {
        // Cleanup failure shouldn't flip the detected permission back to
        // false - the write itself already proved write access.
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    final relPath = parent?.path ?? '';
    try {
      final entries = await _client.readDir(_davPath(relPath));
      for (final entry in entries) {
        token?.throwIfCancelled();
        if (entry.isDir != true) continue;
        final name = entry.name ?? '';
        if (name.isEmpty) continue;
        final childRelPath = relPath.isEmpty ? name : '$relPath/$name';
        yield Result.ok(
          PhotoFolder(
            id: childRelPath,
            name: name,
            path: childRelPath,
            parentId: relPath.isEmpty ? null : relPath,
          ),
        );
      }
    } on CancelledException {
      rethrow;
    } catch (e) {
      yield Result.err(_mapError(e, context: 'Listing Nextcloud folders'));
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
    _unsupportedCount = 0;
    try {
      yield* _walkImages(folder.path, recursive, token);
    } on CancelledException {
      rethrow;
    } catch (e) {
      yield Result.err(_mapError(e, context: 'Listing Nextcloud images'));
    }
  }

  Stream<Result<PhotoItem>> _walkImages(
    String relPath,
    bool recursive,
    CancellationToken? token,
  ) async* {
    token?.throwIfCancelled();
    List<webdav.File> entries;
    try {
      entries = await _client.readDir(_davPath(relPath));
    } catch (e) {
      yield Result.err(_mapError(e, context: 'Listing Nextcloud folder "$relPath"'));
      return;
    }

    for (final entry in entries) {
      token?.throwIfCancelled();
      final name = entry.name ?? '';
      if (name.isEmpty) continue;
      final childRelPath = relPath.isEmpty ? name : '$relPath/$name';

      if (entry.isDir == true) {
        if (recursive) {
          yield* _walkImages(childRelPath, recursive, token);
        }
        continue;
      }

      final ext = _extensionOf(name);
      if (ext == null) continue;
      if (_unsupportedMediaExtensions.contains(ext)) {
        _unsupportedCount++;
        continue;
      }
      if (!_imageExtensions.contains(ext)) continue;

      yield Result.ok(
        PhotoItem(
          id: childRelPath,
          sourceId: id,
          folderId: relPath,
          name: name,
          mediaType: MediaType.image,
          size: entry.size ?? 0,
          mtime: entry.mTime ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
  }

  @override
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token}) async {
    _checkNotDisposed();
    token?.throwIfCancelled();
    try {
      final dir = _cacheDirectory ?? Directory.systemTemp;
      final localFile = File(
        '${dir.path}${Platform.pathSeparator}nextcloud_${id}_${item.id.replaceAll('/', '_')}',
      );
      await localFile.parent.create(recursive: true);
      await _client.read2File(_davPath(item.id), localFile.path);
      token?.throwIfCancelled();
      return Result.ok(localFile);
    } on CancelledException {
      rethrow;
    } catch (e) {
      return Result.err(_mapError(e, context: 'Fetching Nextcloud file "${item.id}"'));
    }
  }

  @override
  Future<Result<void>> uploadImage(File file, {PhotoFolder? targetFolder}) async {
    _checkNotDisposed();
    if (!_canUpload) {
      return Result.err(
        const Unsupported('This Nextcloud source is read-only (no write permission detected)'),
      );
    }
    try {
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetRel = targetFolder?.path ?? '';
      final remotePath = _davPath(targetRel.isEmpty ? name : '$targetRel/$name');
      await _client.writeFromFile(file.path, remotePath);
      return Result.ok(null);
    } catch (e) {
      return Result.err(_mapError(e, context: 'Uploading to Nextcloud'));
    }
  }

  /// Nextcloud/WebDAV has no push-notification mechanism this app consumes
  /// - see the honesty note on [PhotoSource.changes]. Change detection
  /// happens via `source_registry.dart` polling instead.
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
