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
  test('existingFileNames lists the name that fileNameFor gives a copy',
      () async {
    final base = await Directory.systemTemp.createTemp('small_names_test_');
    addTearDown(() => base.delete(recursive: true));
    final live = Directory(
        '${base.path}${Platform.pathSeparator}${SmallPhotoCache.liveDirectoryName}');

    final cache = SmallPhotoCache(directory: () async => live);
    final item = _item('photo1');
    final file = await cache.fileFor(item);
    await file.writeAsBytes([1, 2, 3]);

    expect(await cache.existingFileNames(),
        {SmallPhotoCache.fileNameFor(item)});
  });
}
