import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/app_log_buffer.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/local/local_folder_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';

/// Hands out [file] as the download and counts the fetches.
class _FixedDownloadSource extends MockPhotoSource {
  _FixedDownloadSource(this.file)
      : super(
          id: 'dl',
          folderCount: 1,
          itemsPerFolder: 0,
          simulatedDelay: Duration.zero,
        );

  final File file;
  int fetches = 0;

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async {
    fetches++;
    return Result.ok(file);
  }
}

PhotoItem _item(String sourceId, String id) => PhotoItem(
      id: id,
      sourceId: sourceId,
      folderId: 'folder',
      name: id,
      mediaType: MediaType.image,
      size: 5,
      mtime: DateTime(2024),
    );

/// Five bytes that start like a JPEG but never end: the download is not
/// complete, so [SmallPhotoCache.ensure] fetches it twice and gives up.
const _truncatedJpeg = [0xFF, 0xD8, 1, 2, 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('small_photo_bytes_test_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a cache hit adds no downloaded bytes', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final item = _item('dl', 'hit');
    final small = await cache.fileFor(item);
    await small.writeAsBytes([1, 2, 3, 4]);
    final download = File('${dir.path}/unused.jpg')
      ..writeAsBytesSync(_truncatedJpeg);
    final source = _FixedDownloadSource(download);

    final result = await cache.ensure(source, item);

    expect(result?.path, small.path);
    expect(source.fetches, 0);
    expect(cache.downloadedBytes, 0);
    expect(cache.openConversions, 0);
  });

  test('every download adds the size of the file it returns', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final item = _item('dl', 'broken');
    final download = File('${dir.path}/broken.jpg')
      ..writeAsBytesSync(_truncatedJpeg);
    final source = _FixedDownloadSource(download);

    // Both fetches are counted, even though the copy is discarded.
    expect(await cache.ensure(source, item), isNull);

    expect(source.fetches, 2);
    expect(cache.downloadedBytes, 2 * _truncatedJpeg.length);
  });

  test('a local folder source, which returns the original, adds nothing',
      () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final original = File('${dir.path}/local.jpg')
      ..writeAsBytesSync(_truncatedJpeg);
    final source = LocalFolderSource(id: 'local', rootPath: dir.path);
    final item = _item('local', 'local.jpg');

    expect(await cache.ensure(source, item), isNull);

    expect(original.existsSync(), isTrue);
    expect(cache.downloadedBytes, 0);
  });

  group('a download that is not an image', () {
    File tempFile(List<int> bytes) {
      // Directly in the system temp directory, where the downloads of network
      // sources are stored and where ensure() may delete them.
      final name = 'photoframe_undecodable_${DateTime.now().microsecondsSinceEpoch}.jpg';
      return File('${Directory.systemTemp.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(bytes);
    }

    for (final entry in <String, List<int>>{
      'text': 'this is not a picture at all'.codeUnits,
      // Has JPEG markers, so the completeness check passes, but holds no image.
      'JPEG markers only': [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9],
    }.entries) {
      testWidgets('(${entry.key}) returns null, logs a plain message and is '
          'deleted from the temp directory', (tester) async {
        await tester.runAsync(() async {
          final cache = SmallPhotoCache(directory: () async => dir);
          final item = _item('dl', 'junk-${entry.key.hashCode}');
          final download = tempFile(entry.value);
          final source = _FixedDownloadSource(download);

          // No exception escapes: the photo is simply "could not be prepared".
          expect(await cache.ensure(source, item), isNull);

          expect(download.existsSync(), isFalse,
              reason: 'the broken temp download must be removed');
          final logged = appLogBuffer.entries.where(
            (e) => e.message == 'Photo is not a decodable image',
          );
          expect(logged, isNotEmpty);
          expect(logged.last.errorText, isNotNull);
          expect(
            await cache.fileFor(item).then((f) => f.existsSync()),
            isFalse,
            reason: 'no small file may be left behind',
          );
        });
      });
    }

    testWidgets('a local original that is not an image is never deleted',
        (tester) async {
      await tester.runAsync(() async {
        final cache = SmallPhotoCache(directory: () async => dir);
        final item = _item('dl', 'original');
        // Not in the temp directory: the local original must stay.
        final original = File('${dir.path}/original.jpg')
          ..writeAsBytesSync('not an image'.codeUnits);
        final source = _FixedDownloadSource(original);

        expect(await cache.ensure(source, item), isNull);

        expect(original.existsSync(), isTrue);
      });
    });
  });
}
