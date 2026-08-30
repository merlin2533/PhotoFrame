import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/settings/presentation/settings_screen.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Placeholder destination screen used instead of the app's real settings
/// sub-screens - this test only cares that [SettingsScreen] lists the
/// expected entries and that tapping one navigates to the right route, not
/// about the destination screens' own content/behaviour (those get their
/// own tests elsewhere as the app grows a widget-test suite).
class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('stub:$label')));
  }
}

Widget _buildTestApp() {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(path: 'slideshow', builder: (c, s) => const _StubScreen('slideshow')),
          GoRoute(path: 'always-on', builder: (c, s) => const _StubScreen('always-on')),
          GoRoute(path: 'night-mode', builder: (c, s) => const _StubScreen('night-mode')),
          GoRoute(path: 'weather', builder: (c, s) => const _StubScreen('weather')),
          GoRoute(path: 'sources', builder: (c, s) => const _StubScreen('sources')),
          GoRoute(path: 'cache', builder: (c, s) => const _StubScreen('cache')),
          GoRoute(path: 'pool', builder: (c, s) => const _StubScreen('pool')),
          GoRoute(path: 'sharing', builder: (c, s) => const _StubScreen('sharing')),
          GoRoute(path: 'accessibility', builder: (c, s) => const _StubScreen('accessibility')),
          GoRoute(path: 'autostart-help', builder: (c, s) => const _StubScreen('autostart-help')),
          GoRoute(path: 'kiosk', builder: (c, s) => const _StubScreen('kiosk')),
        ],
      ),
      GoRoute(path: '/onboarding', builder: (c, s) => const _StubScreen('onboarding')),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Grows the test surface tall enough that every `SettingsScreen` entry
  /// renders without needing to scroll the `ListView` first - a plain
  /// `find.text(...)` can't locate a `ListTile` the sliver hasn't laid out
  /// yet, and scrolling isn't the point of these navigation tests.
  Future<void> setTallSurface(WidgetTester tester) async {
    final originalSize = tester.view.physicalSize;
    final originalDpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
    });
  }

  testWidgets('shows every expected settings navigation entry', (tester) async {
    await setTallSurface(tester);
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Einstellungen'), findsOneWidget);

    // Slideshow group. "Diashow" is used as both the group header and the
    // first entry's title, so the entry itself is matched via its
    // containing ListTile rather than a bare (ambiguous) text lookup.
    expect(find.widgetWithText(ListTile, 'Diashow'), findsOneWidget);
    expect(find.text('Dauer-Modus'), findsOneWidget);
    expect(find.text('Nachtmodus'), findsOneWidget);
    expect(find.text('Wetter'), findsOneWidget);
    // Content group
    expect(find.text('Quellen'), findsOneWidget);
    expect(find.text('Cache-Verwaltung'), findsOneWidget);
    expect(find.text('Pool/Index'), findsOneWidget);
    // Sharing group
    expect(find.text('Sharing/Relay'), findsOneWidget);
    // General group, including the new kiosk entry from this change.
    expect(find.text('Autostart auf diesem Handy-Hersteller'), findsOneWidget);
    expect(find.text('Fotorahmen-Startbildschirm'), findsOneWidget);
  });

  testWidgets('tapping the kiosk entry navigates to the kiosk settings route', (tester) async {
    await setTallSurface(tester);
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fotorahmen-Startbildschirm'));
    await tester.pumpAndSettle();

    expect(find.text('stub:kiosk'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('tapping the slideshow entry navigates to the slideshow settings route',
      (tester) async {
    await setTallSurface(tester);
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Diashow'));
    await tester.pumpAndSettle();

    expect(find.text('stub:slideshow'), findsOneWidget);
  });
}
