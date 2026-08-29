import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Friendly full-screen state shown instead of the slideshow when no
/// [PhotoSource] is configured yet (or the configured sources yielded no
/// items), rather than a blank/black screen.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                'Noch keine Bilder',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Füge eine Bildquelle hinzu, damit die Diashow starten kann - '
                'oder lass dich vom Setup-Guide durch die Einrichtung führen.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/settings/sources/add'),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Quelle hinzufügen'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/onboarding'),
                icon: const Icon(Icons.help_outline),
                label: const Text('Setup-Guide öffnen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
