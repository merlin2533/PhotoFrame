import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/observability/error_reporter.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/presentation/settings_screen.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildApp(SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(Future.value(prefs)),
    ],
    child: const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(),
    ),
  );
}

final Finder _tileFinder =
    find.widgetWithText(ListTile, 'Absturzbericht senden');

Future<void> _scrollToTile(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _tileFinder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'PhotoFrame',
      packageName: 'de.photoframe.test',
      version: '0.1.0',
      buildNumber: '14',
      buildSignature: '',
    );
  });

  tearDown(() => setErrorReportingEnabled(true));

  testWidgets('the crash report tile opens a confirmation dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildApp(prefs));
    await tester.pumpAndSettle();
    await _scrollToTile(tester);

    expect(_tileFinder, findsOneWidget);
    expect(
        find.text(
            'Sendet Diagnosedaten an den Entwickler. Keine Fotonamen, keine Zugangsdaten.'),
        findsOneWidget);

    await tester.tap(_tileFinder);
    await tester.pumpAndSettle();

    expect(find.text('Absturzbericht senden?'), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
    expect(find.text('Senden'), findsOneWidget);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(find.text('Absturzbericht senden?'), findsNothing);
  });

  testWidgets('with error reports off it shows a snackbar and no dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_settings_v1': jsonEncode(
        const AppSettings(sendErrorReports: false).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    // main() applies the stored switch at startup; the widget does not.
    setErrorReportingEnabled(false);

    await tester.pumpWidget(_buildApp(prefs));
    await tester.pumpAndSettle();
    await _scrollToTile(tester);

    await tester.tap(_tileFinder);
    await tester.pumpAndSettle();

    expect(find.text('Fehlerberichte sind ausgeschaltet'), findsOneWidget);
    expect(find.text('Absturzbericht senden?'), findsNothing);
  });
}
