import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../local/local_folder_source.dart';
import '../mock/mock_photo_source.dart';
import '../state/sources_providers.dart';

/// Lets the user pick a source type to add.
///
/// SMB and Nextcloud each navigate to their own configuration form
/// (`smb_config_form.dart`/`nextcloud_config_form.dart`); the local folder
/// option opens the platform directory picker directly, since it needs no
/// other input.
class AddSourceScreen extends ConsumerWidget {
  const AddSourceScreen({super.key});

  Future<void> _addLocalFolder(BuildContext context, WidgetRef ref) async {
    final id = ref.read(sourceIdGeneratorProvider).v4();
    final source = LocalFolderSource(id: id);
    final result = await source.pickRootFolder(dialogTitle: 'Ordner auswählen');

    if (!context.mounted) return;

    result.when(
      onOk: (path) {
        if (path == null) {
          // User cancelled the picker - nothing to register.
          unawaited(source.dispose());
          return;
        }
        ref.read(sourcesProvider.notifier).add(source);
        context.pop();
      },
      onErr: (failure) {
        unawaited(source.dispose());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ordner konnte nicht ausgewählt werden: ${failure.message}')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quelle hinzufügen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SourceTypeCard(
            icon: Icons.folder_outlined,
            title: 'Lokaler Ordner',
            subtitle: 'Ordner auf diesem Gerät oder einem angeschlossenen Speicher',
            enabled: true,
            onTap: () => _addLocalFolder(context, ref),
          ),
          _SourceTypeCard(
            icon: Icons.dns_outlined,
            title: 'SMB-Netzwerkfreigabe',
            subtitle: 'NAS oder Windows-Freigabe im lokalen Netzwerk',
            enabled: true,
            onTap: () => context.push('/settings/sources/add/smb'),
          ),
          _SourceTypeCard(
            icon: Icons.cloud_outlined,
            title: 'Nextcloud',
            subtitle: 'Account oder öffentlicher Freigabe-Link',
            enabled: true,
            onTap: () => context.push('/settings/sources/add/nextcloud'),
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
