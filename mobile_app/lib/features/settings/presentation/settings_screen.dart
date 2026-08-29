import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Top-level settings hub. Each row navigates to a focused sub-screen
/// rather than cramming every setting into one long list (per the M6 task:
/// "mehrere Unterseiten, nicht eine riesige Liste").
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          const _SettingsGroupHeader('Diashow'),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('Diashow'),
            subtitle: const Text('Intervall, Overlays, Anzeige-Modus, Übergänge'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/slideshow'),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_high_outlined),
            title: const Text('Dauer-Modus'),
            subtitle: const Text('Bildschirm dauerhaft an lassen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/always-on'),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Nachtmodus'),
            subtitle: const Text('Zeitplan, Dimm-Stärke'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/night-mode'),
          ),
          const Divider(),
          const _SettingsGroupHeader('Inhalte'),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Quellen'),
            subtitle: const Text('Ordner, Freigaben, Nextcloud verwalten'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/sources'),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Cache-Verwaltung'),
            subtitle: const Text('Belegter Speicher, Limit, Cache leeren'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/cache'),
          ),
          ListTile(
            leading: const Icon(Icons.dataset_outlined),
            title: const Text('Pool/Index'),
            subtitle: const Text('Arbeitsmenge, Auffüll-Intervall, neue Bilder'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/pool'),
          ),
          const Divider(),
          const _SettingsGroupHeader('Teilen'),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Sharing/Relay'),
            subtitle: const Text('Relay-Server-URL, Pairing'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/sharing'),
          ),
          const Divider(),
          const _SettingsGroupHeader('Allgemein'),
          ListTile(
            leading: const Icon(Icons.accessibility_new_outlined),
            title: const Text('Barrierefreiheit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/accessibility'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Setup-Guide erneut anzeigen'),
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
