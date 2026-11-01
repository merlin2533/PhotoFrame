import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Client DSN of the GlitchTip project that receives error reports.
///
/// A client DSN only allows submitting events to that one project. It is
/// not a secret and may live in the app. Keep it in this constant only.
const String kGlitchTipDsn =
    'https://6b8923f59fd5466895ec7db6f167af79@glitchtip.resqio.io/12';

/// Replacement text for every piece of information removed before sending.
const String kRedactedText = '[redacted]';

/// Runtime switch for error reporting, driven by the persisted
/// `AppSettings.sendErrorReports` value (settings screen, "Fehlerberichte
/// senden"). Defaults to on, matching the setting's default.
///
/// While `false`, [redactSentryEvent] drops every event and the capture
/// helpers below do nothing, so no data leaves the device.
bool _errorReportingEnabled = true;

bool get isErrorReportingEnabled => _errorReportingEnabled;

void setErrorReportingEnabled(bool enabled) {
  _errorReportingEnabled = enabled;
}

// --- Scrubbing ------------------------------------------------------------

/// Patterns for data that must never leave the device, in application
/// order. Each match is replaced by [kRedactedText].
///
/// Order matters: URLs and e-mail addresses go first so their host and path
/// parts are removed as a whole before the more generic host and path rules
/// run over what is left.
final List<RegExp> _scrubPatterns = [
  // Any URL with a scheme: http(s), file, content (Android SAF URIs carry
  // file names), smb, webdav, and so on. Covers the source hosts too.
  RegExp(r'''\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s'"<>]+'''),
  // E-mail addresses.
  RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
  // Windows drive paths (C:\Users\...) and UNC paths (\\server\share\...).
  RegExp(r'''\b[A-Za-z]:\\[^\s'"<>]*'''),
  RegExp(r'''\\\\[^\s'"<>]+'''),
  // POSIX absolute paths (/storage/emulated/0/...). The lookbehind keeps
  // "and/or"-style text and things like "1/2" untouched.
  RegExp(r'''(?<![\w:])/[^\s'"<>]+'''),
  // Photo and video file names without a directory part.
  RegExp(
    r'''[^\s'"<>/\\]+\.(?:jpe?g|png|heic|heif|webp|gif|bmp|tiff?|dng|raw|cr2|nef|arw|mp4|mov|m4v|3gp|avi|mkv|webm)\b''',
    caseSensitive: false,
  ),
  // IPv4 addresses (NAS and router addresses).
  RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
  // Hostnames such as `nas.local` or `cloud.example.org`. Dotted names
  // whose last label is a common source-code or data file extension are
  // skipped, so that stack frames like `main.dart` stay readable.
  RegExp(
    r'''\b(?:[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\.)+'''
    r'''(?!(?:dart|kt|java|js|ts|json|yaml|yml|xml|gradle|md|txt|html|css|'''
    r'''lock|so|dylib|arb|plist|swift|m|h|c|cc|cpp|py|sh|log)\b)'''
    r'''[a-z]{2,24}\b''',
    caseSensitive: false,
  ),
  // Bare localhost (with optional port).
  RegExp(r'\blocalhost(?::\d+)?\b', caseSensitive: false),
];

/// Replaces every piece of data that must not leave the device in [input]
/// with [kRedactedText]: URLs (any scheme), e-mail addresses, Windows and
/// POSIX file paths, photo and video file names, IPv4 addresses, hostnames
/// and localhost.
///
/// Pure function, used by [redactSentryEvent] on every string of an event.
String scrubSensitiveText(String input) {
  var output = input;
  for (final pattern in _scrubPatterns) {
    output = output.replaceAll(pattern, kRedactedText);
  }
  return output;
}

/// Recursively scrubs strings inside [value] (maps, lists and plain strings).
/// Other values, such as numbers, booleans and null, are returned unchanged.
dynamic _scrubValue(dynamic value) {
  if (value is String) return scrubSensitiveText(value);
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key, _scrubValue(item)),
    );
  }
  if (value is List) return value.map(_scrubValue).toList();
  return value;
}

// --- Sentry configuration ---------------------------------------------------

/// Applies the app's reporting policy to Sentry [options]. Called from
/// `SentryFlutter.init` in `main.dart`.
///
/// - No default PII (no IP address, no user identity).
/// - No performance tracing (`tracesSampleRate` 0, auto tracing off).
/// - `release` in release builds, `debug` otherwise.
/// - Every event passes through [redactSentryEvent] before it is sent.
void configureErrorReporting(SentryFlutterOptions options) {
  options.dsn = kGlitchTipDsn;
  options.environment = kDebugMode ? 'debug' : 'release';
  options.sendDefaultPii = false;
  options.tracesSampleRate = 0;
  options.enableAutoPerformanceTracing = false;
  options.beforeSend = redactSentryEvent;
}

/// Sentry `beforeSend` hook: drops the event while reporting is switched
/// off, and otherwise removes breadcrumbs, user, request and host details
/// and scrubs every remaining string with [scrubSensitiveText].
FutureOr<SentryEvent?> redactSentryEvent(SentryEvent event, Hint hint) {
  if (!_errorReportingEnabled) return null;

  event
    ..breadcrumbs = null
    ..user = null
    ..request = null
    ..serverName = null
    ..culprit = scrubNullable(event.culprit)
    ..transaction = scrubNullable(event.transaction);
  event.contexts.device?.name = null;

  final message = event.message;
  if (message != null) {
    event.message = SentryMessage(
      scrubSensitiveText(message.formatted),
      template: scrubNullable(message.template),
      params: message.params?.map(_scrubValue).toList(),
    );
  }

  final tags = event.tags;
  if (tags != null) {
    event.tags =
        tags.map((key, value) => MapEntry(key, scrubSensitiveText(value)));
  }

  // `extra` is deprecated in favour of contexts, but the SDK may still fill
  // it, so it is scrubbed here as well. The lint is silenced on purpose.
  // ignore: deprecated_member_use
  final extra = event.extra;
  if (extra != null) {
    // ignore: deprecated_member_use
    event.extra = {
      for (final entry in extra.entries) entry.key: _scrubValue(entry.value),
    };
  }

  final recovered = event.contexts['recovered'];
  if (recovered != null) {
    event.contexts['recovered'] = _scrubValue(recovered);
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    exception
      ..value = scrubNullable(exception.value)
      ..throwable = null;
    _scrubFrames(exception.stackTrace?.frames);
  }
  for (final thread in event.threads ?? const <SentryThread>[]) {
    _scrubFrames(thread.stacktrace?.frames);
  }
  return event;
}

String? scrubNullable(String? input) =>
    input == null ? null : scrubSensitiveText(input);

void _scrubFrames(List<SentryStackFrame>? frames) {
  for (final frame in frames ?? const <SentryStackFrame>[]) {
    frame
      ..absPath = scrubNullable(frame.absPath)
      ..fileName = scrubNullable(frame.fileName)
      ..contextLine = null;
  }
}

// --- Capturing ------------------------------------------------------------

/// Sends a recovered error (see `logRecoverableError`). With an [error] this
/// is `captureException`, and [message] is attached as the context
/// `recovered`. Without an error it is `captureMessage`.
///
/// Does nothing while error reporting is switched off.
void captureRecoveredError(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_errorReportingEnabled) return;
  if (error != null) {
    unawaited(Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) =>
          scope.setContexts('recovered', <String, String>{'message': message}),
    ));
  } else {
    unawaited(Sentry.captureMessage(message));
  }
}

/// Sends an uncaught error from `FlutterError.onError` or
/// `PlatformDispatcher.instance.onError`. Does nothing while error reporting
/// is switched off.
void captureUncaughtError(Object error, StackTrace? stackTrace) {
  if (!_errorReportingEnabled) return;
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}
