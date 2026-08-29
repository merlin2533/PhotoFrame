import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
      appBar: AppBar(title: Text(l10n.settingsScreenTitle)),
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
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.settingsReplayOnboardingTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
        ],
      ),
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
