import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
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

PhotoItem _item(String id) => PhotoItem(
      id: id,
      sourceId: 's',
      folderId: 'f',
      name: id,
      mediaType: MediaType.image,
      size: 1,
      mtime: DateTime(2024),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('small_photo_queue_test_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('queued jobs run one at a time, in arrival order', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final gate = Completer<void>();
    final log = <String>[];
    var running = 0;
    var maxRunning = 0;

    Future<void> job(String name, {Completer<void>? hold}) =>
        cache.runInQueueForTest(() async {
          running++;
          maxRunning = math.max(maxRunning, running);
          log.add('start $name');
          if (hold != null) await hold.future;
          log.add('end $name');
          running--;
        });

    final first = job('a', hold: gate);
    final second = job('b');
    final third = job('c');

    // Give the queue time to run whatever it may run: only "a" may start.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(log, ['start a']);

    gate.complete();
    await Future.wait([first, second, third]);
    expect(log, [
      'start a', 'end a', 'start b', 'end b', 'start c', 'end c', //
    ]);
    expect(maxRunning, 1);
  });

  test('a failing job releases the queue for the next one', () async {
    final cache = SmallPhotoCache(directory: () async => dir);
    final failed = cache.runInQueueForTest<void>(() async {
      throw StateError('boom');
    });
    final next = cache.runInQueueForTest(() async => 42);
    await expectLater(failed, throwsStateError);
    expect(await next, 42);
  });

  testWidgets(
      'verifiedExisting waits behind a running job, and a repeat check of a '
      'verified file does not', (tester) async {
    await tester.runAsync(() async {
      final cache = SmallPhotoCache(directory: () async => dir);
      final good = _item('good.jpg');
      final png = await _solidPng(dir, 'tmp.png', const ui.Color(0xFF30A030));
      await png.copy((await cache.fileFor(good)).path);

      // First check, with a free queue: the file is verified and stamped.
      expect(await cache.verifiedExisting(good), isNotNull);

      // Occupy the queue with a job that waits for a gate.
      final gate = Completer<void>();
      final blocker = cache.runInQueueForTest(() => gate.future);

      // Repeat check of the stamped file: answered at once, no queue needed.
      expect(await cache.verifiedExisting(good), isNotNull);

      // A file that was not verified yet must wait behind the blocker.
      final fresh = _item('fresh.jpg');
      await png.copy((await cache.fileFor(fresh)).path);
      var finished = false;
      final pending = cache.verifiedExisting(fresh).then((file) {
        finished = true;
        return file;
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(finished, isFalse);

      gate.complete();
      await blocker;
      expect(await pending, isNotNull);
      expect(finished, isTrue);
    });
  });
}
