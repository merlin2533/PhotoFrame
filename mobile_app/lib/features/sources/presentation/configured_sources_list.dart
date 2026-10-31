import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/photo_source.dart';
import '../state/sources_providers.dart';

/// Compact, read-only list of the currently configured [PhotoSource]s, for
/// screens (onboarding, empty slideshow) that should show what is already
/// set up. Shows nothing while loading and a hint when there are none.
class ConfiguredSourcesList extends ConsumerWidget {
  const ConfiguredSourcesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value;
    if (sources == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (sources.isEmpty) {
      return Text('Noch keine Quelle eingerichtet.', style: theme.textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Eingerichtete Quellen', style: theme.textTheme.titleSmall),
        for (final s in sources)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_icon(s.type)),
            title: Text(s.displayName),
            subtitle: Text(s.type.name),
          ),
      ],
    );
  }

  static IconData _icon(SourceType type) {
    switch (type) {
      case SourceType.smb:
        return Icons.dns_outlined;
      case SourceType.nextcloud:
        return Icons.cloud_outlined;
      case SourceType.local:
        return Icons.folder_outlined;
      case SourceType.sharedAlbum:
        return Icons.people_outline;
      case SourceType.mock:
        return Icons.science_outlined;
    }
  }
}
