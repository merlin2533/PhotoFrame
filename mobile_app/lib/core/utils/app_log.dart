import 'dart:developer' as developer;

/// Logs an error that the app recovers from on purpose (a corrupt cache file,
/// a source that cannot be crawled, a photo that cannot be scaled).
///
/// Such errors used to be swallowed silently, which made field problems
/// impossible to diagnose. The message goes to the developer log (DevTools,
/// `adb logcat`) and never reaches the UI.
void logRecoverableError(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  developer.log(
    message,
    name: 'PhotoFrame',
    level: 900,
    error: error,
    stackTrace: stackTrace,
  );
}
