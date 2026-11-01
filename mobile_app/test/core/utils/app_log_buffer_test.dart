import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/app_log.dart';
import 'package:mobile_app/core/utils/app_log_buffer.dart';

AppLogEntry _entry(String message, {AppLogLevel? level, String? errorText}) {
  return AppLogEntry(
    time: DateTime(2026, 11, 1, 12, 30, 5),
    level: level ?? AppLogLevel.warning,
    message: message,
    errorText: errorText,
  );
}

void main() {
  group('AppLogBuffer', () {
    test('keeps only the newest [capacity] entries', () {
      final buffer = AppLogBuffer(capacity: 3);
      for (var i = 1; i <= 5; i++) {
        buffer.add(_entry('m$i'));
      }

      expect(buffer.length, 3);
      expect(buffer.entries.map((e) => e.message), ['m3', 'm4', 'm5']);
    });

    test('default capacity is 300 entries', () {
      final buffer = AppLogBuffer();
      expect(buffer.capacity, AppLogBuffer.defaultCapacity);
      expect(AppLogBuffer.defaultCapacity, 300);

      for (var i = 0; i < 301; i++) {
        buffer.add(_entry('m$i'));
      }
      expect(buffer.length, 300);
      expect(buffer.entries.first.message, 'm1');
      expect(buffer.entries.last.message, 'm300');
    });

    test('entries are ordered oldest first, newestFirst reverses them', () {
      final buffer = AppLogBuffer(capacity: 10);
      buffer.add(_entry('first'));
      buffer.add(_entry('second'));
      buffer.add(_entry('third'));

      expect(
          buffer.entries.map((e) => e.message), ['first', 'second', 'third']);
      expect(buffer.newestFirst.map((e) => e.message),
          ['third', 'second', 'first']);
    });

    test('returned lists are unmodifiable snapshots', () {
      final buffer = AppLogBuffer(capacity: 10)..add(_entry('a'));
      final snapshot = buffer.newestFirst;

      expect(() => snapshot.add(_entry('b')), throwsUnsupportedError);
      buffer.add(_entry('c'));
      expect(snapshot.length, 1);
    });

    test('notifies listeners on add and on clear', () {
      final buffer = AppLogBuffer(capacity: 10);
      var notifications = 0;
      buffer.addListener(() => notifications++);

      buffer.add(_entry('a'));
      buffer.clear();
      expect(notifications, 2);
      expect(buffer.isEmpty, isTrue);
    });

    test('clear on an empty buffer does not notify', () {
      final buffer = AppLogBuffer(capacity: 10);
      var notifications = 0;
      buffer.addListener(() => notifications++);

      buffer.clear();
      expect(notifications, 0);
    });

    test('rejects a non-positive capacity', () {
      expect(() => AppLogBuffer(capacity: 0), throwsAssertionError);
    });
  });

  group('AppLogEntry', () {
    test('describeError returns null without an error', () {
      expect(AppLogEntry.describeError(null), isNull);
    });

    test('describeError holds the runtime type and message', () {
      expect(AppLogEntry.describeError(const FormatException('kaputt')),
          'FormatException: kaputt');
    });

    test('describeError truncates very long texts', () {
      final long = 'x' * 1000;
      final text = AppLogEntry.describeError(long)!;

      expect(text.length, AppLogEntry.maxErrorTextLength + 1);
      expect(text.endsWith('…'), isTrue);
    });

    test('toLine renders time, level, message and error text', () {
      final entry = _entry(
        'Quelle nicht lesbar',
        level: AppLogLevel.error,
        errorText: 'StateError: leer',
      );

      expect(entry.toLine(),
          '01.11.2026 12:30:05 [Fehler] Quelle nicht lesbar - StateError: leer');
    });

    test('formatAppLogEntriesAsText writes one line per entry', () {
      final text = formatAppLogEntriesAsText([
        _entry('neu'),
        _entry('alt'),
      ]);

      expect(text.split('\n').length, 2);
      expect(text, contains('[Hinweis] neu'));
      expect(text, contains('[Hinweis] alt'));
    });
  });

  group('logRecoverableError', () {
    setUp(appLogBuffer.clear);

    test('records the message and a short error text into the buffer', () {
      logRecoverableError(
        'Foto kann nicht skaliert werden',
        error: const FormatException('defekt'),
        stackTrace: StackTrace.current,
      );

      final entry = appLogBuffer.newestFirst.single;
      expect(entry.message, 'Foto kann nicht skaliert werden');
      expect(entry.level, AppLogLevel.error);
      expect(entry.errorText, 'FormatException: defekt');
    });

    test('an entry without error has warning level and no error text', () {
      logRecoverableError('Quelle übersprungen');

      final entry = appLogBuffer.newestFirst.single;
      expect(entry.level, AppLogLevel.warning);
      expect(entry.errorText, isNull);
    });
  });
}
