import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';

/// Returns a complete JPEG as the download and writes a 100 byte file as
/// the scaled copy, so [SmallPhotoCache.ensure] runs its whole write path.
class _ScalingCache extends SmallPhotoCache {
  _ScalingCache({
    required super.directory,
    super.freeSpace,
  });

  @override
  Future<File?> scaleCopy(File full, File temp) async {
    await temp.writeAsBytes(List<int>.filled(100, 2));
    return temp;
  }
}

class _JpegSource extends MockPhotoSource {
  _JpegSource(this.download)
      : super(
          id: 'dl',
          folderCount: 1,
          itemsPerFolder: 0,
          simulatedDelay: Duration.zero,
        );

  final File download;

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async =>
      Result.ok(download);
}

PhotoItem _item(String id) => PhotoItem(
      id: id,
      sourceId: 'dl',
      folderId: 'folder',
      name: id,
      mediaType: MediaType.image,
      size: 5,
      mtime: DateTime(2024),
    );

/// Writes a [bytes] file named [name] in [dir] that was last modified [age]
/// before now.
Future<File> _copy(Directory dir, String name, int bytes, Duration age) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(List<int>.filled(bytes, 1));
  await file.setLastModified(DateTime.now().subtract(age));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory cacheDir;
  late File download;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('small_photo_limit_test_');
    cacheDir = Directory('${root.path}/small')..createSync();
    // The download lives outside the cache folder so it is not counted.
    final downloadDir = Directory('${root.path}/download')..createSync();
    download = File('${downloadDir.path}/photo.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 0xFF, 0xD9]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('removes the oldest copies until the new copy fits under the limit',
      () async {
    final oldest =
        await _copy(cacheDir, 'a.jpg', 300, const Duration(hours: 4));
    final second =
        await _copy(cacheDir, 'b.jpg', 300, const Duration(hours: 3));
    final third = await _copy(cacheDir, 'c.jpg', 300, const Duration(hours: 2));
    final newest =
        await _copy(cacheDir, 'd.jpg', 200, const Duration(hours: 1));
    final cache = _ScalingCache(directory: () async => cacheDir);
    final item = _item('photo.jpg');

    // 1100 bytes on disk, limit 1000, new copy 100 bytes: the room for the
    // others is 900, so only the oldest copy has to go.
    final result = await cache.ensure(
      _JpegSource(download),
      item,
      cacheLimitBytes: 1000,
    );

    expect(result, isNotNull);
    expect(oldest.existsSync(), isFalse);
    expect(second.existsSync(), isTrue);
    expect(third.existsSync(), isTrue);
    expect(newest.existsSync(), isTrue);
    final usage = await cache.usage(['dl']);
    expect(usage.totalBytes, lessThanOrEqualTo(1000));
  });

  test(
      'keeps copies modified within 60 seconds and stops when only those are left',
      () async {
    final recent =
        await _copy(cacheDir, 'recent.jpg', 950, const Duration(seconds: 10));
    final cache = _ScalingCache(directory: () async => cacheDir);

    // 950 bytes of recent copies plus the 100 byte copy exceed the limit of
    // 1000, and the recent copy may not be removed.
    await expectLater(
      cache.ensure(
        _JpegSource(download),
        _item('photo.jpg'),
        cacheLimitBytes: 1000,
      ),
      throwsA(isA<CacheLimitReachedException>()),
    );

    expect(recent.existsSync(), isTrue);
    expect(cache.takeEvictedNames(), isEmpty);
    expect(await cache.fileFor(_item('photo.jpg')).then((f) => f.existsSync()),
        isFalse);
  });

  test('without evictToFit a full cache throws before the download and keeps '
      'every copy', () async {
    final old = await _copy(cacheDir, 'old.jpg', 1000, const Duration(hours: 4));
    final cache = _ScalingCache(directory: () async => cacheDir);
    final source = _JpegSource(download);

    await expectLater(
      cache.ensure(
        source,
        _item('photo.jpg'),
        cacheLimitBytes: 1000,
        evictToFit: false,
      ),
      throwsA(isA<CacheLimitReachedException>()),
    );

    expect(old.existsSync(), isTrue);
    expect(cache.takeEvictedNames(), isEmpty);
    expect(cache.downloadedBytes, 0);
  });

  test('without evictToFit a copy is still written while there is room',
      () async {
    final old = await _copy(cacheDir, 'old.jpg', 300, const Duration(hours: 4));
    final cache = _ScalingCache(directory: () async => cacheDir);

    final result = await cache.ensure(
      _JpegSource(download),
      _item('photo.jpg'),
      cacheLimitBytes: 1000,
      evictToFit: false,
    );

    expect(result, isNotNull);
    expect(old.existsSync(), isTrue);
  });

  test('writes no copy when the free space is below the floor', () async {
    final old = await _copy(cacheDir, 'old.jpg', 300, const Duration(hours: 4));
    final cache = _ScalingCache(
      directory: () async => cacheDir,
      freeSpace: () async => minFreeStorageBytes - 1,
    );
    final item = _item('photo.jpg');

    final result = await cache.ensure(
      _JpegSource(download),
      item,
      cacheLimitBytes: 1000,
    );

    expect(result, isNull);
    expect(await (await cache.fileFor(item)).exists(), isFalse);
    expect(old.existsSync(), isTrue);
  });
}
