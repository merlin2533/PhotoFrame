import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry message of every user crash report, so the reports can be found
/// together in GlitchTip.
const String kUserCrashReportMessage = 'User crash report';

/// Key of the Sentry context that carries the report data.
const String kUserCrashReportContext = 'crash_report';

/// Number of trace lines sent with a user crash report.
const int kUserCrashReportTraceLines = 200;

/// Builds the data of a user crash report. Holds counts, sizes, versions and
/// the trace text only: never a file name, a folder, a host or a credential.
///
/// [traceLines] are joined with line breaks into the single field `trace`.
Map<String, Object> buildUserCrashReportData({
  required String appVersion,
  required String build,
  required String deviceModel,
  required String androidVersion,
  required int cacheFiles,
  required int cacheBytes,
  required int cacheLimitBytes,
  required bool preparationEnabled,
  required int sourceCount,
  required List<String> traceLines,
}) {
  return {
    'app_version': appVersion,
    'build': build,
    'device_model': deviceModel,
    'android_version': androidVersion,
    'cache_files': cacheFiles,
    'cache_bytes': cacheBytes,
    'cache_limit_bytes': cacheLimitBytes,
    'preparation_enabled': preparationEnabled,
    'source_count': sourceCount,
    'trace': traceLines.join('\n'),
  };
}

/// Sends one event with [kUserCrashReportMessage]. The data goes into the
/// context [kUserCrashReportContext], so the shared `beforeSend` scrubbing in
/// `redactSentryEvent` covers it like every other event.
Future<void> sendUserCrashReport(Map<String, Object> data) async {
  await Sentry.captureMessage(
    kUserCrashReportMessage,
    withScope: (scope) => scope.setContexts(kUserCrashReportContext, data),
  );
}
