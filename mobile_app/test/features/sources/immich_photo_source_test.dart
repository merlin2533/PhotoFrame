import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mobile_app/core/errors/failure.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/private_host.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/immich/immich_config_form_model.dart';
import 'package:mobile_app/features/sources/immich/immich_photo_source.dart';
import 'package:test/test.dart';

/// Hand-written [HttpClientAdapter] serving canned responses keyed by
/// "METHOD path" (query string excluded), mirroring the pattern used in
/// `test/services/weather/weather_client_test.dart`. No real network calls.
/// A `Uint8List` body is served as raw bytes, anything else as JSON.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _CannedResponse> responses = {};
  final List<RequestOptions> requests = [];

  void when(String method, String path,
      {required int statusCode, Object? body}) {
    responses['$method $path'] = _CannedResponse(statusCode, body);
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${options.path}';
    final canned = responses[key];
    if (canned == null) {
      throw StateError('No canned response registered for $key');
    }
    final body = canned.body;
    if (body is Uint8List) {
      return ResponseBody.fromBytes(body, canned.statusCode);
    }
    final payload = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(
      payload,
      canned.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _CannedResponse {
  _CannedResponse(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}

const String _base = 'https://immich.test';

ImmichPhotoSource _source({
  required _FakeAdapter adapter,
  String albumId = '',
  String albumName = '',
  Directory? cacheDirectory,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ImmichPhotoSource(
    id: 'src-1',
    config: ImmichSourceConfig(
      serverUrl: _base,
      apiKey: 'secret',
      albumId: albumId,
      albumName: albumName,
    ),
    cacheDirectory: cacheDirectory,
    dio: dio,
  );
}

void main() {
  certificateHostTests();
  group('ImmichPhotoSource connection', () {
    test('testConnection reports server version and album count', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/server/about',
            statusCode: 200, body: {'version': 'v1.120.0'})
        ..when('GET', '$_base/api/albums', statusCode: 200, body: []);
      final source = _source(adapter: adapter);

      final result = await source.testConnection();

      final status = result.valueOrNull;
      expect(status, isNotNull);
      expect(status!.reachable, isTrue);
      expect(status.detail, contains('v1.120.0'));
      expect(status.detail, contains('0 Alben'));
    });

    test('testConnection maps a rejected API key to AuthError', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/server/about',
            statusCode: 200, body: {'version': 'v1.120.0'})
        ..when('GET', '$_base/api/albums', statusCode: 401, body: {});
      final source = _source(adapter: adapter);

      final result = await source.testConnection();

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<AuthError>());
    });

    test('every request carries the x-api-key header', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/server/about',
            statusCode: 200, body: {'version': 'v1'})
        ..when('GET', '$_base/api/albums', statusCode: 200, body: []);
      final source = _source(adapter: adapter);

      await source.testConnection();

      expect(adapter.requests, isNotEmpty);
      for (final request in adapter.requests) {
        expect(request.headers['x-api-key'], 'secret');
      }
    });
  });

  group('ImmichPhotoSource folders', () {
    test('listFolders yields one folder per album', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/albums', statusCode: 200, body: [
          {'id': 'album-1', 'albumName': 'Urlaub'},
          {'id': 'album-2', 'albumName': 'Familie'},
        ]);
      final source = _source(adapter: adapter);

      final folders = await source.listFolders().toList();

      final ok = folders.map((r) => r.valueOrNull!).toList();
      expect(ok.map((f) => f.id), ['album-1', 'album-2']);
      expect(ok.map((f) => f.name), ['Urlaub', 'Familie']);
    });

    test('an album-scoped source yields only its album, without a request',
        () async {
      final adapter = _FakeAdapter();
      final source = _source(
        adapter: adapter,
        albumId: 'album-2',
        albumName: 'Familie',
      );

      final folders = await source.listFolders().toList();

      expect(folders, hasLength(1));
      expect(folders.single.valueOrNull?.id, 'album-2');
      expect(folders.single.valueOrNull?.name, 'Familie');
      expect(adapter.requests, isEmpty);
    });

    test('listFolders below a folder yields nothing (albums are flat)',
        () async {
      final adapter = _FakeAdapter();
      final source = _source(adapter: adapter);
      const album = PhotoFolder(id: 'album-1', name: 'Urlaub', path: 'album-1');

      final folders = await source.listFolders(parent: album).toList();

      expect(folders, isEmpty);
      expect(adapter.requests, isEmpty);
    });
  });

  group('ImmichPhotoSource images', () {
    test('listImages keeps only IMAGE assets and maps their metadata',
        () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/albums/album-1', statusCode: 200, body: {
          'id': 'album-1',
          'albumName': 'Urlaub',
          'assets': [
            {
              'id': 'asset-1',
              'type': 'IMAGE',
              'originalFileName': 'IMG_1.jpg',
              'fileCreatedAt': '2025-07-01T10:00:00.000Z',
              'exifInfo': {
                'exifImageWidth': 4032,
                'exifImageHeight': 3024,
                'fileSizeInByte': 1234,
              },
            },
            {
              'id': 'asset-2',
              'type': 'VIDEO',
              'originalFileName': 'clip.mp4',
            },
          ],
        });
      final source = _source(adapter: adapter);
      const album = PhotoFolder(id: 'album-1', name: 'Urlaub', path: 'album-1');

      final items = await source.listImages(album).toList();

      expect(items, hasLength(1));
      final item = items.single.valueOrNull!;
      expect(item.id, 'asset-1');
      expect(item.sourceId, 'src-1');
      expect(item.folderId, 'album-1');
      expect(item.name, 'IMG_1.jpg');
      expect(item.width, 4032);
      expect(item.height, 3024);
      expect(item.size, 1234);
      expect(item.takenAt, DateTime.utc(2025, 7, 1, 10));
    });

    test('listImages on the empty root folder yields nothing and makes no request',
        () async {
      final adapter = _FakeAdapter();
      final source = _source(adapter: adapter);
      const root = PhotoFolder(id: '', name: '', path: '');

      final items = await source.listImages(root, recursive: false).toList();

      expect(items, isEmpty);
      expect(adapter.requests, isEmpty);
    });

    test('listImages reports a missing album as NotFound', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/albums/gone', statusCode: 404, body: {});
      final source = _source(adapter: adapter);
      const album = PhotoFolder(id: 'gone', name: 'Weg', path: 'gone');

      final results = await source.listImages(album).toList();

      expect(results.single.isErr, isTrue);
      expect(results.single.failureOrNull, isA<NotFound>());
    });
  });

  group('ImmichPhotoSource fetchToCache', () {
    late Directory cacheDir;

    setUp(() {
      cacheDir = Directory.systemTemp.createTempSync('immich_test_');
    });

    tearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    final item = PhotoItem(
      id: 'asset-1',
      sourceId: 'src-1',
      folderId: 'album-1',
      name: 'IMG_1.jpg',
      mediaType: MediaType.image,
      size: 0,
      mtime: DateTime(2025),
    );

    test('downloads the preview into the cache directory', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/assets/asset-1/thumbnail',
            statusCode: 200, body: Uint8List.fromList([1, 2, 3]));
      final source = _source(adapter: adapter, cacheDirectory: cacheDir);

      final result = await source.fetchToCache(item);

      final file = result.valueOrNull!;
      expect(file.path.startsWith(cacheDir.path), isTrue);
      expect(file.uri.pathSegments.last, startsWith('immich_src-1_asset-1'));
      expect(file.readAsBytesSync(), [1, 2, 3]);
    });

    test('falls back to the original when the preview fails', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/assets/asset-1/thumbnail',
            statusCode: 500, body: null)
        ..when('GET', '$_base/api/assets/asset-1/original',
            statusCode: 200, body: Uint8List.fromList([9, 8, 7]));
      final source = _source(adapter: adapter, cacheDirectory: cacheDir);

      final result = await source.fetchToCache(item);

      expect(result.valueOrNull!.readAsBytesSync(), [9, 8, 7]);
    });

    test('returns the cached file without requesting it again', () async {
      final adapter = _FakeAdapter()
        ..when('GET', '$_base/api/assets/asset-1/thumbnail',
            statusCode: 200, body: Uint8List.fromList([1]));
      final source = _source(adapter: adapter, cacheDirectory: cacheDir);

      await source.fetchToCache(item);
      final second = await source.fetchToCache(item);

      expect(second.isOk, isTrue);
      expect(adapter.requests, hasLength(1));
    });

    test('an already cancelled token aborts before any request', () async {
      final adapter = _FakeAdapter();
      final source = _source(adapter: adapter, cacheDirectory: cacheDir);
      final cancellation = CancellationTokenSource()..cancel();

      await expectLater(
        source.fetchToCache(item, token: cancellation.token),
        throwsA(isA<CancelledException>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('ImmichConfigFormModel', () {
    test('https server to a public host is valid', () {
      const model = ImmichConfigFormModel(
        serverUrl: 'https://immich.example.com',
        apiKey: 'k',
      );
      expect(model.isValid, isTrue);
    });

    test('plain http to a public host is rejected', () {
      const model = ImmichConfigFormModel(
        serverUrl: 'http://immich.example.com',
        apiKey: 'k',
      );
      expect(model.validate(), containsPair('serverUrl', isNotEmpty));
    });

    test('plain http to a LAN address is allowed', () {
      const model = ImmichConfigFormModel(
        serverUrl: 'http://192.168.1.20:2283',
        apiKey: 'k',
      );
      expect(model.validate().containsKey('serverUrl'), isFalse);
    });

    test('a pasted /api suffix is stripped on normalization', () {
      const model = ImmichConfigFormModel(
        serverUrl: ' https://immich.example.com/api/ ',
        apiKey: ' k ',
      );
      final normalized = model.normalized();
      expect(normalized.serverUrl, 'https://immich.example.com');
      expect(normalized.apiKey, 'k');
    });

    test('missing API key is invalid', () {
      const model = ImmichConfigFormModel(
        serverUrl: 'https://immich.example.com',
      );
      expect(model.validate(), containsPair('apiKey', isNotEmpty));
    });
  });

  group('ImmichSourceConfig', () {
    test('toJson never contains the API key', () {
      const config = ImmichSourceConfig(
        serverUrl: _base,
        apiKey: 'secret',
        albumId: 'album-1',
        albumName: 'Urlaub',
      );
      final json = config.toJson();
      expect(json.values, isNot(contains('secret')));

      final restored =
          ImmichSourceConfig.fromJson(json, password: 'secret');
      expect(restored.serverUrl, _base);
      expect(restored.albumId, 'album-1');
      expect(restored.albumName, 'Urlaub');
      expect(restored.apiKey, 'secret');
    });
  });
}

void certificateHostTests() {
  group('isPrivateHost', () {
    test('accepts local network hosts', () {
      for (final h in [
        'localhost',
        'nas.local',
        '192.168.1.5',
        '10.0.0.2',
        '172.16.3.4',
        '127.0.0.1',
      ]) {
        expect(isPrivateHost(h), isTrue, reason: h);
      }
    });
    test('rejects public hosts', () {
      for (final h in ['immich.example.com', '8.8.8.8', '172.32.0.1']) {
        expect(isPrivateHost(h), isFalse, reason: h);
      }
    });
  });
}
