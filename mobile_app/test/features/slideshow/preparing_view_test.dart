import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/cache/prepared_count_provider.dart';
import 'package:mobile_app/features/cache/small_photo_cache.dart';
import 'package:mobile_app/features/settings/domain/app_settings.dart';
import 'package:mobile_app/features/settings/state/settings_providers.dart';
import 'package:mobile_app/features/slideshow/domain/daily_selection.dart';
import 'package:mobile_app/features/slideshow/domain/rotation_swap.dart';
import 'package:mobile_app/features/slideshow/presentation/widgets/preparing_view.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mib = 1024 * 1024;

/// Test stand-in that reports a fixed status and never prepares anything.
class _StatusWorker extends SmallPhotoWorker {
  _StatusWorker(this.status);

  final SmallPhotoStatus status;

  @override
  SmallPhotoStatus build() => status;
}

/// Pumps the preparing view with a fake cache count of [cachedCount], the
/// daily swap percent [swapPercent], and a swap that ran today when
/// [swappedToday] is set.
Future<void> _pumpPreparingView(
  WidgetTester tester,
  SmallPhotoStatus status, {
  int cachedCount = 0,
  int swapPercent = 5,
  bool swappedToday = false,
  int? poolSize,
}) async {
  SharedPreferences.setMockInitialValues({
    if (swappedToday)
      rotationSwapDayPrefsKey: DailySelection.dayKey(DateTime.now()),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        smallPhotoWorkerProvider.overrideWith(() => _StatusWorker(status)),
        preparedCountProvider.overrideWith((ref) async => cachedCount),
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        settingsProvider.overrideWith(
          () => _FixedSettings(AppSettings(rotationSwapPercent: swapPercent)),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PreparingView(poolSize: poolSize),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FixedSettings extends AppSettingsController {
  _FixedSettings(this.settings);

  final AppSettings settings;

  @override
  Future<AppSettings> build() async => settings;
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

  testWidgets('shows the cached photo count and the daily swap',
      (tester) async {
    await _pumpPreparingView(
      tester,
      const SmallPhotoStatus(done: 0, total: 5, running: true),
      cachedCount: 42,
      swapPercent: 10,
      poolSize: 100,
    );

    expect(find.text('42 Fotos im Cache'), findsOneWidget);
    // Not swapped yet today: nothing changed so far.
    expect(find.text('Heute ausgetauscht: 0 von 100'), findsOneWidget);
    expect(
      find.text('Täglicher Austausch: 10 % (10 Fotos pro Tag)'),
      findsOneWidget,
    );
  });

  testWidgets('counts the swap of today once it ran', (tester) async {
    await _pumpPreparingView(
      tester,
      const SmallPhotoStatus(done: 0, total: 5, running: true),
      swappedToday: true,
      poolSize: 100,
    );

    expect(
      find.text('Heute ausgetauscht: ${rotationSwapSize(100)} von 100'),
      findsOneWidget,
    );
    expect(find.text('Täglicher Austausch: 5 % (5 Fotos pro Tag)'),
        findsOneWidget);
  });

  testWidgets('without a known pool size only the percent is shown',
      (tester) async {
    await _pumpPreparingView(
      tester,
      const SmallPhotoStatus(done: 0, total: 5, running: true),
      swapPercent: 5,
    );

    expect(find.text('Täglicher Austausch: 5 %'), findsOneWidget);
    expect(find.textContaining('Heute ausgetauscht'), findsNothing);
  });

  testWidgets('a daily swap of 0 percent shows 0 %', (tester) async {
    await _pumpPreparingView(
      tester,
      const SmallPhotoStatus(done: 0, total: 5, running: true),
      swapPercent: 0,
      swappedToday: true,
      poolSize: 100,
    );

    expect(find.text('Täglicher Austausch: 0 % (0 Fotos pro Tag)'),
        findsOneWidget);
    expect(find.text('Heute ausgetauscht: 0 von 100'), findsOneWidget);
  });
}
