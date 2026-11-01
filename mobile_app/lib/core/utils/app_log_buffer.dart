import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Severity of a buffered log entry.
enum AppLogLevel {
  warning,
  error;

  /// Short German label shown in the log screen and in copied text.
  String get label => switch (this) {
        AppLogLevel.warning => 'Hinweis',
        AppLogLevel.error => 'Fehler',
      };
}

/// One recovered error or notice, as kept in [AppLogBuffer].
///
/// Deliberately holds no stack trace: the log screen and the "Kopieren"
/// action only need a short, human-readable line.
class AppLogEntry {
  AppLogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.errorText,
  });

  /// Maximum length of [errorText]; longer exception texts are cut off so a
  /// single huge exception cannot dominate the log screen.
  static const int maxErrorTextLength = 300;

  final DateTime time;
  final AppLogLevel level;
  final String message;

  /// `runtimeType` and message of the attached error, e.g.
  /// `FileSystemException: cannot open ...`. Null when no error was given.
  final String? errorText;

  /// Builds the short error text for [error] (type plus `toString()`,
  /// truncated). Returns null for a null [error].
  static String? describeError(Object? error) {
    if (error == null) return null;
    // Most exceptions already print as "Type: message", so the type is only
    // prepended when toString() does not start with it.
    final type = error.runtimeType.toString();
    final message = error.toString();
    final text = message.startsWith(type) ? message : '$type: $message';
    if (text.length <= maxErrorTextLength) return text;
    return '${text.substring(0, maxErrorTextLength)}…';
  }

  /// One-line plain-text rendering used by the "Kopieren" action.
  String toLine() {
    final buffer = StringBuffer()
      ..write(formatAppLogTime(time))
      ..write(' [')
      ..write(level.label)
      ..write('] ')
      ..write(message);
    if (errorText != null) {
      buffer
        ..write(' - ')
        ..write(errorText);
    }
    return buffer.toString();
  }
}

/// Formats [time] as `dd.MM.yyyy HH:mm:ss` (locale-independent on purpose).
String formatAppLogTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)}.${time.year} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Bounded, in-memory ring buffer of recent [AppLogEntry]s.
///
/// Nothing in here is persisted: the buffer is lost on app restart by design,
/// so that no error history accumulates on the device beyond the session.
/// When full, the oldest entry is dropped.
///
/// Extends [ChangeNotifier] so UI code (see `appLogProvider`) can rebuild on
/// new entries.
class AppLogBuffer extends ChangeNotifier {
  AppLogBuffer({this.capacity = defaultCapacity})
      : assert(capacity > 0, 'capacity must be positive');

  /// Number of entries kept when no explicit capacity is given.
  static const int defaultCapacity = 300;

  final int capacity;
  final Queue<AppLogEntry> _entries = Queue<AppLogEntry>();

  /// Number of entries currently held (at most [capacity]).
  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  /// Entries from oldest to newest.
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  /// Entries from newest to oldest, the order the log screen displays.
  List<AppLogEntry> get newestFirst =>
      List.unmodifiable(_entries.toList().reversed);

  /// Appends [entry], dropping the oldest entries beyond [capacity].
  void add(AppLogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Removes all entries.
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

/// Process-wide buffer that [logRecoverableError] writes into.
///
/// A top-level instance (rather than one owned by a Riverpod provider)
/// because [logRecoverableError] has no access to a `Ref`. Riverpod code
/// reads it through `appLogBufferProvider`, which tests can override.
final AppLogBuffer appLogBuffer = AppLogBuffer();

/// Renders [entries] (newest first, as shown on screen) as plain text, one
/// line per entry, for the clipboard.
String formatAppLogEntriesAsText(List<AppLogEntry> entries) =>
    entries.map((e) => e.toLine()).join('\n');
