import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../l10n/app_localizations.dart';

/// Top-level settings hub. Each row navigates to a focused sub-screen
/// rather than cramming every setting into one long list (per the M6 task:
/// "mehrere Unterseiten, nicht eine riesige Liste").
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Einstellungen durchsuchen',
            onPressed: () => showSearch<void>(
              context: context,
              delegate: _SettingsSearchDelegate(),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          _SettingsGroupHeader(l10n.settingsGroupSlideshow),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: Text(l10n.settingsSlideshowTitle),
            subtitle: Text(l10n.settingsSlideshowSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/slideshow'),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_high_outlined),
            title: Text(l10n.settingsAlwaysOnTitle),
            subtitle: Text(l10n.settingsAlwaysOnSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/always-on'),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.settingsNightModeTitle),
            subtitle: Text(l10n.settingsNightModeSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/night-mode'),
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: Text(l10n.settingsWeatherTitle),
            subtitle: Text(l10n.settingsWeatherSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/weather'),
          ),
          const Divider(),
          _SettingsGroupHeader(l10n.settingsGroupContent),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(l10n.settingsSourcesTitle),
            subtitle: Text(l10n.settingsSourcesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/sources'),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.settingsCacheTitle),
            subtitle: Text(l10n.settingsCacheSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/cache'),
          ),
          ListTile(
            leading: const Icon(Icons.dataset_outlined),
            title: Text(l10n.settingsPoolTitle),
            subtitle: Text(l10n.settingsPoolSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/pool'),
          ),
          const Divider(),
          _SettingsGroupHeader(l10n.settingsGroupSharing),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(l10n.settingsSharingTitle),
            subtitle: Text(l10n.settingsSharingSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/sharing'),
          ),
          const Divider(),
          _SettingsGroupHeader(l10n.settingsGroupGeneral),
          ListTile(
            leading: const Icon(Icons.accessibility_new_outlined),
            title: Text(l10n.settingsAccessibilityTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/accessibility'),
          ),
          ListTile(
            leading: const Icon(Icons.phonelink_setup_outlined),
            title: Text(l10n.settingsAutostartHelpTitle),
            subtitle: Text(l10n.settingsAutostartHelpSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/autostart-help'),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(l10n.settingsKioskTitle),
            subtitle: Text(l10n.settingsKioskSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/kiosk'),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(l10n.settingsLanguageTitle),
            subtitle: Text(l10n.settingsLanguageSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/language'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.settingsReplayOnboardingTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
          const _AppVersionFooter(),
        ],
      ),
    );
  }
}

/// Short git commit hash the app was built from. Injected at build time with
/// `--dart-define=GIT_COMMIT=$(git rev-parse --short HEAD)`; builds without
/// the define (for example `flutter run`) show the fallback text.
const String buildGitCommit =
    String.fromEnvironment('GIT_COMMIT', defaultValue: 'unbekannt');

/// Reads `pubspec.yaml`'s `version:` (e.g. `1.2.3+45`) via `package_info_plus`
/// at build time - no manual wiring needed when the version is bumped
/// (including by the repo's own pre-commit hook, see CHANGELOG.md /
/// CONTRIBUTING.md). Shows nothing until resolved rather than a loading
/// spinner - this is a footer, not a critical piece of content.
class _AppVersionFooter extends StatelessWidget {
  const _AppVersionFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              '${info.appName} ${info.version}+${info.buildNumber} · '
              '$buildGitCommit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsGroupHeader extends StatelessWidget {
  const _SettingsGroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// Searches the settings sub-pages by name and opens the chosen one.
class _SettingsSearchDelegate extends SearchDelegate<void> {
  static const _entries = <(String, String)>[
    ('Diashow', '/settings/slideshow'),
    ('Dauer-Modus', '/settings/always-on'),
    ('Nachtmodus', '/settings/night-mode'),
    ('Wetter', '/settings/weather'),
    ('Quellen', '/settings/sources'),
    ('Cache', '/settings/cache'),
    ('Pool und Index', '/settings/pool'),
    ('Teilen', '/settings/sharing'),
    ('Barrierefreiheit', '/settings/accessibility'),
    ('Autostart', '/settings/autostart-help'),
    ('Kiosk-Modus', '/settings/kiosk'),
    ('Sprache', '/settings/language'),
    ('Setup-Guide', '/onboarding'),
  ];

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final q = query.trim().toLowerCase();
    final matches = [
      for (final e in _entries)
        if (q.isEmpty || e.$1.toLowerCase().contains(q)) e,
    ];
    return ListView(
      children: [
        for (final (title, path) in matches)
          ListTile(
            title: Text(title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              close(context, null);
              context.push(path);
            },
          ),
      ],
    );
  }
}
