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

Finder _switchFinder() => find.widgetWithText(
      SwitchListTile,
      'Fehlerberichte senden',
    );

bool _switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(_switchFinder()).value;

Future<void> _scrollToSwitch(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _switchFinder(),
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
      buildNumber: '13',
      buildSignature: '',
    );
  });

  tearDown(() => setErrorReportingEnabled(true));

  testWidgets('the switch is on by default', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildApp(prefs));
    await tester.pumpAndSettle();
    await _scrollToSwitch(tester);

    expect(_switchValue(tester), isTrue);
    expect(isErrorReportingEnabled, isTrue);
  });

  testWidgets('switching it off persists and disables reporting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildApp(prefs));
    await tester.pumpAndSettle();
    await _scrollToSwitch(tester);

    await tester.tap(_switchFinder());
    await tester.pumpAndSettle();

    expect(_switchValue(tester), isFalse);
    expect(isErrorReportingEnabled, isFalse);

    final stored =
        jsonDecode(prefs.getString('app_settings_v1')!) as Map<String, dynamic>;
    expect(stored['sendErrorReports'], isFalse);
  });

  testWidgets('the stored value is shown again after a restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_settings_v1': jsonEncode(
        const AppSettings(sendErrorReports: false).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildApp(prefs));
    await tester.pumpAndSettle();
    await _scrollToSwitch(tester);

    expect(_switchValue(tester), isFalse);
    expect(readSendErrorReportsSetting(prefs), isFalse);
  });
}
