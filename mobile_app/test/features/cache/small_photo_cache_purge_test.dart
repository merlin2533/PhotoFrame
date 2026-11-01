import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';

PhotoItem _item(String id) => PhotoItem(
      id: id,
      sourceId: 'src',
      folderId: 'folder',
      name: '$id.jpg',
      mediaType: MediaType.image,
      size: 1,
      mtime: DateTime(2024),
    );

void main() {
  test('the live cache folder survives the one-time legacy purge', () async {
    final base = await Directory.systemTemp.createTemp('small_purge_test_');
    addTearDown(() => base.delete(recursive: true));

    // A prepared copy in the live folder, plus an old folder that must go.
    final live = Directory(
        '${base.path}${Platform.pathSeparator}${SmallPhotoCache.liveDirectoryName}');
    await live.create();
    final prepared = File('${live.path}${Platform.pathSeparator}kept.jpg');
    await prepared.writeAsBytes([1, 2, 3]);
    final legacy = Directory(
        '${base.path}${Platform.pathSeparator}${SmallPhotoCache.legacyDirectoryNames.first}');
    await legacy.create();

    final cache = SmallPhotoCache(directory: () async => live);
    // Any lookup goes through the folder setup, which runs the purge once.
    await cache.existing(_item('probe'));

    expect(await prepared.exists(), isTrue);
    expect(await legacy.exists(), isFalse);
  });
}
