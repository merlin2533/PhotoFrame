import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Placeholder landing screen. Will later show configured sources and
/// quick actions (start slideshow, manage sources, open settings).
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
            const Text('PhotoFrame - placeholder home screen'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.goNamed('slideshow'),
              child: const Text('Start slideshow'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.goNamed('settings'),
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
