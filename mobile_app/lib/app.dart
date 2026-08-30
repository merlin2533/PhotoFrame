import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/pairing/state/pairing_providers.dart';
import 'features/settings/state/settings_providers.dart';
import 'l10n/app_localizations.dart';

/// Root widget of the PhotoFrame companion app.
///
/// Waits for [settingsProvider] to load once (so the router can decide
/// whether to open the onboarding wizard or go straight to the home
/// screen), then wires up [MaterialApp.router] with `go_router`.
class PhotoFrameApp extends ConsumerWidget {
  const PhotoFrameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return settingsAsync.when(
      loading: () => const _SplashApp(),
      error: (error, stackTrace) => _SplashApp(error: error),
      data: (settings) => _RoutedApp(
        initialLocation: settings.onboardingCompleted ? '/' : '/onboarding',
      ),
    );
  }
}

class _SplashApp extends StatelessWidget {
  const _SplashApp({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text('Fehler beim Starten: $error'),
        ),
      ),
    );
  }
}

/// Resolves [AppSettings.languageCode] into the actual [Locale] passed to
/// [MaterialApp.router]: an explicit choice ('de'/'en') wins outright;
/// `null` (the "follow system language" option in
/// `language_settings_screen.dart`) follows the platform locale as long as
/// its language is one of [AppLocalizations.supportedLocales], falling back
/// to German - this app's primary/default locale (see docs/DECISIONS.md
/// ADR-009) - when the system language isn't supported at all.
Locale resolveAppLocale(String? languageCode) {
  if (languageCode != null && languageCode.isNotEmpty) {
    return Locale(languageCode);
  }

  final systemLocale = PlatformDispatcher.instance.locale;
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == systemLocale.languageCode) {
      return supported;
    }
  }
  return const Locale('de');
}

class _RoutedApp extends ConsumerStatefulWidget {
  const _RoutedApp({required this.initialLocation});

  final String initialLocation;

  @override
  ConsumerState<_RoutedApp> createState() => _RoutedAppState();
}

class _RoutedAppState extends ConsumerState<_RoutedApp> {
  late final GoRouter _router = buildAppRouter(initialLocation: widget.initialLocation);

  @override
  Widget build(BuildContext context) {
    final languageCode = ref.watch(settingsProvider.select((s) => s.valueOrNull?.languageCode));

    return MaterialApp.router(
      title: 'PhotoFrame',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      // See [resolveAppLocale] doc comment: `languageCode == null` follows
      // the system locale (falling back to German), otherwise the user's
      // explicit choice from `language_settings_screen.dart` wins.
      locale: resolveAppLocale(languageCode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Subscribes to incoming `config_push` realtime notifications for the
      // whole app (see `pairing_providers.dart`'s [ConfigPushListener] doc
      // comment) - placed in `builder` rather than deeper in the tree so it
      // sits above `go_router`'s own navigator and can push a route from an
      // event that isn't tied to whatever screen happens to be showing.
      builder: (context, child) => ConfigPushListener(child: child ?? const SizedBox.shrink()),
    );
  }
}
