import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' hide Timeout;
import 'package:mobile_app/core/errors/failure.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/smb/smb_photo_source.dart';
import 'package:mocktail/mocktail.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:smb_connect/src/connect/smb_transport.dart';

class _MockSmbConnect extends Mock implements SmbConnect {}

class _MockSmbFile extends Mock implements SmbFile {}

class _MockTransport extends Mock implements SmbTransport {}

const _root = PhotoFolder(id: '', name: '', path: '');
const _config = SmbSourceConfig(host: 'nas', share: 'Photos');

/// A fake connection whose transport close can be observed. The folder
/// listing is empty unless a test overrides [listFiles] or [file].
class _Fake {
  _Fake() {
    when(() => connect.transport).thenReturn(transport);
    when(() => transport.close()).thenAnswer((_) async {});
    when(() => connect.file(any())).thenAnswer((_) async => folder);
    when(() => connect.listFiles(any())).thenAnswer((_) async => <SmbFile>[]);
  }

  final connect = _MockSmbConnect();
  final transport = _MockTransport();
  final folder = _MockSmbFile();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_MockSmbFile());
  });

  group('SmbPhotoSource connection handling', () {
    test('concurrent callers share one in-flight connect', () async {
      final fake = _Fake();
      final gate = Completer<SmbConnect>();
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        connector: (_) {
          connectCount++;
          return gate.future;
        },
      );

      final first = source.listImages(_root).toList();
      final second = source.listImages(_root).toList();
      gate.complete(fake.connect);
      final results = await Future.wait([first, second]);

      expect(connectCount, 1);
      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
      await source.dispose();
    });

    test('a connection older than the max age is closed before reconnecting',
        () async {
      final first = _Fake();
      final second = _Fake();
      var now = DateTime(2026, 1, 1, 12);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        clock: () => now,
        connector: (_) async {
          connectCount++;
          return connectCount == 1 ? first.connect : second.connect;
        },
      );

      await source.listImages(_root).toList();
      now = now.add(const Duration(seconds: 61));
      await source.listImages(_root).toList();

      expect(connectCount, 2);
      verify(() => first.transport.close()).called(1);
      verifyNever(() => second.transport.close());
      await source.dispose();
    });

    test('a connect that finishes after its timeout is closed, not leaked',
        () async {
      final fake = _Fake();
      final gate = Completer<SmbConnect>();
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        connector: (_) => gate.future,
        stepTimeout: const Duration(milliseconds: 20),
      );

      final results = await source.listImages(_root).toList();
      expect(results.single.failureOrNull, isA<Timeout>());

      gate.complete(fake.connect);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => fake.transport.close()).called(1);
      await source.dispose();
    });
  });

  group('SmbPhotoSource crawl timeouts', () {
    test(
        'a hanging directory listing yields a Timeout and drops the connection',
        () async {
      final fake = _Fake();
      final hang = Completer<SmbFile>();
      when(() => fake.connect.file(any())).thenAnswer((_) => hang.future);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        stepTimeout: const Duration(milliseconds: 20),
        connector: (_) async {
          connectCount++;
          return fake.connect;
        },
      );

      final results = await source.listImages(_root).toList();

      expect(results, hasLength(1));
      expect(results.single.failureOrNull, isA<Timeout>());
      verify(() => fake.transport.close()).called(1);

      // The next crawl must reconnect instead of reusing the dead socket.
      when(() => fake.connect.file(any())).thenAnswer((_) async => fake.folder);
      await source.listImages(_root).toList();
      expect(connectCount, 2);
      await source.dispose();
    });

    test('a listing error yields a NetworkError and drops the connection',
        () async {
      final fake = _Fake();
      when(() => fake.connect.listFiles(any()))
          .thenThrow(StateError('socket reset'));
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        connector: (_) async => fake.connect,
      );

      final results = await source.listFolders().toList();

      expect(results, hasLength(1));
      expect(results.single.failureOrNull, isA<NetworkError>());
      verify(() => fake.transport.close()).called(1);
      await source.dispose();
    });

    test('a hanging folder listing in folder enumeration also times out',
        () async {
      final fake = _Fake();
      when(() => fake.connect.listFiles(any()))
          .thenAnswer((_) => Completer<List<SmbFile>>().future);
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        stepTimeout: const Duration(milliseconds: 20),
        connector: (_) async => fake.connect,
      );

      final results = await source.listFolders().toList();

      expect(results.single.failureOrNull, isA<Timeout>());
      verify(() => fake.transport.close()).called(1);
      await source.dispose();
    });
  });

  group('SmbPhotoSource downloads', () {
    final item = PhotoItem(
      id: 'Holiday/a.jpg',
      sourceId: 'smb1',
      folderId: 'Holiday',
      name: 'a.jpg',
      mediaType: MediaType.image,
      size: 4,
      mtime: DateTime(2026),
    );

    late Directory cache;
    late File finalFile;
    late File partFile;

    setUp(() {
      cache = Directory.systemTemp.createTempSync('smb_fetch_test');
      finalFile = File('${cache.path}${Platform.pathSeparator}'
          'smb_smb1_Holiday_a.jpg');
      partFile = File('${finalFile.path}.part');
    });

    tearDown(() {
      cache.deleteSync(recursive: true);
    });

    /// Makes [fake] serve [bytes] in full.
    void serveFile(_Fake fake, List<int> bytes) {
      when(() => fake.folder.isExists).thenReturn(true);
      when(() => fake.folder.size).thenReturn(bytes.length);
      when(() => fake.connect.openRead(any()))
          .thenAnswer((_) async => Stream.value(Uint8List.fromList(bytes)));
    }

    /// Makes [fake] report [size] bytes but deliver only the first two, then
    /// fail, like a connection that drops in the middle of a download.
    void failMidway(_Fake fake, {required int size}) {
      when(() => fake.folder.isExists).thenReturn(true);
      when(() => fake.folder.size).thenReturn(size);
      when(() => fake.connect.openRead(any()))
          .thenAnswer((_) async => _twoBytesThenError());
    }

    /// Makes [fake] report 8 bytes but end the stream after 4 without error.
    void serveShort(_Fake fake) {
      when(() => fake.folder.isExists).thenReturn(true);
      when(() => fake.folder.size).thenReturn(8);
      when(() => fake.connect.openRead(any())).thenAnswer(
          (_) async => Stream.value(Uint8List.fromList([1, 2, 3, 4])));
    }

    test('a connection older than 10 s is replaced by the next download',
        () async {
      final first = _Fake();
      final second = _Fake();
      serveFile(first, [1, 2, 3, 4]);
      serveFile(second, [1, 2, 3, 4]);
      var now = DateTime(2026, 1, 1, 12);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        cacheDirectory: cache,
        clock: () => now,
        connector: (_) async {
          connectCount++;
          return connectCount == 1 ? first.connect : second.connect;
        },
      );

      await source.fetchToCache(item);
      now = now.add(const Duration(seconds: 9));
      await source.fetchToCache(item);
      expect(connectCount, 1, reason: '9 s old connection is still reused');

      now = now.add(const Duration(seconds: 1));
      await source.fetchToCache(item);
      expect(connectCount, 2, reason: '10 s old connection is replaced');
      verify(() => first.transport.close()).called(1);
      verifyNever(() => second.transport.close());
      await source.dispose();
    });

    test('a failing first attempt is retried once and succeeds', () async {
      final broken = _Fake();
      final healthy = _Fake();
      failMidway(broken, size: 4);
      serveFile(healthy, [1, 2, 3, 4]);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        cacheDirectory: cache,
        connector: (_) async {
          connectCount++;
          return connectCount == 1 ? broken.connect : healthy.connect;
        },
      );

      final result = await source.fetchToCache(item);

      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull?.path, finalFile.path);
      expect(connectCount, 2);
      verify(() => broken.transport.close()).called(1);
      expect(await finalFile.readAsBytes(), [1, 2, 3, 4]);
      expect(await partFile.exists(), isFalse);
      await source.dispose();
    });

    test('a short read on the first attempt is retried once', () async {
      final short = _Fake();
      final healthy = _Fake();
      serveShort(short);
      serveFile(healthy, [1, 2, 3, 4]);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        cacheDirectory: cache,
        connector: (_) async {
          connectCount++;
          return connectCount == 1 ? short.connect : healthy.connect;
        },
      );

      final result = await source.fetchToCache(item);

      expect(result.failureOrNull, isNull);
      expect(connectCount, 2);
      expect(await finalFile.readAsBytes(), [1, 2, 3, 4]);
      await source.dispose();
    });

    test(
        'a failure on both attempts returns an error and leaves no partial file',
        () async {
      final first = _Fake();
      final second = _Fake();
      failMidway(first, size: 4);
      failMidway(second, size: 4);
      var connectCount = 0;
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        cacheDirectory: cache,
        connector: (_) async {
          connectCount++;
          return connectCount == 1 ? first.connect : second.connect;
        },
      );

      final result = await source.fetchToCache(item);

      expect(result.failureOrNull, isA<NetworkError>());
      expect(connectCount, 2);
      verify(() => first.transport.close()).called(1);
      verify(() => second.transport.close()).called(1);
      expect(await partFile.exists(), isFalse);
      expect(await finalFile.exists(), isFalse);
      await source.dispose();
    });

    test('a short read on both attempts returns an error and no file',
        () async {
      final first = _Fake();
      final second = _Fake();
      serveShort(first);
      serveShort(second);
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        cacheDirectory: cache,
        connector: (_) async => first.connect,
      );

      final result = await source.fetchToCache(item);

      expect(result.failureOrNull, isA<NetworkError>());
      expect(await partFile.exists(), isFalse);
      expect(await finalFile.exists(), isFalse);
      await source.dispose();
    });

    test('a completed download is renamed from .part to the final name',
        () async {
      final fake = _Fake();
      serveFile(fake, [9, 8, 7, 6]);
      final source = SmbPhotoSource(
        id: 'smb1',
        config: _config,
        cacheDirectory: cache,
        connector: (_) async => fake.connect,
      );

      final result = await source.fetchToCache(item);

      expect(result.valueOrNull?.path, finalFile.path);
      expect(await finalFile.readAsBytes(), [9, 8, 7, 6]);
      expect(await partFile.exists(), isFalse);
      await source.dispose();
    });
  });
}

/// Emits two bytes and then fails, like a connection that drops mid-read.
Stream<Uint8List> _twoBytesThenError() async* {
  yield Uint8List.fromList([1, 2]);
  throw StateError('socket reset');
}
