import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';

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
