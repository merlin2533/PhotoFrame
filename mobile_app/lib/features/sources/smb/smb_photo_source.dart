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
  factory SmbSourceConfig.fromJson(Map<String, dynamic> json,
      {required String password}) {
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
    Future<SmbConnect> Function(SmbSourceConfig config)? connector,
    Duration stepTimeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  })  : _config = config,
        displayName = displayName ?? 'SMB: ${config.share}',
        _cacheDirectory = cacheDirectory,
        _connector = connector ?? _defaultConnector,
        _stepTimeout = stepTimeout,
        _now = clock ?? DateTime.now;

  /// Opens a new authenticated connection for [config]. Injectable so tests
  /// can drive connect timing without a real SMB server.
  static Future<SmbConnect> _defaultConnector(SmbSourceConfig config) {
    return SmbConnect.connectAuth(
      host: config.host,
      username: config.username,
      password: config.password,
      domain: config.domain,
    );
  }

  final Future<SmbConnect> Function(SmbSourceConfig config) _connector;

  /// Upper bound for each single network step (file lookup, directory listing,
  /// opening/reading a download). On a dead socket the library never answers,
  /// so every step is bounded.
  final Duration _stepTimeout;

  /// Clock used for connection age; injectable for tests.
  final DateTime Function() _now;

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.smb;

  SmbSourceConfig _config;
  final Directory? _cacheDirectory;

  SmbConnect? _connect;

  /// When the current connection was opened. A connection is only reused while
  /// it is younger than [_connectionMaxAge]; older ones are closed and replaced.
  /// The SMB library keeps writing to a socket the server may already have
  /// closed (or that has gone slow), which surfaces as "StreamSink is closed"
  /// errors and timeouts on the device.
  DateTime _connectedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// A connection is reused only if it was established less than this long
  /// ago (strictly less than: a connection aged exactly 10 s is replaced).
  static const _connectionMaxAge = Duration(seconds: 10);
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
    'heic',
    'heif',
    'raw',
    'cr2',
    'cr3',
    'nef',
    'arw',
    'dng',
    'raf',
    'orf',
    'rw2',
    'srw',
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    'webm',
    '3gp',
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
    if (connect != null) _closeQuietly(connect);
  }

  /// Best-effort close of [connect]; a share that's already gone away
  /// shouldn't throw during cleanup.
  static void _closeQuietly(SmbConnect connect) {
    unawaited(connect.transport.close().catchError((_) {}));
  }

  /// The connect currently in progress, if any. A second caller awaits this
  /// same future instead of opening another transport.
  Future<Result<SmbConnect>>? _connecting;

  Future<Result<SmbConnect>> _ensureConnected(Duration timeout) {
    final existing = _connect;
    final fresh = _now().difference(_connectedAt) < _connectionMaxAge;
    if (existing != null && fresh) return Future.value(Result.ok(existing));
    final running = _connecting;
    if (running != null) return running;
    // Too old: close the stale transport instead of orphaning it.
    _dropConnection();
    final connecting = _connectNew(timeout);
    _connecting = connecting;
    return connecting.whenComplete(() {
      if (identical(_connecting, connecting)) _connecting = null;
    });
  }

  Future<Result<SmbConnect>> _connectNew(Duration timeout) async {
    final config = _config;
    final attempt = Future.sync(() => _connector(config));
    try {
      final connect = await attempt.timeout(timeout);
      if (_disposed || !identical(_config, config)) {
        // Disposed or reconfigured while connecting: this connection is
        // already outdated and nobody would own it.
        _closeQuietly(connect);
        return Result.err(const NetworkError(
            'SMB-Verbindung wurde während des Verbindungsaufbaus verworfen'));
      }
      _connect = connect;
      _connectedAt = _now();
      return Result.ok(connect);
    } on TimeoutException {
      // The abandoned attempt may still complete later; close whatever it
      // yields so that transport does not leak.
      unawaited(attempt.then(_closeQuietly, onError: (_) {}));
      return Result.err(Timeout(
          'Verbindung zu "${config.host}" dauert zu lange – Netzwerk oder Host prüfen'));
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('logon') ||
          msg.contains('access') ||
          msg.contains('password')) {
        return Result.err(AuthError(
            'SMB authentication failed for "${config.host}"',
            cause: e));
      }
      return Result.err(NetworkError(
          'Could not connect to SMB host "${config.host}"',
          cause: e));
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
        return Result.err(
            NetworkError('SMB-Host "${_config.host}" ist nicht erreichbar'));
      }

      final connectResult = await _ensureConnected(timeout);
      if (connectResult.isErr) {
        return Result.err(connectResult.failureOrNull!);
      }
      final connect = connectResult.valueOrNull!;

      final rootFile = await connect.file(_fullPath('')).timeout(timeout);
      if (!rootFile.isExists) {
        return Result.err(
          NotFound(
              'Share/folder not found: "${_config.share}/${_config.rootPath}"'),
        );
      }
      stopwatch.stop();
      return Result.ok(
        ConnectionStatus(
          reachable: true,
          latency: stopwatch.elapsed,
          detail: 'Connected to "\\\\${_config.host}\\${_config.share}"',
        ),
      );
    } on TimeoutException {
      return Result.err(Timeout(
          'Verbindungstest zu "${_config.host}" hat zu lange gedauert'));
    } catch (e) {
      return Result.err(NetworkError(
          'Unerwarteter Fehler beim SMB-Verbindungstest',
          cause: e));
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
      yield Result.err(NetworkError(
          'Unerwarteter Fehler beim Lesen der SMB-Ordner',
          cause: e));
    }
  }

  /// Lists the direct children of [relPath] with a timeout on each network
  /// step. On a timeout or error the broken connection is dropped and a
  /// failure is returned, so the caller always gets a result and never waits
  /// on a dead socket.
  Future<Result<List<SmbFile>>> _listChildren(
    SmbConnect connect,
    String relPath,
  ) async {
    try {
      final folder =
          await connect.file(_fullPath(relPath)).timeout(_stepTimeout);
      final children =
          await connect.listFiles(folder).timeout(_stepTimeout);
      return Result.ok(children);
    } on TimeoutException {
      _dropBrokenConnection(connect);
      return Result.err(Timeout(
          'SMB-Ordner "$relPath" hat zu lange gedauert – Verbindung wird neu aufgebaut'));
    } catch (e) {
      _dropBrokenConnection(connect);
      return Result.err(NetworkError(
          'SMB-Ordner "$relPath" konnte nicht gelesen werden',
          cause: e));
    }
  }

  Stream<Result<PhotoFolder>> _walkFolders(
    SmbConnect connect,
    String relPath,
    CancellationToken? token,
  ) async* {
    token?.throwIfCancelled();
    final listed = await _listChildren(connect, relPath);
    if (listed.isErr) {
      yield Result.err(listed.failureOrNull!);
      return;
    }
    final children = listed.valueOrNull!;

    for (final child in children) {
      token?.throwIfCancelled();
      if (!child.isDirectory()) continue;
      if (child.name == '.' || child.name == '..') continue;
      final childRelPath =
          relPath.isEmpty ? child.name : '$relPath/${child.name}';
      // Only the direct children: the folder picker navigates level by level,
      // and the slideshow crawl reads each subtree through listImages.
      yield Result.ok(
        PhotoFolder(
          id: childRelPath,
          name: child.name,
          path: childRelPath,
          parentId: relPath.isEmpty ? null : relPath,
        ),
      );
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
      yield Result.err(NetworkError(
          'Unerwarteter Fehler beim Lesen der SMB-Bilder',
          cause: e));
    }
  }

  Stream<Result<PhotoItem>> _walkImages(
    SmbConnect connect,
    String relPath,
    bool recursive,
    CancellationToken? token,
  ) async* {
    token?.throwIfCancelled();
    final listed = await _listChildren(connect, relPath);
    if (listed.isErr) {
      yield Result.err(listed.failureOrNull!);
      return;
    }
    final children = listed.valueOrNull!;

    for (final child in children) {
      token?.throwIfCancelled();
      if (child.name == '.' || child.name == '..') continue;

      if (child.isDirectory()) {
        if (recursive) {
          final childRelPath =
              relPath.isEmpty ? child.name : '$relPath/${child.name}';
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

      final childRelPath =
          relPath.isEmpty ? child.name : '$relPath/${child.name}';
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

  /// Downloads in progress, by item id. A second request for the same photo
  /// (prefetch and display can ask at the same time) waits for the first
  /// download instead of writing the same file twice.
  final Map<String, Future<Result<File>>> _inFlight = {};

  @override
  Future<Result<File>> fetchToCache(PhotoItem item,
      {CancellationToken? token}) {
    final running = _inFlight[item.id];
    if (running != null) return running;
    final download = _fetchOnce(item, token: token);
    _inFlight[item.id] = download;
    return download.whenComplete(() => _inFlight.remove(item.id));
  }

  /// Downloads [item] into the cache. The first attempt reuses the current
  /// connection only if it is younger than [_connectionMaxAge] (see
  /// [_ensureConnected]). If that attempt fails for any reason other than a
  /// missing file, it is retried exactly once on a fresh connection; the
  /// failed attempt has already dropped its connection and removed its partial
  /// file. Cancellation is never retried.
  Future<Result<File>> _fetchOnce(PhotoItem item,
      {CancellationToken? token}) async {
    _checkNotDisposed();
    token?.throwIfCancelled();
    final first = await _fetchAttempt(item, token: token);
    if (first.isOk || first.failureOrNull is NotFound) return first;
    return _fetchAttempt(item, token: token);
  }

  /// One complete download attempt. The bytes are written to
  /// `<target>.part` and renamed to the final name only after the whole stream
  /// was read. On any failure the connection is dropped (unless cancelled) and
  /// the partial file is deleted.
  Future<Result<File>> _fetchAttempt(PhotoItem item,
      {CancellationToken? token}) async {
    final connectResult = await _ensureConnected(const Duration(seconds: 8));
    if (connectResult.isErr) {
      return Result.err(connectResult.failureOrNull!);
    }
    final connect = connectResult.valueOrNull!;

    final dir = _cacheDirectory ?? Directory.systemTemp;
    final localFile = File(
      '${dir.path}${Platform.pathSeparator}smb_${id}_${item.id.replaceAll('/', '_')}',
    );
    final partFile = File('${localFile.path}.part');
    IOSink? sink;

    // Every network step has a timeout: on a dead socket the library never
    // answers, and a call without one would hold the preparation queue forever.
    try {
      final remoteFile =
          await connect.file(_fullPath(item.id)).timeout(_stepTimeout);
      if (!remoteFile.isExists) {
        return Result.err(NotFound('SMB file no longer exists: "${item.id}"'));
      }
      await localFile.parent.create(recursive: true);

      sink = partFile.openWrite();
      final stream = await connect.openRead(remoteFile).timeout(_stepTimeout);
      var written = 0;
      await for (final chunk in stream.timeout(_stepTimeout)) {
        token?.throwIfCancelled();
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (written < remoteFile.size) {
        // The stream ended early without an error: treat it as a failed read.
        _dropBrokenConnection(connect);
        await _discardPartial(null, partFile);
        return Result.err(NetworkError(
            'Foto "${item.id}" wurde unvollständig geladen'));
      }

      await partFile.rename(localFile.path);
      return Result.ok(localFile);
    } on CancelledException {
      await _discardPartial(sink, partFile);
      rethrow;
    } on TimeoutException {
      await _discardPartial(sink, partFile);
      _dropBrokenConnection(connect);
      return Result.err(
          Timeout('Foto "${item.id}" konnte nicht rechtzeitig geladen werden'));
    } catch (e) {
      // A failed read leaves the socket in an unknown state. Drop it, so the
      // next attempt connects again instead of failing on the same socket.
      await _discardPartial(sink, partFile);
      _dropBrokenConnection(connect);
      return Result.err(NetworkError(
          'Foto "${item.id}" konnte nicht geladen werden',
          cause: e));
    }
  }

  /// Closes [sink] (if still open) and deletes [partFile]. Errors are ignored:
  /// this runs on failure paths where the original error is what matters.
  static Future<void> _discardPartial(IOSink? sink, File partFile) async {
    if (sink != null) {
      try {
        await sink.close();
      } catch (_) {}
    }
    try {
      if (await partFile.exists()) await partFile.delete();
    } catch (_) {}
  }

  /// Closes [connect] and forgets it, but only if it is still the current
  /// connection (a newer one may already have replaced it).
  void _dropBrokenConnection(SmbConnect connect) {
    if (!identical(_connect, connect)) return;
    _dropConnection();
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
