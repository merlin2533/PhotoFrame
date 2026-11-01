import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/preparing_view.dart';
import 'package:mobile_app/l10n/app_localizations.dart';

const _mib = 1024 * 1024;

/// Test stand-in that reports a fixed status and never prepares anything.
class _StatusWorker extends SmallPhotoWorker {
  _StatusWorker(this.status);

  final SmallPhotoStatus status;

  @override
  SmallPhotoStatus build() => status;
}

Future<void> _pumpPreparingView(
  WidgetTester tester,
  SmallPhotoStatus status,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        smallPhotoWorkerProvider.overrideWith(() => _StatusWorker(status)),
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
        home: PreparingView(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the downloaded bytes, speed and open conversions',
      (tester) async {
    await _pumpPreparingView(
      tester,
      SmallPhotoStatus(
        done: 2,
        total: 5,
        running: true,
        waiting: 3,
        downloadedBytes: (12.3 * _mib).round(),
        downloadRate: 2.5 * _mib,
        openConversions: 1,
      ),
    );

    expect(
      find.text('2 von 5 Fotos vorbereitet · 3 in Warteschlange'),
      findsOneWidget,
    );
    expect(find.text('12,3 MB heruntergeladen'), findsOneWidget);
    expect(find.text('Geschwindigkeit: 2,5 MB/s'), findsOneWidget);
    expect(find.text('Offene Konvertierungen: 1'), findsOneWidget);
  });

  testWidgets('an idle download shows 0 MB/s', (tester) async {
    await _pumpPreparingView(
      tester,
      const SmallPhotoStatus(done: 0, total: 5, running: true),
    );

    expect(find.text('0 KB heruntergeladen'), findsOneWidget);
    expect(find.text('Geschwindigkeit: 0 MB/s'), findsOneWidget);
    expect(find.text('Offene Konvertierungen: 0'), findsOneWidget);
  });
}
