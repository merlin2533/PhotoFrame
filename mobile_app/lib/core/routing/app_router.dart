import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/accessibility_settings_screen.dart';
import '../../features/settings/presentation/always_on_settings_screen.dart';
import '../../features/settings/presentation/autostart_help_screen.dart';
import '../../features/settings/presentation/cache_settings_screen.dart';
import '../../features/settings/presentation/kiosk_settings_screen.dart';
import '../../features/settings/presentation/night_mode_settings_screen.dart';
import '../../features/settings/presentation/pool_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/sharing_settings_screen.dart';
import '../../features/settings/presentation/slideshow_settings_screen.dart';
import '../../features/settings/presentation/weather_settings_screen.dart';
import '../../features/slideshow/presentation/slideshow_screen.dart';
import '../../features/sources/nextcloud/nextcloud_config_form.dart';
import '../../features/sources/presentation/add_source_screen.dart';
import '../../features/sources/presentation/source_list_screen.dart';
import '../../features/sources/smb/smb_config_form.dart';
import '../../screens/home_screen.dart';

/// Builds the app's [GoRouter]. [initialLocation] is decided by the caller
/// (see `app.dart`) based on whether onboarding has been completed yet.
GoRouter buildAppRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/slideshow',
        name: 'slideshow',
        builder: (context, state) => const SlideshowScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'slideshow',
            name: 'settings-slideshow',
            builder: (context, state) => const SlideshowSettingsScreen(),
          ),
          GoRoute(
            path: 'always-on',
            name: 'settings-always-on',
            builder: (context, state) => const AlwaysOnSettingsScreen(),
          ),
          GoRoute(
            path: 'night-mode',
            name: 'settings-night-mode',
            builder: (context, state) => const NightModeSettingsScreen(),
          ),
          GoRoute(
            path: 'cache',
            name: 'settings-cache',
            builder: (context, state) => const CacheSettingsScreen(),
          ),
          GoRoute(
            path: 'pool',
            name: 'settings-pool',
            builder: (context, state) => const PoolSettingsScreen(),
          ),
          GoRoute(
            path: 'sharing',
            name: 'settings-sharing',
            builder: (context, state) => const SharingSettingsScreen(),
          ),
          GoRoute(
            path: 'weather',
            name: 'settings-weather',
            builder: (context, state) => const WeatherSettingsScreen(),
          ),
          GoRoute(
            path: 'accessibility',
            name: 'settings-accessibility',
            builder: (context, state) => const AccessibilitySettingsScreen(),
          ),
          GoRoute(
            path: 'autostart-help',
            name: 'settings-autostart-help',
            builder: (context, state) => const AutostartHelpScreen(),
          ),
          GoRoute(
            path: 'kiosk',
            name: 'settings-kiosk',
            builder: (context, state) => const KioskSettingsScreen(),
          ),
          GoRoute(
            path: 'sources',
            name: 'settings-sources',
            builder: (context, state) => const SourceListScreen(),
            routes: [
              GoRoute(
                path: 'add',
                name: 'settings-sources-add',
                builder: (context, state) => const AddSourceScreen(),
                routes: [
                  GoRoute(
                    path: 'smb',
                    name: 'settings-sources-add-smb',
                    builder: (context, state) => const SmbConfigFormScreen(),
                  ),
                  GoRoute(
                    path: 'nextcloud',
                    name: 'settings-sources-add-nextcloud',
                    builder: (context, state) => const NextcloudConfigFormScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
