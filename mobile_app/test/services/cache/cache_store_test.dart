import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/cache/cache_store.dart';

void main() {
  late Directory tmp;
  late Directory root;
  late CacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cache_store_test');
    root = Directory('${tmp.path}${Platform.pathSeparator}photo_cache');
    store = CacheStore(root: () async => root);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> write(CacheArea area, String source, String key, int size,
      {String ext = 'jpg'}) async {
    final file = await store.fileFor(area, source, key, ext: ext);
    await file.writeAsBytes(List<int>.filled(size, 1));
    return file;
  }

  group('fileFor', () {
    test('returns the same deterministic path under the layout', () async {
      final a = await store.fileFor(CacheArea.downloads, 'src1', 'photo');
      final b = await store.fileFor(CacheArea.downloads, 'src1', 'photo');
      expect(a.path, b.path);
      expect(
        a.path,
        '${root.path}${Platform.pathSeparator}downloads'
        '${Platform.pathSeparator}src1${Platform.pathSeparator}photo.jpg',
      );
      expect(await a.parent.exists(), isTrue);
      expect(await a.exists(), isFalse);
    });

    test('uses the area folder name and the given extension', () async {
      final f =
          await store.fileFor(CacheArea.prepared, 'src1', 'k', ext: 'png');
      expect(
          f.path,
          contains('${Platform.pathSeparator}prepared'
              '${Platform.pathSeparator}src1${Platform.pathSeparator}k.png'));
    });

    test('rejects an extension with path characters', () {
      expect(
        store.fileFor(CacheArea.downloads, 'src1', 'k', ext: '../x'),
        throwsArgumentError,
      );
    });
  });

  group('safeName', () {
    test('keeps names that are already safe unchanged', () {
      expect(CacheStore.safeName('a_b-C9'), 'a_b-C9');
    });

    test('replaces unsafe characters and appends a hash', () {
      final name = CacheStore.safeName('a:b');
      expect(name, matches(RegExp(r'^a_b_[0-9a-f]{8}$')));
    });

    test('raw ids a:b and a_b give different folders', () async {
      final colon = await store.fileFor(CacheArea.downloads, 'a:b', 'k');
      final underscore = await store.fileFor(CacheArea.downloads, 'a_b', 'k');
      expect(colon.parent.path, isNot(underscore.parent.path));
      expect(CacheStore.safeName('a:b'), isNot(CacheStore.safeName('a_b')));
    });

    test('never produces a path separator or a dot-only segment', () {
      expect(CacheStore.safeName('../x/y'), isNot(contains('/')));
      expect(CacheStore.safeName('..'), isNot(anyOf('.', '..')));
      expect(CacheStore.safeName(''), isNotEmpty);
    });
  });

  group('existing', () {
    test('returns null for a missing file', () async {
      expect(await store.existing(CacheArea.downloads, 'src1', 'nope'), isNull);
    });

    test('returns the file once it exists', () async {
      final written = await write(CacheArea.downloads, 'src1', 'photo', 3);
      final found = await store.existing(CacheArea.downloads, 'src1', 'photo');
      expect(found?.path, written.path);
    });
  });

  group('commit', () {
    test('moves tmp to target and replaces an existing target', () async {
      final target = await write(CacheArea.prepared, 'src1', 'photo', 5);
      final tmpFile = File('${target.path}.123.tmp');
      await tmpFile.writeAsString('new');

      final result = await store.commit(tmpFile, target);

      expect(result.path, target.path);
      expect(await tmpFile.exists(), isFalse);
      expect(await result.readAsString(), 'new');
    });

    test('moves tmp to a new target', () async {
      final parent =
          (await store.fileFor(CacheArea.downloads, 's', 'x')).parent;
      final tmpFile = File('${parent.path}${Platform.pathSeparator}x.tmp');
      await tmpFile.writeAsString('data');
      final target = File('${parent.path}${Platform.pathSeparator}x.jpg');

      final result = await store.commit(tmpFile, target);

      expect(await result.readAsString(), 'data');
      expect(await tmpFile.exists(), isFalse);
    });
  });

  group('usage', () {
    test('counts per area and per source and reports unassigned folders',
        () async {
      await write(CacheArea.downloads, 's1', 'a', 10);
      await write(CacheArea.downloads, 's1', 'b', 20);
      await write(CacheArea.prepared, 's1', 'a', 5);
      await write(CacheArea.prepared, 's2', 'a', 7);
      await write(CacheArea.downloads, 'ghost', 'g', 100);

      final usage = await store.usage(['s1', 's2', 's3']);

      expect(usage.sources.map((s) => s.sourceId), ['s1', 's2', 's3']);

      final s1 = usage.sources[0];
      expect(s1.countIn(CacheArea.downloads), 2);
      expect(s1.bytesIn(CacheArea.downloads), 30);
      expect(s1.countIn(CacheArea.prepared), 1);
      expect(s1.bytesIn(CacheArea.prepared), 5);
      expect(s1.count, 3);
      expect(s1.bytes, 35);

      final s2 = usage.sources[1];
      expect(s2.count, 1);
      expect(s2.bytes, 7);
      expect(s2.countIn(CacheArea.downloads), 0);

      final s3 = usage.sources[2];
      expect(s3.count, 0);
      expect(s3.bytes, 0);

      expect(usage.unassigned.sourceId, isNull);
      expect(usage.unassigned.count, 1);
      expect(usage.unassigned.bytes, 100);

      expect(usage.totalBytes, 35 + 7 + 100);
      expect(usage.totalCount, 5);
    });

    test('is empty for a cache that does not exist yet', () async {
      final usage = await store.usage(['s1']);
      expect(usage.sources.single.count, 0);
      expect(usage.unassigned.count, 0);
      expect(usage.totalBytes, 0);
    });
  });

  group('deleteForSource', () {
    test('removes only the given source', () async {
      await write(CacheArea.downloads, 's1', 'a', 1);
      await write(CacheArea.prepared, 's1', 'a', 1);
      await write(CacheArea.downloads, 's2', 'a', 1);

      final removed = await store.deleteForSource('s1');

      expect(removed, 2);
      final usage = await store.usage(['s1', 's2']);
      expect(usage.sources[0].count, 0);
      expect(usage.sources[1].count, 1);
    });

    test('with an area removes only that area of the source', () async {
      await write(CacheArea.downloads, 's1', 'a', 1);
      await write(CacheArea.prepared, 's1', 'a', 1);

      final removed =
          await store.deleteForSource('s1', area: CacheArea.prepared);

      expect(removed, 1);
      final usage = await store.usage(['s1']);
      expect(usage.sources.single.countIn(CacheArea.downloads), 1);
      expect(usage.sources.single.countIn(CacheArea.prepared), 0);
    });
  });

  group('clear', () {
    test('clears one area and keeps the other', () async {
      await write(CacheArea.downloads, 's1', 'a', 1);
      await write(CacheArea.prepared, 's1', 'a', 1);

      await store.clear(area: CacheArea.downloads);

      final usage = await store.usage(['s1']);
      expect(usage.sources.single.countIn(CacheArea.downloads), 0);
      expect(usage.sources.single.countIn(CacheArea.prepared), 1);
    });

    test('clears all areas without an area argument', () async {
      await write(CacheArea.downloads, 's1', 'a', 1);
      await write(CacheArea.prepared, 's2', 'a', 1);

      await store.clear();

      final usage = await store.usage(['s1', 's2']);
      expect(usage.totalCount, 0);
    });
  });
}
