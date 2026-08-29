import 'dart:io';

import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:test/test.dart';

void main() {
  group('MockPhotoSource', () {
    late Directory tempDir;
    late MockPhotoSource source;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mock_photo_source_test_');
      source = MockPhotoSource(
        id: 'test-source',
        displayName: 'Test Source',
        folderCount: 2,
        itemsPerFolder: 3,
        cacheDirectory: tempDir,
        simulatedDelay: Duration.zero,
      );
    });

    tearDown(() async {
      await source.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('testConnection reports reachable', () async {
      final result = await source.testConnection();
      expect(result.isOk, isTrue);
      final status = (result as Ok<ConnectionStatus>).value;
      expect(status.reachable, isTrue);
    });

    test('listFolders yields the expected number of root folders', () async {
      final folders = <PhotoFolder>[];
      await for (final result in source.listFolders()) {
        expect(result.isOk, isTrue);
        folders.add((result as Ok<PhotoFolder>).value);
      }
      expect(folders, hasLength(2));
      expect(folders.map((f) => f.id), containsAll(['folder-0', 'folder-1']));
    });

    test('listImages yields the expected items for a folder', () async {
      const folder = PhotoFolder(id: 'folder-0', name: 'Mock Folder 0', path: '/mock/folder-0');

      final items = <String>[];
      await for (final result in source.listImages(folder)) {
        expect(result.isOk, isTrue);
        final item = result.valueOrNull!;
        expect(item.sourceId, 'test-source');
        expect(item.folderId, 'folder-0');
        expect(item.mediaType, MediaType.image);
        items.add(item.id);
      }
      expect(items, hasLength(3));
      expect(items, containsAll(['folder-0-item-0', 'folder-0-item-1', 'folder-0-item-2']));
    });

    test('listImages on an unknown folder yields a NotFound failure', () async {
      const unknownFolder = PhotoFolder(id: 'nope', name: 'Nope', path: '/nope');
      final results = await source.listImages(unknownFolder).toList();
      expect(results, hasLength(1));
      expect(results.single.isErr, isTrue);
    });

    test('fetchToCache returns a readable file for a known item', () async {
      const folder = PhotoFolder(id: 'folder-0', name: 'Mock Folder 0', path: '/mock/folder-0');
      final firstItemResult = await source.listImages(folder).first;
      final item = firstItemResult.valueOrNull!;

      final fetchResult = await source.fetchToCache(item);
      expect(fetchResult.isOk, isTrue);
      final file = (fetchResult as Ok<File>).value;
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));
    });

    test('changes stream never emits for the mock source', () async {
      final emitted = <void>[];
      final sub = source.changes.listen(emitted.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(emitted, isEmpty);
    });
  });
}
