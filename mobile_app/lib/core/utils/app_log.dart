import 'dart:developer' as developer;

import '../observability/error_reporter.dart';
import 'app_log_buffer.dart';

/// Logs an error that the app recovers from on purpose (a corrupt cache file,
/// a source that cannot be crawled, a photo that cannot be scaled).
///
/// Such errors used to be swallowed silently, which made field problems
/// impossible to diagnose. Every call does three things:
///  - records a short entry (time, level, message, error type and text, no
///    stack trace) in [appLogBuffer], shown in the settings log screen,
///  - writes to the developer log (DevTools, `adb logcat`),
///  - reports to GlitchTip via [captureRecoveredError] (a no-op while error
///    reporting is switched off, see `error_reporter.dart`).
///
/// None of this reaches the UI.
void logRecoverableError(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  appLogBuffer.add(AppLogEntry(
    time: DateTime.now(),
    level: error != null ? AppLogLevel.error : AppLogLevel.warning,
    message: message,
    errorText: AppLogEntry.describeError(error),
  ));
  developer.log(
    message,
    name: 'PhotoFrame',
    level: 900,
    error: error,
    stackTrace: stackTrace,
  );
  captureRecoveredError(message, error: error, stackTrace: stackTrace);
}
