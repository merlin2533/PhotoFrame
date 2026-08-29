import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../mock/mock_photo_source.dart';
import '../state/sources_providers.dart';

/// Lets the user pick a source type to add.
///
/// Only "Mock/Test-Quelle" is actually wired up here - `SmbPhotoSource`,
/// `NextcloudPhotoSource` and `LocalFolderSource` config forms
/// (`smb_config_form.dart`, `nextcloud_config_form.dart`, a local-folder
/// picker) are expected to come from a parallel agent per `docs/PLAN.md`.
/// This screen shows them as disabled placeholders so the navigation
/// structure is complete without pretending those flows already work.
class AddSourceScreen extends ConsumerWidget {
  const AddSourceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quelle hinzufügen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SourceTypeCard(
            icon: Icons.folder_outlined,
            title: 'Lokaler Ordner',
            subtitle: 'Noch nicht verfügbar - kommt in einem späteren Schritt',
            enabled: false,
          ),
          const _SourceTypeCard(
            icon: Icons.dns_outlined,
            title: 'SMB-Netzwerkfreigabe',
            subtitle: 'Noch nicht verfügbar - kommt in einem späteren Schritt',
            enabled: false,
          ),
          const _SourceTypeCard(
            icon: Icons.cloud_outlined,
            title: 'Nextcloud',
            subtitle: 'Noch nicht verfügbar - kommt in einem späteren Schritt',
            enabled: false,
          ),
          _SourceTypeCard(
            icon: Icons.science_outlined,
            title: 'Mock/Test-Quelle',
            subtitle: 'Für Entwicklung: generiert Beispielbilder',
            enabled: true,
            onTap: () {
              ref.read(sourcesProvider.notifier).add(MockPhotoSource(
                    displayName: 'Test-Quelle ${DateTime.now().millisecondsSinceEpoch}',
                  ));
              context.pop();
            },
          ),
        ],
      ),
    );
  }
}

class _SourceTypeCard extends StatelessWidget {
  const _SourceTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: enabled,
        trailing: enabled ? const Icon(Icons.chevron_right) : null,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
