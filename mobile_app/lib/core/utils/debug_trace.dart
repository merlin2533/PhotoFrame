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

  /// Appends one line `<ISO time> <tag> <message>` to the trace file.
  ///
  /// The write is synchronous and flushed, so the line is on disk when this
  /// returns. Never throws: any failure is ignored.
  static void event(String tag, String message) {
    if (!isActive) return;
    final file = _file;
    if (file == null) return;
    try {
      final text = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $tag $text\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Never let tracing break the app.
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
