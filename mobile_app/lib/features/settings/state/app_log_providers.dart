import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_log_buffer.dart';

/// The app's log buffer. Defaults to the process-wide [appLogBuffer] that
/// `logRecoverableError` writes into. Tests override it with a fresh buffer.
final Provider<AppLogBuffer> appLogBufferProvider =
    Provider<AppLogBuffer>((ref) => appLogBuffer);

/// Current log entries, newest first. Rebuilds whenever the buffer changes
/// (a new entry, or a clear).
final NotifierProvider<AppLogEntriesNotifier, List<AppLogEntry>>
    appLogEntriesProvider =
    NotifierProvider<AppLogEntriesNotifier, List<AppLogEntry>>(
  AppLogEntriesNotifier.new,
);

/// Mirrors [AppLogBuffer] into Riverpod state by listening to its change
/// notifications. The listener is removed when the provider is disposed.
class AppLogEntriesNotifier extends Notifier<List<AppLogEntry>> {
  @override
  List<AppLogEntry> build() {
    final buffer = ref.watch(appLogBufferProvider);
    void sync() => state = buffer.newestFirst;

    buffer.addListener(sync);
    ref.onDispose(() => buffer.removeListener(sync));
    return buffer.newestFirst;
  }

  /// Empties the buffer. The listener then updates [state].
  void clear() => ref.read(appLogBufferProvider).clear();
}
