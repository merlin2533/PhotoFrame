import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A crash-safe event trace for field debugging.
///
/// When the Flutter engine crashes natively (for example a SIGSEGV on the
/// `io.worker` thread), neither the developer log nor the in-app log buffer
/// survives. This trace therefore writes every event synchronously to
/// `<ApplicationSupport>/debug_trace.log` before the next step runs, so the
/// last seconds before a crash are still on disk afterwards.
///
/// The trace is active only in debug builds (`kDebugMode`) or when the app is
/// built with `--dart-define=DEBUG_TRACE=true`. In release builds every call
/// returns at once and nothing is written.
///
/// Rules for callers: short messages only, no file contents, no secrets, no
/// user names and no host names. File names are fine.
class DebugTrace {
  DebugTrace._();

  /// Name of the trace file inside the application support directory.
  static const fileName = 'debug_trace.log';

  /// At app start the file is cut down to its last [maxLines] lines.
  static const maxLines = 3000;

  static const bool _environmentFlag = bool.fromEnvironment('DEBUG_TRACE');

  /// `true` when events are written at all.
  static bool get isActive => kDebugMode || _environmentFlag;

  /// The trace file, set by [startup]. Events are dropped until it is known.
  static File? _file;

  /// Prepares the trace for this run: resolves the file in the application
  /// support directory and keeps only its last [maxLines] lines.
  ///
  /// Meant to be called once from `main`, without `await`, so it never delays
  /// `runApp`. [directory] is only for tests. Never throws.
  static Future<void> startup({
    Future<Directory> Function()? directory,
  }) async {
    if (!isActive) return;
    try {
      final dir = await (directory ?? getApplicationSupportDirectory)();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      _file = file;
      _truncate(file);
    } catch (_) {
      // The trace is a debugging aid; a missing directory must not matter.
    }
  }

  /// Number of lines kept in memory by [event], also in release builds.
  static const memoryLines = 200;

  /// The last [memoryLines] events, kept raw in memory whether or not the
  /// file is written. Formatted only by [recentLines], so release builds pay
  /// for one small object per call.
  static final List<_TraceEntry> _memory = <_TraceEntry>[];

  /// Appends one line `<ISO time> <tag> <message>` to the trace file and keeps
  /// the raw event in memory for [recentLines].
  ///
  /// The file write is synchronous and flushed, so the line is on disk when
  /// this returns. Never throws: any failure is ignored.
  static void event(String tag, String message) {
    final entry = _TraceEntry(DateTime.now(), tag, message);
    _memory.add(entry);
    if (_memory.length > memoryLines) _memory.removeAt(0);
    if (!isActive) return;
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        '${entry.format()}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Never let tracing break the app.
    }
  }

  /// The last [max] trace lines, oldest first, for a crash report.
  ///
  /// In debug builds these are the last lines of the trace file, read from its
  /// end. In release builds, or when the file cannot be read, they are the
  /// in-memory events of [event]. Never throws.
  static List<String> recentLines(int max) {
    if (max <= 0) return const [];
    final file = _file;
    if (isActive && file != null) {
      try {
        return _readTail(file, max);
      } catch (_) {
        // Fall through to the in-memory events.
      }
    }
    final start = _memory.length > max ? _memory.length - max : 0;
    return [for (final entry in _memory.sublist(start)) entry.format()];
  }

  /// The last [max] lines of [file]. Reads backwards from the end in growing
  /// windows, so a long trace file is never loaded as a whole.
  static List<String> _readTail(File file, int max) {
    final raf = file.openSync();
    try {
      final length = raf.lengthSync();
      var window = 16 * 1024;
      while (true) {
        final start = length > window ? length - window : 0;
        raf.setPositionSync(start);
        final text = utf8.decode(
          raf.readSync(length - start),
          allowMalformed: true,
        );
        final lines = text.split('\n');
        if (lines.last.isEmpty) lines.removeLast();
        // Unless the window starts at the file start, its first piece is a
        // partial line.
        if (start == 0 || lines.length > max + 1) {
          final complete = start == 0 ? lines : lines.sublist(1);
          return complete.sublist(
            complete.length > max ? complete.length - max : 0,
          );
        }
        window *= 2;
      }
    } finally {
      raf.closeSync();
    }
  }

  /// Last path segment of [path], for logging without the folder names.
  /// Accepts both `/` and `\` as separators. Never throws.
  static String baseName(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Size of [file] in bytes for logging: `0` when [file] is `null`, `-1`
  /// when it cannot be read. Does no I/O when tracing is off. Never throws.
  static int fileLength(File? file) {
    if (!isActive) return 0;
    if (file == null) return 0;
    try {
      return file.lengthSync();
    } catch (_) {
      return -1;
    }
  }

  /// Keeps only the last [maxLines] lines of [file]. Synchronous, so no event
  /// can be written in the middle of the rewrite. Never throws.
  static void _truncate(File file) {
    try {
      if (!file.existsSync()) return;
      final lines = file.readAsLinesSync();
      if (lines.length <= maxLines) return;
      final kept = lines.sublist(lines.length - maxLines);
      file.writeAsStringSync('${kept.join('\n')}\n');
    } catch (_) {
      // Keep the old content if the file cannot be rewritten.
    }
  }
}

/// One traced event, kept raw until a line is needed.
class _TraceEntry {
  const _TraceEntry(this.time, this.tag, this.message);

  final DateTime time;
  final String tag;
  final String message;

  /// `<ISO time> <tag> <message>` on one line: line breaks become spaces.
  String format() {
    final text = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return '${time.toIso8601String()} $tag $text';
  }
}
