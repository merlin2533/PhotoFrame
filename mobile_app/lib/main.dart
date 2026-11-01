import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/observability/error_reporter.dart';
import 'core/utils/debug_trace.dart';
import 'features/settings/state/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug trace: trims the trace file in the background. Not awaited, so it
  // never delays runApp. Does nothing in release builds.
  unawaited(DebugTrace.startup());

  // Read the persisted "Fehlerberichte senden" switch before anything can
  // fail, so that an opted-out user never sends an early error.
  final prefs = await SharedPreferences.getInstance();
  setErrorReportingEnabled(readSendErrorReportsSetting(prefs));

  await SentryFlutter.init(
    configureErrorReporting,
    appRunner: () {
      // Replaces the handlers Sentry installed, so each uncaught error is
      // captured once, through the same reporter as recovered errors.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        captureUncaughtError(details.exception, details.stack);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        captureUncaughtError(error, stack);
        return true;
      };
      runApp(
        const ProviderScope(
          child: PhotoFrameApp(),
        ),
      );
    },
  );
}
