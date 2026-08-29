import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/state/settings_providers.dart';

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

class _RoutedApp extends StatefulWidget {
  const _RoutedApp({required this.initialLocation});

  final String initialLocation;

  @override
  State<_RoutedApp> createState() => _RoutedAppState();
}

class _RoutedAppState extends State<_RoutedApp> {
  late final GoRouter _router = buildAppRouter(initialLocation: widget.initialLocation);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PhotoFrame',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('de'),
      ],
    );
  }
}
