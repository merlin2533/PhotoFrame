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

  test('baseName() strips folders for both separators', () {
    expect(DebugTrace.baseName('/a/b/photo.jpg'), 'photo.jpg');
    expect(DebugTrace.baseName(r'C:\a\b\photo.jpg'), 'photo.jpg');
    expect(DebugTrace.baseName('photo.jpg'), 'photo.jpg');
  });
}
