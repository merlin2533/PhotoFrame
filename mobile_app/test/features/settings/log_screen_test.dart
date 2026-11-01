import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/app_log_buffer.dart';
import 'package:mobile_app/features/settings/presentation/log_screen.dart';
import 'package:mobile_app/features/settings/state/app_log_providers.dart';
import 'package:mobile_app/l10n/app_localizations.dart';

Widget _buildApp(AppLogBuffer buffer) {
  return ProviderScope(
    overrides: [appLogBufferProvider.overrideWithValue(buffer)],
    child: const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: LogScreen(),
    ),
  );
}

void main() {
  testWidgets('shows the German empty state when there are no entries',
      (tester) async {
    await tester.pumpWidget(_buildApp(AppLogBuffer()));
    await tester.pumpAndSettle();

    expect(find.text('Protokoll'), findsOneWidget);
    expect(find.text('Noch keine Einträge.'), findsOneWidget);
  });

  testWidgets('shows an entry with its message and error text', (tester) async {
    final buffer = AppLogBuffer()
      ..add(AppLogEntry(
        time: DateTime(2026, 11, 1, 9, 15, 0),
        level: AppLogLevel.error,
        message: 'Foto kann nicht skaliert werden',
        errorText: 'FormatException: defekt',
      ));

    await tester.pumpWidget(_buildApp(buffer));
    await tester.pumpAndSettle();

    expect(find.text('Foto kann nicht skaliert werden'), findsOneWidget);
    expect(find.textContaining('FormatException: defekt'), findsOneWidget);
    expect(find.text('Noch keine Einträge.'), findsNothing);
  });

  testWidgets('new entries appear while the screen is open', (tester) async {
    final buffer = AppLogBuffer();
    await tester.pumpWidget(_buildApp(buffer));
    await tester.pumpAndSettle();

    buffer.add(AppLogEntry(
      time: DateTime(2026, 11, 1, 9, 15, 0),
      level: AppLogLevel.warning,
      message: 'Quelle übersprungen',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Quelle übersprungen'), findsOneWidget);
    expect(find.text('Noch keine Einträge.'), findsNothing);
  });

  testWidgets('"Leeren" asks for confirmation and then clears the log',
      (tester) async {
    final buffer = AppLogBuffer()
      ..add(AppLogEntry(
        time: DateTime(2026, 11, 1, 9, 15, 0),
        level: AppLogLevel.warning,
        message: 'Quelle übersprungen',
      ));

    await tester.pumpWidget(_buildApp(buffer));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Leeren'));
    await tester.pumpAndSettle();
    expect(find.text('Protokoll leeren?'), findsOneWidget);

    await tester.tap(find.text('Leeren').last);
    await tester.pumpAndSettle();

    expect(buffer.isEmpty, isTrue);
    expect(find.text('Noch keine Einträge.'), findsOneWidget);
  });
}
