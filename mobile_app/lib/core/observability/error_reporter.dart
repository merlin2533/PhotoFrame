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

/// Photo and video file extensions (case-insensitive).
const String _mediaExtensions =
    r'(?:jpe?g|png|heic|heif|webp|gif|bmp|tiff?|dng|raw|cr2|nef|arw|'
    r'mp4|mov|m4v|3gp|avi|mkv|webm)';

/// Source and config file extensions. Paths ending in one of these are kept
/// readable so that stack frames such as `lib/core/x.dart:42` survive.
const String _codeExtensions =
    r'(?:dart|kt|java|swift|m|h|c|cc|cpp|py|js|ts|gradle|plist|so|dylib|'
    r'arb|yaml|yml|json|xml|lock)';

/// Dotted names whose last label is a common source-code or data file
/// extension are not treated as hostnames (see [_scrubRules]).
const String _hostnameExcludedExtensions =
    r'(?:dart|kt|java|js|ts|json|yaml|yml|xml|gradle|md|txt|html|css|'
    r'lock|so|dylib|arb|plist|swift|m|h|c|cc|cpp|py|sh|log)';

final RegExp _mediaNamePattern =
    RegExp(r'\.' + _mediaExtensions + r'$', caseSensitive: false);
final RegExp _codeNamePattern =
    RegExp(r'\.' + _codeExtensions + r'$', caseSensitive: false);
final RegExp _lineSuffixPattern = RegExp(r'(?::\d+)+');
final RegExp _trailingPunctuationPattern = RegExp(r'[.,;:)\]"]+$');
final RegExp _numericSlashPattern = RegExp(r'^\d+(?:[/\\]\d+)+$');

/// True for tokens that are code references or plain numbers and dates
/// (`lib/core/x.dart:42`, `package:app/x.dart`, `1/2`, `12/05/2026`). Those
/// are not sensitive and stay readable. Media file names never count as code.
bool _isReadableReference(String token) {
  var core = token.replaceFirst(_lineSuffixPattern, '');
  core = core.replaceFirst(_trailingPunctuationPattern, '');
  if (_mediaNamePattern.hasMatch(core)) return false;
  return _codeNamePattern.hasMatch(core) || _numericSlashPattern.hasMatch(core);
}

String _redactAll(Match match) => kRedactedText;

/// Replaces the whole match, unless [keep] says the match is readable.
String _redactUnlessReadable(Match match) {
  final text = match.group(0)!;
  return _isReadableReference(text) ? text : kRedactedText;
}

/// Quoted text containing a path separator, such as
/// `"Urlaub 2023/Italien/IMG_1.jpg"`. The quotes stay, the content goes.
String _redactQuotedPath(Match match) {
  final quote = match.group(1)!;
  final content = match.group(2)!;
  if (!content.contains('/') && !content.contains('\\')) {
    return match.group(0)!;
  }
  if (_isReadableReference(content)) return match.group(0)!;
  return '$quote$kRedactedText$quote';
}

/// Keeps the text before the value (group 1) and the quotes (group 2),
/// replaces the value (group 3).
String _redactKeepingPrefix(Match match) {
  final quote = match.group(2) ?? '';
  return '${match.group(1)}$quote$kRedactedText$quote';
}

/// One scrubbing step: every match of [pattern] is replaced by the result of
/// [replace].
class _ScrubRule {
  _ScrubRule(this.pattern, [this.replace = _redactAll]);

  final RegExp pattern;
  final String Function(Match match) replace;
}

/// Patterns for data that must never leave the device, in application
/// order. Each match is replaced by [kRedactedText] unless noted otherwise.
///
/// Order matters: URLs and quoted paths go first so their parts are removed
/// as a whole before the more generic rules run over what is left.
final List<_ScrubRule> _scrubRules = [
  // Any URL with a scheme: http(s), file, content (Android SAF URIs carry
  // file names), smb, webdav, and so on. Covers the source hosts too.
  _ScrubRule(RegExp(r'''\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s'"<>]+''')),

  // Quoted text with a path separator, including folder names with spaces:
  // `"Urlaub 2023/Italien/IMG_1.jpg"`. Quoted code paths stay readable.
  _ScrubRule(RegExp(r'''(["'])([^"'\n]{1,512})\1'''), _redactQuotedPath),

  // Windows drive paths up to the end of the file name, including spaces
  // (`C:\Users\John Smith\Pictures\a b.jpg`). Without a file extension the
  // path ends at the next whitespace. UNC paths (`\\server\share\...`).
  _ScrubRule(RegExp(
    r'''\b[A-Za-z]:\\(?:[^\\/\r\n"'<>|*?]+\\)*[^\\/\r\n"'<>|*?]*?'''
    r'''\.[A-Za-z0-9]{1,5}\b'''
    r'''|\b[A-Za-z]:\\[^\s'"<>]*'''
    r'''|\\\\[^\s'"<>]+''',
  )),

  // POSIX absolute paths up to the end of the file name, including spaces
  // (`/data/.../My Photos/a.jpg`). Without a file extension the path ends at
  // the next whitespace. The lookbehind keeps `package:` and similar forms.
  _ScrubRule(RegExp(
    r'''(?<![\w:])/(?:[^/\r\n'"<>]+/)*[^/\r\n'"<>]*?\.[A-Za-z0-9]{1,5}\b'''
    r'''|(?<![\w:])/[^\s'"<>]+''',
  )),

  // IPv6 addresses such as `fe80::1` or `2001:db8::1`, also in brackets.
  _ScrubRule(RegExp(
    r'(?<![\w:])(?=[0-9A-Fa-f:]*::|(?:[0-9A-Fa-f]{1,4}:){7})'
    r'[0-9A-Fa-f:]{2,39}(?![\w:])',
  )),

  // E-mail addresses and user@host pairs (`user@nas`).
  _ScrubRule(RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9][A-Za-z0-9.\-]*')),

  // Host named in quotes after a keyword: `zu "nas"`, `for "nas"`,
  // `Host "nas"`, `server "nas"`, `SMB-Host "nas"`. Keyword and quotes stay.
  _ScrubRule(
    RegExp(
      r'''(\b(?:zu|to|for|von|host|hostname|server|address|adresse)\s+)'''
      r'''(["'])([^"'\n]{1,253})\2''',
      caseSensitive: false,
    ),
    _redactKeepingPrefix,
  ),

  // Key-value form: `address = nas, port = 445`, `host: nas`. Only the value
  // is replaced, the key stays.
  _ScrubRule(
    RegExp(
      r'''(\b(?:host|hostname|server|address|adresse)\s*[=:]\s*)'''
      r'''(["']?)([^\s"',;()]+)\2''',
      caseSensitive: false,
    ),
    _redactKeepingPrefix,
  ),

  // Host named without quotes after a keyword, only when it looks like a
  // device name (contains `-`, `_` or `.`): `Host Nas-Synology`.
  _ScrubRule(
    RegExp(
      r'(\b(?:host|hostname|server)\s+)'
      r'([A-Za-z0-9]+(?:[\-_.][A-Za-z0-9]+)+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$kRedactedText',
  ),

  // Relative paths with spaces that end in a photo or video file name:
  // `Urlaub 2023/Italien/IMG_1.jpg`. The whole path goes.
  _ScrubRule(
    RegExp(
      r'''[^\s'"<>/\\]+(?: [^\s'"<>/\\]+)*'''
      r'''(?:[/\\][^\s'"<>/\\]+(?: [^\s'"<>/\\]+)*)+'''
      '\\.$_mediaExtensions\\b',
      caseSensitive: false,
    ),
  ),

  // Any other token with a path separator and no spaces (`Immich/Alben`).
  // Code references, numbers and dates stay readable (see
  // [_isReadableReference]).
  _ScrubRule(
      RegExp(r'''[^\s'"<>/\\]*[/\\][^\s'"<>]*'''), _redactUnlessReadable),

  // Photo and video file names without a directory part, any position.
  _ScrubRule(
    RegExp(r'''[^\s'"<>/\\]+\.''' + _mediaExtensions + r'\b',
        caseSensitive: false),
  ),

  // IPv4 addresses (NAS and router addresses).
  _ScrubRule(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')),

  // Hostnames such as `nas.local` or `cloud.example.org`. Dotted names
  // whose last label is a common source-code or data file extension are
  // skipped, so that stack frames like `main.dart` stay readable.
  _ScrubRule(
    RegExp(
      r'''\b(?:[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?\.)+'''
      '(?!$_hostnameExcludedExtensions\\b)[a-z]{2,24}\\b',
      caseSensitive: false,
    ),
  ),

  // Bare localhost (with optional port).
  _ScrubRule(
    RegExp(r'\blocalhost(?::\d+)?\b', caseSensitive: false),
  ),
];

/// Replaces every piece of data that must not leave the device in [input]
/// with [kRedactedText]: URLs (any scheme), e-mail addresses and user@host
/// pairs, Windows, UNC and POSIX file paths (also with spaces), quoted paths,
/// photo and video file names, IPv4 and IPv6 addresses, hostnames after the
/// keywords listed on [_scrubRules], and localhost.
///
/// Pure function, used by [redactSentryEvent] on every string of an event.
String scrubSensitiveText(String input) {
  var output = input;
  for (final rule in _scrubRules) {
    output = output.replaceAllMapped(rule.pattern, rule.replace);
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
/// off, and otherwise removes breadcrumbs, user, request, debug image and
/// host details and scrubs every remaining string with [scrubSensitiveText].
FutureOr<SentryEvent?> redactSentryEvent(SentryEvent event, Hint hint) {
  if (!_errorReportingEnabled) return null;

  event
    ..breadcrumbs = null
    ..user = null
    ..request = null
    ..serverName = null
    ..debugMeta = null
    ..culprit = scrubNullable(event.culprit)
    ..transaction = scrubNullable(event.transaction);

  _scrubContexts(event.contexts);

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

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    exception
      ..type = scrubNullable(exception.type)
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

/// Scrubs the strings of every context. Plain values and maps are scrubbed
/// recursively. Typed device, OS, app and runtime contexts keep their
/// diagnostic fields with free text scrubbed, and lose identifiers and paths.
/// Any other typed context is removed.
void _scrubContexts(Contexts contexts) {
  for (final key in contexts.keys.toList()) {
    final value = contexts[key];
    if (value == null) continue;
    if (value is String || value is Map || value is List) {
      contexts[key] = _scrubValue(value);
    } else if (value is SentryDevice) {
      value
        ..name = null
        ..deviceUniqueIdentifier = null
        ..cpuDescription = scrubNullable(value.cpuDescription)
        ..deviceType = scrubNullable(value.deviceType);
    } else if (value is SentryOperatingSystem) {
      value
        ..name = scrubNullable(value.name)
        ..build = scrubNullable(value.build)
        ..kernelVersion = scrubNullable(value.kernelVersion)
        ..rawDescription = scrubNullable(value.rawDescription);
    } else if (value is SentryApp) {
      value
        ..name = scrubNullable(value.name)
        ..identifier = scrubNullable(value.identifier)
        ..build = scrubNullable(value.build)
        ..deviceAppHash = null;
    } else if (value is SentryRuntime) {
      value
        ..name = scrubNullable(value.name)
        ..build = scrubNullable(value.build)
        ..compiler = scrubNullable(value.compiler)
        ..rawDescription = scrubNullable(value.rawDescription);
    } else {
      contexts.remove(key);
    }
  }
}

void _scrubFrames(List<SentryStackFrame>? frames) {
  for (final frame in frames ?? const <SentryStackFrame>[]) {
    frame
      ..absPath = scrubNullable(frame.absPath)
      ..fileName = scrubNullable(frame.fileName)
      ..module = scrubNullable(frame.module)
      ..package = scrubNullable(frame.package)
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
