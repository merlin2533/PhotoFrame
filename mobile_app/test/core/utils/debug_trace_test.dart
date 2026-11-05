import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/debug_trace.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('debug_trace_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File traceFile() => File('${tempDir.path}/${DebugTrace.fileName}');

  test('event() appends one line with time, tag and message', () async {
    await DebugTrace.startup(directory: () async => tempDir);

    DebugTrace.event('slide', 'image.file a.jpg bytes=12');
    DebugTrace.event('cache', 'ensure end b.jpg ok');

    final lines = traceFile().readAsLinesSync();
    expect(lines, hasLength(2));
    expect(
        lines[0], matches(RegExp(r'^\S+ slide image\.file a\.jpg bytes=12$')));
    expect(lines[1], endsWith(' cache ensure end b.jpg ok'));
    // The first token is an ISO 8601 time stamp.
    expect(DateTime.tryParse(lines[0].split(' ').first), isNotNull);
  });

  test('event() keeps a message with line breaks on one line', () async {
    await DebugTrace.startup(directory: () async => tempDir);

    DebugTrace.event('error', 'first\nsecond\r\nthird');

    final lines = traceFile().readAsLinesSync();
    expect(lines, hasLength(1));
    expect(lines.single, endsWith(' error first second third'));
  });

  test('startup() keeps only the last 3000 lines', () async {
    final old = [for (var i = 1; i <= 3500; i++) 'line $i'];
    traceFile().writeAsStringSync('${old.join('\n')}\n');

    await DebugTrace.startup(directory: () async => tempDir);

    final lines = traceFile().readAsLinesSync();
    expect(lines, hasLength(DebugTrace.maxLines));
    expect(lines.first, 'line 501');
    expect(lines.last, 'line 3500');
  });

  test('startup() leaves a short file unchanged', () async {
    traceFile().writeAsStringSync('one\ntwo\n');

    await DebugTrace.startup(directory: () async => tempDir);

    expect(traceFile().readAsStringSync(), 'one\ntwo\n');
  });

  test('event() never throws when the directory is missing', () async {
    final missing = Directory('${tempDir.path}/does/not/exist');

    await DebugTrace.startup(directory: () async => missing);

    expect(
      () => DebugTrace.event('slide', 'image.file a.jpg'),
      returnsNormally,
    );
    expect(missing.existsSync(), isFalse);
  });

  test('startup() never throws when the directory cannot be resolved',
      () async {
    await expectLater(
      DebugTrace.startup(
        directory: () async => throw const FileSystemException('no dir'),
      ),
      completes,
    );
    expect(() => DebugTrace.event('x', 'y'), returnsNormally);
  });

  test('recentLines() returns the last lines of the trace file', () async {
    await DebugTrace.startup(directory: () async => tempDir);

    for (var i = 1; i <= 5; i++) {
      DebugTrace.event('slide', 'step $i');
    }

    final lines = DebugTrace.recentLines(3);
    expect(lines, hasLength(3));
    expect(lines[0], endsWith(' slide step 3'));
    expect(lines[2], endsWith(' slide step 5'));
  });

  test('recentLines() reads only the tail of a large trace file', () async {
    await DebugTrace.startup(directory: () async => tempDir);
    final padding = 'x' * 120;
    final written = [for (var i = 1; i <= 2000; i++) '$padding line $i'];
    traceFile().writeAsStringSync('${written.join('\n')}\n');

    final lines = DebugTrace.recentLines(3);

    expect(lines, [
      endsWith('$padding line 1998'),
      endsWith('$padding line 1999'),
      endsWith('$padding line 2000'),
    ]);
  });

  test('recentLines() falls back to the memory lines when the file is gone',
      () async {
    final missing = Directory('${tempDir.path}/does/not/exist');
    await DebugTrace.startup(directory: () async => missing);

    DebugTrace.event('cache', 'memory one');
    DebugTrace.event('cache', 'memory two');

    final lines = DebugTrace.recentLines(2);
    expect(lines, hasLength(2));
    expect(lines.last, endsWith(' cache memory two'));
  });

  test('the memory keeps only the last 200 events', () async {
    final missing = Directory('${tempDir.path}/does/not/exist');
    await DebugTrace.startup(directory: () async => missing);

    for (var i = 1; i <= 250; i++) {
      DebugTrace.event('slide', 'event $i');
    }

    final lines = DebugTrace.recentLines(1000);
    expect(lines, hasLength(DebugTrace.memoryLines));
    expect(lines.last, endsWith(' slide event 250'));
    expect(lines.first, endsWith(' slide event 51'));
  });

  test('baseName() strips folders for both separators', () {
    expect(DebugTrace.baseName('/a/b/photo.jpg'), 'photo.jpg');
    expect(DebugTrace.baseName(r'C:\a\b\photo.jpg'), 'photo.jpg');
    expect(DebugTrace.baseName('photo.jpg'), 'photo.jpg');
  });
}
