import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;

import '../../../core/errors/failure.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/private_host.dart';
import '../../../core/utils/result.dart';
import '../domain/media_type.dart';
import '../domain/photo_folder.dart';
import '../domain/photo_item.dart';
import '../domain/photo_source.dart';
import 'immich_config_form_model.dart';

/// Resolved, non-secret-plus-key connection details for [ImmichPhotoSource].
///
/// [albumId] scopes the source to one album (one configured source per
/// selected album, mirroring how Nextcloud creates one source per folder).
/// An empty [albumId] means "all albums on the server".
class ImmichSourceConfig {
  const ImmichSourceConfig({
    required this.serverUrl,
    required this.apiKey,
    this.albumId = '',
    this.albumName = '',
  });

  /// Server base URL without trailing slash and without `/api`, e.g.
  /// `https://immich.example.com`.
  final String serverUrl;

  /// Immich API key, sent as the `x-api-key` header. Never serialized by
  /// [toJson] - it lives only in `SecureCredentialStore`.
  final String apiKey;

  /// Album this source is scoped to, or empty for all albums.
  final String albumId;

  /// Display name of [albumId], kept so the list screen can show it without
  /// a network round trip.
  final String albumName;

  /// Non-secret fields only, for persisting via `SourceDescriptor.config`.
  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'albumId': albumId,
        'albumName': albumName,
      };

  /// Rebuilds a config from its non-secret [json] plus the API key [password]
  /// loaded from `SecureCredentialStore`.
  factory ImmichSourceConfig.fromJson(Map<String, dynamic> json,
      {required String password}) {
    return ImmichSourceConfig(
      serverUrl: json['serverUrl'] as String? ?? '',
      apiKey: password,
      albumId: json['albumId'] as String? ?? '',
      albumName: json['albumName'] as String? ?? '',
    );
  }

  factory ImmichSourceConfig.fromForm(
    ImmichConfigFormModel form, {
    String albumId = '',
    String albumName = '',
  }) {
    final normalized = form.normalized();
    return ImmichSourceConfig(
      serverUrl: normalized.serverUrl,
      apiKey: normalized.apiKey,
      albumId: albumId,
      albumName: albumName,
    );
  }
}

/// Read-only [PhotoSource] backed by an Immich server (REST API, see
/// https://immich.app/docs/api). Albums are exposed as folders; photos are
/// the IMAGE assets of those albums. Videos are skipped.
///
/// Like the Nextcloud source, a self-signed certificate is accepted, since
/// self-hosted Immich instances often run with one on the LAN.
class ImmichPhotoSource implements PhotoSource {
  ImmichPhotoSource({
    required this.id,
    required ImmichSourceConfig config,
    String? displayName,
    Directory? cacheDirectory,
    Dio? dio,
  })  : _config = config,
        displayName = displayName ?? 'Immich',
        _cacheDirectory = cacheDirectory,
        _dio = dio ?? _buildDio(),
        _ownsDio = dio == null;

  @override
  final String id;

  @override
  final String displayName;

  @override
  SourceType get type => SourceType.immich;

  final ImmichSourceConfig _config;
  final Directory? _cacheDirectory;
  final Dio _dio;
  final bool _ownsDio;
  bool _disposed = false;

  /// The active configuration, exposed so `source_descriptor.dart` can turn a
  /// live instance back into a persistable [SourceDescriptor] config.
  ImmichSourceConfig get config => _config;

  String get _baseUrl => _config.serverUrl;

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 60),
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient()..badCertificateCallback = (cert, host, port) =>
              isPrivateHost(host),
    );
    return dio;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ImmichPhotoSource "$id" has already been disposed');
    }
  }

  Failure _mapError(Object e, {required String context}) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return Timeout('$context timed out', cause: e);
        case DioExceptionType.connectionError:
          return NetworkError(
              '$context: server unreachable (${e.message ?? 'connection error'})',
              cause: e);
        case DioExceptionType.badCertificate:
          return NetworkError('$context: invalid TLS certificate', cause: e);
        default:
          break;
      }
      if (status == 401 || status == 403) {
        return AuthError(
            '$context: API key rejected or missing permission (HTTP $status)',
            cause: e);
      }
      if (status == 404) {
        return NotFound('$context: not found (HTTP $status)', cause: e);
      }
      return NetworkError(
          '$context failed (HTTP ${status ?? '?'}${e.message != null ? ', ${e.message}' : ''})',
          cause: e);
    }
    if (e is TimeoutException) {
      return Timeout('$context timed out', cause: e);
    }
    return NetworkError('$context failed unexpectedly', cause: e);
  }

  /// Every request carries the API key itself (not via the Dio instance), so
  /// the key is sent regardless of how the client was constructed.
  Options _authOptions({Duration? timeout}) => Options(
        headers: {'x-api-key': _config.apiKey},
        connectTimeout: timeout,
        receiveTimeout: timeout,
      );

  Future<Response<dynamic>> _get(String path,
      {Duration? timeout, Map<String, dynamic>? query}) {
    return _dio.get<dynamic>('$_baseUrl$path',
        queryParameters: query, options: _authOptions(timeout: timeout));
  }

  Future<Map<String, dynamic>> _getMap(String path,
      {Duration? timeout}) async {
    final response = await _get(path, timeout: timeout);
    final data = response.data;
    if (data is! Map) {
      throw FormatException('Unexpected JSON object response from $path');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<List<dynamic>> _getList(String path, {Duration? timeout}) async {
    final response = await _get(path, timeout: timeout);
    final data = response.data;
    if (data is! List) {
      throw FormatException('Unexpected JSON array response from $path');
    }
    return data;
  }

  static Map<String, dynamic> _asMap(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  PhotoFolder get _scopedFolder => PhotoFolder(
        id: _config.albumId,
        name: _config.albumName.isEmpty ? _config.albumId : _config.albumName,
        path: _config.albumId,
      );

  @override
  Future<Result<ConnectionStatus>> testConnection({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _checkNotDisposed();
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Reachability and server version.
      final about = await _getMap('/api/server/about', timeout: timeout);
      // 2. Key check: the authenticated album list fails with 401 on a bad key.
      final albums = await _getList('/api/albums', timeout: timeout);
      stopwatch.stop();
      final version = about['version'] as String?;
      return Result.ok(
        ConnectionStatus(
          reachable: true,
          latency: stopwatch.elapsed,
          detail:
              'Immich${version != null ? ' $version' : ''}, ${albums.length} Alben',
        ),
      );
    } catch (e) {
      return Result.err(_mapError(e, context: 'Immich connection test'));
    }
  }

  @override
  Stream<Result<PhotoFolder>> listFolders({
    PhotoFolder? parent,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    // Albums are flat (no sub-albums), so there is nothing below a folder.
    if (parent != null) return;
    token?.throwIfCancelled();

    if (_config.albumId.isNotEmpty) {
      yield Result.ok(_scopedFolder);
      return;
    }

    try {
      final albums = await _getList('/api/albums');
      for (final entry in albums) {
        token?.throwIfCancelled();
        final album = _asMap(entry);
        final albumId = album['id'] as String? ?? '';
        if (albumId.isEmpty) continue;
        final name = album['albumName'] as String? ?? '';
        yield Result.ok(
          PhotoFolder(
            id: albumId,
            name: name.isEmpty ? albumId : name,
            path: albumId,
          ),
        );
      }
    } on CancelledException {
      rethrow;
    } catch (e) {
      yield Result.err(_mapError(e, context: 'Listing Immich albums'));
    }
  }

  @override
  Stream<Result<PhotoItem>> listImages(
    PhotoFolder folder, {
    bool recursive = true,
    CancellationToken? token,
  }) async* {
    _checkNotDisposed();
    token?.throwIfCancelled();
    // The indexer and slideshow probe every source with the empty root
    // folder first. Immich has no root album, so that probe yields nothing.
    if (folder.id.isEmpty) return;

    try {
      final album = await _getMap(
          '/api/albums/${Uri.encodeComponent(folder.id)}');
      final assets = album['assets'];
      if (assets is! List) return;
      for (final entry in assets) {
        token?.throwIfCancelled();
        final item = _itemFromAsset(_asMap(entry), folder.id);
        if (item != null) yield Result.ok(item);
      }
    } on CancelledException {
      rethrow;
    } catch (e) {
      yield Result.err(
          _mapError(e, context: 'Listing Immich album "${folder.name}"'));
    }
  }

  PhotoItem? _itemFromAsset(Map<String, dynamic> asset, String albumId) {
    final assetId = asset['id'] as String? ?? '';
    if (assetId.isEmpty) return null;
    // Only still images are offered; videos are not played.
    if (asset['type'] != 'IMAGE') return null;

    final exif = _asMap(asset['exifInfo']);
    final takenAt =
        _parseDate(asset['fileCreatedAt']) ?? _parseDate(asset['localDateTime']);
    final mtime = _parseDate(asset['fileModifiedAt']) ??
        takenAt ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return PhotoItem(
      id: assetId,
      sourceId: id,
      folderId: albumId,
      name: asset['originalFileName'] as String? ?? assetId,
      mediaType: MediaType.image,
      size: _asInt(exif['fileSizeInByte']) ?? 0,
      mtime: mtime,
      width: _asInt(exif['exifImageWidth']),
      height: _asInt(exif['exifImageHeight']),
      takenAt: takenAt,
    );
  }

  /// Downloads [path] to [destination] via a `.part` file that is renamed
  /// only once complete, so a cached file is never half-written.
  Future<void> _download(
    String path,
    File destination,
    CancellationToken? token, {
    Map<String, dynamic>? query,
  }) async {
    final temp = File('${destination.path}.part');
    final cancel = CancelToken();
    try {
      await _dio.download(
        '$_baseUrl$path',
        temp.path,
        queryParameters: query,
        options: _authOptions(),
        cancelToken: cancel,
        onReceiveProgress: (received, total) {
          if (token?.isCancelled ?? false) cancel.cancel('cancelled');
        },
      );
      token?.throwIfCancelled();
      await temp.rename(destination.path);
    } catch (e) {
      if (await temp.exists()) await temp.delete();
      if (e is DioException && e.type == DioExceptionType.cancel) {
        throw const CancelledException();
      }
      rethrow;
    }
  }

  /// Fetches the ~1440px preview JPEG, which is what the frame needs; falls
  /// back to the original file if the server cannot produce a preview.
  @override
  Future<Result<File>> fetchToCache(PhotoItem item,
      {CancellationToken? token}) async {
    _checkNotDisposed();
    token?.throwIfCancelled();
    try {
      final dir = _cacheDirectory ?? Directory.systemTemp;
      final localFile = File(
        '${dir.path}${Platform.pathSeparator}immich_${id}_${item.id}.jpg',
      );
      await localFile.parent.create(recursive: true);
      if (await localFile.exists()) return Result.ok(localFile);

      try {
        await _download(
          '/api/assets/${Uri.encodeComponent(item.id)}/thumbnail',
          localFile,
          token,
          query: {'size': 'preview'},
        );
      } on CancelledException {
        rethrow;
      } catch (_) {
        await _download(
          '/api/assets/${Uri.encodeComponent(item.id)}/original',
          localFile,
          token,
        );
      }
      token?.throwIfCancelled();
      return Result.ok(localFile);
    } on CancelledException {
      rethrow;
    } catch (e) {
      return Result.err(
          _mapError(e, context: 'Fetching Immich photo "${item.name}"'));
    }
  }

  /// Immich has no push notification this app consumes - see the honesty
  /// note on [PhotoSource.changes]. Change detection happens by polling.
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> dispose() async {
    _disposed = true;
    if (_ownsDio) _dio.close(force: true);
  }
}
