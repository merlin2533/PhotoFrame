import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Landing screen: quick actions to start the slideshow, manage sources, or
/// open settings. Kept intentionally minimal - the slideshow itself is the
/// app's primary surface once configured (see `EmptyStateView` for the
/// unconfigured case, shown by `/slideshow` when no source has items yet).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PhotoFrame')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => context.goNamed('slideshow'),
              icon: const Icon(Icons.slideshow_outlined),
              label: const Text('Diashow starten'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.pushNamed('settings'),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Einstellungen'),
            ),
          ],
        ),
      ),
    );
  }
}
