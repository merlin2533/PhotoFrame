import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/settings/presentation/settings_screen.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'PhotoFrame',
      packageName: 'de.photoframe.test',
      version: '0.1.0',
      buildNumber: '10',
      buildSignature: '',
    );
  });

  testWidgets('settings end with the app version and the build commit',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(),
    ));

    // The commit is the --dart-define value, or the fallback text when the
    // test runs without it.
    final footer = find.text('PhotoFrame 0.1.0+10 · $buildGitCommit');
    await tester.scrollUntilVisible(footer, 200);
    await tester.pumpAndSettle();

    expect(footer, findsOneWidget);
    expect(buildGitCommit, isNotEmpty);
  });
}
