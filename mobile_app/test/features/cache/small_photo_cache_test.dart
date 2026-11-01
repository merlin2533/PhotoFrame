import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/sources/domain/media_type.dart';
import 'package:mobile_app/features/sources/domain/photo_item.dart';

Future<File> _solidPng(Directory dir, String name, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 32, 32),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(32, 32);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

Future<File> _twoTonePng(
    Directory dir, String name, ui.Color left, ui.Color right) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 16, 32), ui.Paint()..color = left);
  canvas.drawRect(
      const ui.Rect.fromLTWH(16, 0, 16, 32), ui.Paint()..color = right);
  final image = await recorder.endRecording().toImage(32, 32);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('small_photo_cache_test_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets('similar colours are accepted, a purple cast is rejected',
      (tester) async {
    await tester.runAsync(() async {
      final orange = await _solidPng(dir, 'a.png', const ui.Color(0xFFC87828));
      final almost = await _solidPng(dir, 'b.png', const ui.Color(0xFFC47A2C));
      final purple = await _solidPng(dir, 'c.png', const ui.Color(0xFF9040C0));
      expect(await SmallPhotoCache.looksLikeOriginal(orange, almost), isTrue);
      expect(await SmallPhotoCache.looksLikeOriginal(orange, purple), isFalse);
    });
  });

  testWidgets('damage in one part of the picture is rejected', (tester) async {
    await tester.runAsync(() async {
      const green = ui.Color(0xFF30A030);
      const garbled = ui.Color(0xFFE040E0);
      final good = await _twoTonePng(dir, 'g.png', green, green);
      final left = await _twoTonePng(dir, 'l.png', garbled, green);
      final same = await _twoTonePng(dir, 's.png', green, green);
      expect(await SmallPhotoCache.looksLikeOriginal(good, same), isTrue);
      expect(await SmallPhotoCache.looksLikeOriginal(good, left), isFalse);
    });
  });

  testWidgets('an undecodable scaled file is rejected', (tester) async {
    await tester.runAsync(() async {
      final orange = await _solidPng(dir, 'a.png', const ui.Color(0xFFC87828));
      final broken = File('${dir.path}${Platform.pathSeparator}x.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      expect(await SmallPhotoCache.looksLikeOriginal(orange, broken), isFalse);
    });
  });

  test('looksComplete detects truncated JPEG and short downloads', () async {
    File write(String name, List<int> bytes) =>
        File('${dir.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(bytes);
    final whole = write('ok.jpg', [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
    final cut = write('cut.jpg', [0xFF, 0xD8, 1, 2, 3, 4, 5]);
    final padded = write('pad.jpg', [0xFF, 0xD8, 1, 0xFF, 0xD9, 0, 0, 0]);
    expect(await SmallPhotoCache.looksComplete(whole, 7), isTrue);
    expect(await SmallPhotoCache.looksComplete(cut, 7), isFalse);
    expect(await SmallPhotoCache.looksComplete(padded, 8), isTrue);
    // The original reported more bytes than arrived.
    expect(
      await SmallPhotoCache.looksComplete(whole, 100, downloadIsOriginal: true),
      isFalse,
    );
    // The size is ignored for a preview (the source reports the original).
    expect(await SmallPhotoCache.looksComplete(whole, 100), isTrue);
    expect(await SmallPhotoCache.looksComplete(write('e.jpg', []), 0), isFalse);
  });

  test('looksComplete accepts a JPEG with appended data and rejects a cut one',
      () async {
    File write(String name, List<int> bytes) =>
        File('${dir.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(bytes);
    // SOI, a JFIF APP0 segment and EOI: the smallest JPEG structure with an
    // end marker.
    const jpeg = [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, 0x11, 0x22, 0xFF, 0xD9,
    ];
    // A motion photo: a video follows the EOI. The 200 KiB appended contain no
    // 0xFF byte, so the search has to walk through several chunks.
    final motionPhoto = [
      ...jpeg,
      for (var i = 0; i < 200 * 1024; i++) (i * 7) & 0x7F,
    ];
    expect(
      await SmallPhotoCache.looksComplete(write('motion.jpg', motionPhoto), 0),
      isTrue,
    );
    // Cut off before the EOI, with no marker in the 200 KiB that follow.
    final cutLong = [
      ...jpeg.sublist(0, 10),
      for (var i = 0; i < 200 * 1024; i++) (i * 7) & 0x7F,
    ];
    expect(
      await SmallPhotoCache.looksComplete(write('cut_long.jpg', cutLong), 0),
      isFalse,
    );
    expect(
      await SmallPhotoCache.looksComplete(
        write('cut_short.jpg', jpeg.sublist(0, 10)),
        0,
      ),
      isFalse,
    );
    // An end marker split across the 64 KiB chunk border is still found.
    final split = List<int>.filled(128 * 1024, 0)
      ..[0] = 0xFF
      ..[1] = 0xD8
      ..[64 * 1024 - 1] = 0xFF
      ..[64 * 1024] = 0xD9;
    expect(
      await SmallPhotoCache.looksComplete(write('split.jpg', split), 0),
      isTrue,
    );
  });

  test('onlyPreparedPhotos defaults to true and survives JSON', () {
    expect(const AppSettings().onlyPreparedPhotos, isTrue);
    final off = AppSettings.fromJson(
        const AppSettings().copyWith(onlyPreparedPhotos: false).toJson());
    expect(off.onlyPreparedPhotos, isFalse);
  });

  testWidgets('verifiedExisting returns intact files and deletes damaged ones',
      (tester) async {
    await tester.runAsync(() async {
      final cache = SmallPhotoCache(directory: () async => dir);
      PhotoItem item(String id) => PhotoItem(
            id: id,
            sourceId: 's',
            folderId: 'f',
            name: id,
            mediaType: MediaType.image,
            size: 1,
            mtime: DateTime(2024),
          );
      final good = item('good.jpg');
      final bad = item('bad.jpg');
      final png = await _solidPng(dir, 'tmp.png', const ui.Color(0xFF30A030));
      await png.copy((await cache.fileFor(good)).path);
      // Starts like a JPEG but is cut off.
      await (await cache.fileFor(bad))
          .writeAsBytes([0xFF, 0xD8, 1, 2, 3, 4, 5, 6, 7, 8]);

      expect(await cache.verifiedExisting(good), isNotNull);
      expect(await cache.verifiedExisting(bad), isNull);
      expect(await (await cache.fileFor(bad)).exists(), isFalse);
    });
  });

  test('clear removes the prepared copies', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    File('${dir.path}${Platform.pathSeparator}one.jpg').writeAsBytesSync([1]);
    await cache.clear();
    expect(await dir.exists(), isFalse);
  });

  test('batch size defaults to 5 and survives a JSON round trip', () {
    expect(const AppSettings().smallPhotoBatchSize, 5);
    final back = AppSettings.fromJson(
        const AppSettings().copyWith(smallPhotoBatchSize: 12).toJson());
    expect(back.smallPhotoBatchSize, 12);
  });
}
