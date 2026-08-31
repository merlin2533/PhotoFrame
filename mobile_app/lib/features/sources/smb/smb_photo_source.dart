// UNVERIFIED - based on public package API docs, not tested against a real
// share (SMB spike M1 still pending, see docs/PLAN.md "SMB-Machbarkeit wird
// als Spike vorgezogen"). No SMB server/hardware is reachable from this
// environment, so nothing in this file has been exercised against a real
// Windows/Samba/NAS share. It is written carefully against the `smb_connect`
// package's public API (verified by reading its source in the pub cache),
// with defensive error handling everywhere a real network/protocol failure
// could otherwise surface as a crash, but the M1 spike must still validate
// this against real hardware on Android *and* iOS before shipping.
//
// Package choice: `smb_connect` was chosen over `samba_client` because it is
// a pure-Dart SMB1/SMB2 client (no native platform channel), which sidesteps
// the "iOS SMB support historically thin" risk called out in docs/PLAN.md -
// a pure-Dart implementation only needs raw socket access, which is
// available on iOS, whereas a wrapper around a native library (`libdsm`,
// jcifs via platform channel) tends to be Android-only or requires separate
// iOS porting effort. `smb_connect` also had a more recent pub.dev release
// at the time of writing (0.0.9, Jan 2025) than most alternatives in this
// niche. This is a documented *assumption*, not a verified conclusion - the
// M1 spike is exactly the activity that would confirm or refute it.

import 'dart:async';
import 'dart:io';

import 'package:smb_connect/smb_connect.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/result.dart';
import '../domain/media_type.dart';
import '../domain/photo_folder.dart';
import '../domain/photo_item.dart';
import '../domain/photo_source.dart';

/// Configuration needed to connect to one SMB share.
class SmbSourceConfig {
  const SmbSourceConfig({
    required this.host,
    required this.share,
    this.domain = '',
    this.username = '',
    this.password = '',
    this.rootPath = '',
  });

  final String host;
  final String share;
  final String domain;
  final String username;
  final String password;

  /// Path within [share] to treat as the source root, e.g. `Photos/Frame`.
  /// Empty string means the share root itself.
  final String rootPath;

  /// Non-secret fields only, for persisting via `SourceDescriptor.config` -
  /// [password] is deliberately NOT included; it lives solely in
  /// `SecureCredentialStore`, keyed by the owning source's id.
  Map<String, dynamic> toJson() => {
        'host': host,
        'share': share,
        'domain': domain,
        'username': username,
        'rootPath': rootPath,
      };

  /// Rebuilds a config from its non-secret [json] (as produced by [toJson])
  /// plus a [password] loaded separately from `SecureCredentialStore`.
  factory SmbSourceConfig.fromJson(Map<String, dynamic> json, {required String password}) {
    return SmbSourceConfig(
      host: json['host'] as String? ?? '',
      share: json['share'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: password,
      rootPath: json['rootPath'] as String? ?? '',
    );
  }
}

/// [PhotoSource] backed by an SMB/CIFS share, via the `smb_connect` package.
///
/// See the file-level comment above for the important "UNVERIFIED" caveat -
/// this class cannot be exercised against a real share in this environment.
class SmbPhotoSource implements PhotoSource {
  SmbPhotoSource({
    required this.id,
    required SmbSourceConfig config,
    String? displayName,
    Directory? cacheDirectory,
  })  : _config = config,
        displayName = displayName ?? 'SMB: ${config.host}/${config.share}',
        _cacheDirectory = cacheDirectory;

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.smb;

  SmbSourceConfig _config;
  final Directory? _cacheDirectory;

  SmbConnect? _connect;
  bool _disposed = false;
  int _unsupportedCount = 0;

  /// The currently active configuration, exposed so `source_descriptor.dart`
  /// can turn a live instance back into a persistable, non-secret
  /// [SourceDescriptor] via [SmbSourceConfig.toJson].
  SmbSourceConfig get config => _config;

  /// Extension whitelist, mirroring `LocalFolderSource` - shared logic isn't
  /// factored out yet since these sources may diverge (e.g. SMB one day
  /// exposing server-side thumbnails).
  /// Formats `Image.file`/Flutter's built-in codec can actually decode -
  /// see `local_folder_source.dart`'s doc comment on the same constant for
  /// why HEIC/HEIF moved out of this set (not decodable without an extra,
  /// not-yet-wired-in conversion step) and GIF moved in (it is decodable).
  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
  };

  /// Recognized-but-unsupported extensions: HEIC/HEIF/RAW plus video
  /// formats. Video clips are *not* played (P2 decision - see
  /// `docs/PLAN.md`'s `MediaType.video` note and
  /// `local_folder_source.dart`'s doc comment for the full rationale); they
  /// are counted like HEIC/RAW rather than surfaced as playable items.
  static const Set<String> _unsupportedMediaExtensions = {
    'heic', 'heif',
    'raw', 'cr2', 'cr3', 'nef', 'arw', 'dng', 'raf', 'orf', 'rw2', 'srw',
    'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp',
  };

  /// Number of files skipped in the most recent [listImages] run because
  /// they matched a known-but-unsupported media extension.
  int get unsupportedCount => _unsupportedCount;

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('SmbPhotoSource "$id" has already been disposed');
    }
  }

  /// Updates connection settings (e.g. after the user edits the config
  /// form). Any existing connection is dropped so the next operation
  /// reconnects with the new settings.
  void updateConfig(SmbSourceConfig config) {
    _config = config;
    _dropConnection();
  }

  void _dropConnection() {
    final connect = _connect;
    _connect = null;
    if (connect != null) {
      // Best-effort close; a share that's already gone away shouldn't throw
      // during cleanup.
      unawaited(connect.transport.close().catchError((_) {}));
    }
  }

  Future<Result<SmbConnect>> _ensureConnected(Duration timeout) async {
    final existing = _connect;
    if (existing != null) return Result.ok(existing);
    try {
      final connect = await SmbConnect.connectAuth(
        host: _config.host,
        username: _config.username,
        password: _config.password,
        domain: _config.domain,
      ).timeout(timeout);
      _connect = connect;
      return Result.ok(connect);
    } on TimeoutException {
      return Result.err(Timeout('Connecting to SMB host "${_config.host}" timed out'));
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('logon') || msg.contains('access') || msg.contains('password')) {
        return Result.err(AuthError('SMB authentication failed for "${_config.host}"', cause: e));
      }
      return Result.err(NetworkError('Could not connect to SMB host "${_config.host}"', cause: e));
    }
  }

  String _fullPath(String relativePath) {
    final combined = [
      _config.share,
      if (_config.rootPath.isNotEmpty) _config.rootPath,
      if (relativePath.isNotEmpty) relativePath,
    ].join('/');
    return '/$combined';
  }

  @override
  Future<Result<ConnectionStatus>> testConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _checkNotDisposed();
    final stopwatch = Stopwatch()..start();
    try {
      final reachable = await SmbConnect.pingConnection(
        host: _config.host,
        username: _config.username,
        password: _config.password,
        domain: _config.domain,
      ).timeout(timeout);
      if (!reachable) {
        return Result.err(NetworkError('SMB host "${_config.host}" is not reachable'));
      }

      final connectResult = await _ensureConnected(timeout);
      if (connectResult.isErr) {
        return Result.err(connectResult.failureOrNull!);
      }
      final connect = connectResult.valueOrNull!;

      final rootFile = await connect.file(_fullPath('')).timeout(timeout);
      if (!rootFile.isExists) {
        return Result.err(
          NotFound('Share/folder not found: ${_config.share}/${_config.rootPath}'),
        );
      }
      stopwatch.stop();
      return Result.ok(
        ConnectionStatus(
          reachable: true,
          latency: stopwatch.elapsed,
          detail: 'Connected to \\\\${_config.host}\\${_config.share}',
        ),
      );
    } on TimeoutException {
      return Result.err(Timeout('SMB connection test to "${_config.host}" timed out'));
    } catch (e) {
      return Result.err(NetworkError('Unexpected error testing SMB connection', cause: e));
    }
  }

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    final connectResult = await _ensureConnected(const Duration(seconds: 8));
    if (connectResult.isErr) {
      yield Result.err(connectResult.failureOrNull!);
      return;
    }
    final connect = connectResult.valueOrNull!;
    final startRelPath = parent?.path ?? '';

    try {
      yield* _walkFolders(connect, startRelPath, token);
    } on CancelledException {
      rethrow;
    } catch (e) {
      yield Result.err(NetworkError('Unexpected error listing SMB folders', cause: e));
    }
  }

  Stream<Result<PhotoFolder>> _walkFolders(
    SmbConnect connect,
    String relPath,
    CancellationToken? token,
  ) async* {
    token?.throwIfCancelled();
    List<SmbFile> children;
    try {
      final folder = await connect.file(_fullPath(relPath));
      children = await connect.listFiles(folder);
    } catch (e) {
      yield Result.err(NetworkError('Failed to list SMB folder "$relPath"', cause: e));
      return;
    }

    for (final child in children) {
      token?.throwIfCancelled();
      if (!child.isDirectory()) continue;
      if (child.name == '.' || child.name == '..') continue;
      final childRelPath = relPath.isEmpty ? child.name : '$relPath/${child.name}';
      yield Result.ok(
        PhotoFolder(
          id: childRelPath,
          name: child.name,
          path: childRelPath,
          parentId: relPath.isEmpty ? null : relPath,
        ),
      );
      yield* _walkFolders(connect, childRelPath, token);
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
    final connectResult = await _ensureConnected(const Duration(seconds: 8));
    if (connectResult.isErr) {
      yield Result.err(connectResult.failureOrNull!);
      return;
    }
    final connect = connectResult.valueOrNull!;

    try {
      yield* _walkImages(connect, folder.path, recursive, token);
    } on CancelledException {
      rethrow;
    } catch (e) {
      yield Result.err(NetworkError('Unexpected error listing SMB images', cause: e));
    }
  }

  Stream<Result<PhotoItem>> _walkImages(
    SmbConnect connect,
    String relPath,
    bool recursive,
    CancellationToken? token,
  ) async* {
    token?.throwIfCancelled();
    List<SmbFile> children;
    try {
      final folder = await connect.file(_fullPath(relPath));
      children = await connect.listFiles(folder);
    } catch (e) {
      yield Result.err(NetworkError('Failed to list SMB folder "$relPath"', cause: e));
      return;
    }

    for (final child in children) {
      token?.throwIfCancelled();
      if (child.name == '.' || child.name == '..') continue;

      if (child.isDirectory()) {
        if (recursive) {
          final childRelPath = relPath.isEmpty ? child.name : '$relPath/${child.name}';
          yield* _walkImages(connect, childRelPath, recursive, token);
        }
        continue;
      }

      final ext = _extensionOf(child.name);
      if (ext == null) continue;
      if (_unsupportedMediaExtensions.contains(ext)) {
        _unsupportedCount++;
        continue;
      }
      if (!_imageExtensions.contains(ext)) continue;

      final childRelPath = relPath.isEmpty ? child.name : '$relPath/${child.name}';
      yield Result.ok(
        PhotoItem(
          id: childRelPath,
          sourceId: id,
          folderId: relPath,
          name: child.name,
          mediaType: MediaType.image,
          size: child.size,
          // `SmbFile.lastModified` is documented by the package only as "an
          // int timestamp" without units confirmed against a live server in
          // this environment - treated as epoch milliseconds, matching the
          // package's own Dart-facing convention elsewhere. UNVERIFIED.
          mtime: DateTime.fromMillisecondsSinceEpoch(child.lastModified),
        ),
      );
    }
  }

  @override
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token}) async {
    _checkNotDisposed();
    token?.throwIfCancelled();
    final connectResult = await _ensureConnected(const Duration(seconds: 8));
    if (connectResult.isErr) {
      return Result.err(connectResult.failureOrNull!);
    }
    final connect = connectResult.valueOrNull!;

    try {
      final remoteFile = await connect.file(_fullPath(item.id));
      if (!remoteFile.isExists) {
        return Result.err(NotFound('SMB file no longer exists: ${item.id}'));
      }

      final dir = _cacheDirectory ?? Directory.systemTemp;
      final localFile = File(
        '${dir.path}${Platform.pathSeparator}smb_${id}_${item.id.replaceAll('/', '_')}',
      );
      await localFile.parent.create(recursive: true);

      final sink = localFile.openWrite();
      try {
        final stream = await connect.openRead(remoteFile);
        await for (final chunk in stream) {
          token?.throwIfCancelled();
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return Result.ok(localFile);
    } on CancelledException {
      rethrow;
    } on TimeoutException {
      return Result.err(Timeout('Fetching SMB file "${item.id}" timed out'));
    } catch (e) {
      return Result.err(NetworkError('Failed to fetch SMB file "${item.id}"', cause: e));
    }
  }

  /// SMB shares don't push change notifications - see the honesty note on
  /// [PhotoSource.changes].
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _dropConnection();
  }
}
