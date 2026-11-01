import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/cancellation_token.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';

/// Hands out [file] as the download.
class _FixedDownloadSource extends MockPhotoSource {
  _FixedDownloadSource(this.file)
      : super(
          id: 'fmt',
          folderCount: 1,
          itemsPerFolder: 0,
          simulatedDelay: Duration.zero,
        );

  final File file;

  @override
  Future<Result<File>> fetchToCache(
    PhotoItem item, {
    CancellationToken? token,
  }) async =>
      Result.ok(file);
}

PhotoItem _item(String id, {MediaType type = MediaType.image}) => PhotoItem(
      id: id,
      sourceId: 'fmt',
      folderId: 'folder',
      name: id,
      mediaType: type,
      size: 16,
      mtime: DateTime(2024),
    );

/// First bytes of a HEIC file (ftyp box with the heic brand).
const _heicBytes = [
  0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, //
  0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('small_photo_format_test_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('only JPEG (FF D8 FF) and PNG (89 50 4E 47) headers are scalable', () {
    expect(SmallPhotoCache.isScalableHeader([0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
    expect(SmallPhotoCache.isScalableHeader([0x89, 0x50, 0x4E, 0x47]), isTrue);
    expect(SmallPhotoCache.isScalableHeader(_heicBytes), isFalse);
    expect(SmallPhotoCache.isScalableHeader([0xFF, 0xD8]), isFalse);
    expect(SmallPhotoCache.isScalableHeader([0x89, 0x50, 0x4E]), isFalse);
    expect(SmallPhotoCache.isScalableHeader(const []), isFalse);
  });

  test('a HEIC original is refused without scaling', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final download = File('${dir.path}/photo.heic')
      ..writeAsBytesSync(_heicBytes);
    final source = _FixedDownloadSource(download);

    await expectLater(
      cache.ensure(source, _item('photo.heic')),
      throwsA(isA<PhotoNotConvertibleException>()
          .having((e) => e.cause, 'cause', isNull)),
    );

    // The scaling queue was never entered.
    expect(cache.openConversions, 0);
    expect(cache.downloadedBytes, _heicBytes.length);
  });

  test('a video is refused without any download', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final download = File('${dir.path}/clip.mp4')..writeAsBytesSync([0, 1, 2]);
    final source = _FixedDownloadSource(download);

    await expectLater(
      cache.ensure(source, _item('clip.mp4', type: MediaType.video)),
      throwsA(isA<PhotoNotConvertibleException>()),
    );

    expect(cache.downloadedBytes, 0);
    expect(cache.openConversions, 0);
  });
}
