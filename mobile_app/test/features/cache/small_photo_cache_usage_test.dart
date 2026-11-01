import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/index/media_stable_id.dart';

/// File name a photo of [sourceId] at [path] gets in the cache folder, built
/// the same way [SmallPhotoCache] builds it.
String _fileNameFor(String sourceId, String path) =>
    '${SmallPhotoCache.baseNameFor(MediaStableId.compute(sourceId: sourceId, path: path))}.jpg';

Future<void> _write(Directory dir, String name, int bytes) async {
  await File('${dir.path}${Platform.pathSeparator}$name')
      .writeAsBytes(List<int>.filled(bytes, 1));
}

void main() {
  late Directory tempDir;
  late SmallPhotoCache cache;

  // Source ids as the sources providers would return them. 'my' is a prefix
  // of 'my_nas_share' and 'mein.quelle' contains a character that is replaced
  // in file names.
  const knownIds = ['cam', 'my_nas_share', 'my', 'mein.quelle'];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('small_photo_usage_test_');
    cache = SmallPhotoCache(directory: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Writes one file per source plus files that belong to no known source.
  Future<void> writeFixture() async {
    await _write(tempDir, _fileNameFor('cam', 'a.jpg'), 100);
    await _write(tempDir, _fileNameFor('cam', 'b/c.jpg'), 200);
    await _write(tempDir, _fileNameFor('my_nas_share', 'x.jpg'), 300);
    await _write(tempDir, _fileNameFor('mein.quelle', 'y.jpg'), 50);
    await _write(tempDir, _fileNameFor('gone_src', 'z.jpg'), 70);
    await _write(tempDir, 'notes.txt', 10);
  }

  group('usage', () {
    test('counts and sizes every file, per known source', () async {
      await writeFixture();

      final usage = await cache.usage(knownIds);

      final bySource = {for (final s in usage.bySource) s.sourceId: s};
      expect(bySource['cam']!.count, 2);
      expect(bySource['cam']!.bytes, 300);
      expect(bySource['my_nas_share']!.count, 1);
      expect(bySource['my_nas_share']!.bytes, 300);
      expect(bySource['mein.quelle']!.count, 1);
      expect(bySource['mein.quelle']!.bytes, 50);
      expect(usage.bySource.map((s) => s.sourceId), knownIds);
    });

    test('a source whose id is a prefix of another id gets only its own files',
        () async {
      await writeFixture();

      final usage = await cache.usage(knownIds);

      final my = usage.bySource.firstWhere((s) => s.sourceId == 'my');
      expect(my.count, 0);
      expect(my.bytes, 0);
    });

    test('files of unknown sources and other files are summed as unassigned',
        () async {
      await writeFixture();

      final usage = await cache.usage(knownIds);

      expect(usage.unassignedCount, 2);
      expect(usage.unassignedBytes, 80);
    });

    test('totals cover the whole folder', () async {
      await writeFixture();

      final usage = await cache.usage(knownIds);

      expect(usage.count, 6);
      expect(usage.totalBytes, 100 + 200 + 300 + 50 + 70 + 10);
    });

    test('a missing cache folder counts as empty', () async {
      await tempDir.delete(recursive: true);

      final usage = await cache.usage(knownIds);

      expect(usage.count, 0);
      expect(usage.totalBytes, 0);
      expect(usage.bySource.length, knownIds.length);
    });
  });

  group('sourceIdForFile', () {
    test('maps a file to the source whose id contains underscores', () {
      final name = _fileNameFor('my_nas_share', 'x.jpg');

      expect(SmallPhotoCache.sourceIdForFile(name, knownIds), 'my_nas_share');
    });

    test('maps a file of the shorter id to that id', () {
      final name = _fileNameFor('my', 'x.jpg');

      expect(SmallPhotoCache.sourceIdForFile(name, knownIds), 'my');
    });

    test('matches ids that were sanitised in the file name', () {
      final name = _fileNameFor('mein.quelle', 'y.jpg');

      expect(name.startsWith('mein_quelle_'), isTrue);
      expect(SmallPhotoCache.sourceIdForFile(name, knownIds), 'mein.quelle');
    });

    test('returns null for a source that is not known', () {
      final name = _fileNameFor('gone_src', 'z.jpg');

      expect(SmallPhotoCache.sourceIdForFile(name, knownIds), isNull);
    });

    test('requires exactly one 16 character hash after the source id', () {
      expect(
        SmallPhotoCache.belongsToSource('cam_0123456789abcdef.jpg', 'cam'),
        isTrue,
      );
      expect(
        SmallPhotoCache.belongsToSource('cam_0123456789abcde.jpg', 'cam'),
        isFalse,
      );
      expect(
        SmallPhotoCache.belongsToSource('cam_0123456789ABCDEF.jpg', 'cam'),
        isFalse,
      );
      expect(
        SmallPhotoCache.belongsToSource('cam_my_0123456789abcdef.jpg', 'cam'),
        isFalse,
      );
    });
  });

  group('deleteForSource', () {
    test('removes only the files of that source', () async {
      await writeFixture();

      final deleted = await cache.deleteForSource('my_nas_share');

      expect(deleted, 1);
      final usage = await cache.usage(knownIds);
      final bySource = {for (final s in usage.bySource) s.sourceId: s};
      expect(bySource['my_nas_share']!.count, 0);
      expect(bySource['cam']!.count, 2);
      expect(bySource['mein.quelle']!.count, 1);
      expect(usage.unassignedCount, 2);
    });

    test('does not touch files of a source whose id it is a prefix of',
        () async {
      await writeFixture();

      final deleted = await cache.deleteForSource('my');

      expect(deleted, 0);
      final usage = await cache.usage(knownIds);
      expect(
          usage.bySource.firstWhere((s) => s.sourceId == 'my_nas_share').count,
          1);
    });

    test('deleting the files of one source returns how many were removed',
        () async {
      await writeFixture();

      expect(await cache.deleteForSource('cam'), 2);
      expect(await cache.deleteForSource('cam'), 0);
    });
  });

  group('deleteUnassigned', () {
    test('removes files that belong to no known source only', () async {
      await writeFixture();

      final deleted = await cache.deleteUnassigned(knownIds);

      expect(deleted, 2);
      final usage = await cache.usage(knownIds);
      expect(usage.unassignedCount, 0);
      expect(usage.count, 4);
    });
  });
}
