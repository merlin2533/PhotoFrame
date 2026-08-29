import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../slideshow/domain/always_on_controller.dart';
import '../state/settings_providers.dart';

class AlwaysOnSettingsScreen extends ConsumerWidget {
  const AlwaysOnSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Dauer-Modus')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Bestimmt, wann der Bildschirm dauerhaft an bleibt und nicht '
              'sperrt oder abschaltet - das Kernfeature eines digitalen '
              'Fotorahmens. Dauerbetrieb erhöht den Stromverbrauch spürbar.',
            ),
            const SizedBox(height: 16),
            RadioListTile<AlwaysOnMode>(
              title: const Text('Nur während der Diashow'),
              subtitle: const Text('Empfohlen - Standardverhalten'),
              value: AlwaysOnMode.duringSlideshowOnly,
              groupValue: settings.alwaysOnMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(alwaysOnMode: v)),
            ),
            RadioListTile<AlwaysOnMode>(
              title: const Text('Immer an'),
              subtitle: const Text(
                  'Nur empfohlen bei dauerhaftem Ladekabel-Betrieb'),
              value: AlwaysOnMode.always,
              groupValue: settings.alwaysOnMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(alwaysOnMode: v)),
            ),
            RadioListTile<AlwaysOnMode>(
              title: const Text('Nach Zeitplan'),
              subtitle: const Text(
                  'Während der Diashow an, außer im Nachtmodus-Zeitfenster'),
              value: AlwaysOnMode.scheduled,
              groupValue: settings.alwaysOnMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(alwaysOnMode: v)),
            ),
          ],
        ),
      ),
    );
  }
}
