import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../slideshow/domain/slideshow_config.dart';
import '../domain/app_settings.dart';
import '../state/settings_providers.dart';

class SlideshowSettingsScreen extends ConsumerWidget {
  const SlideshowSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Diashow')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Intervall: ${settings.intervalSeconds} s',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.intervalSeconds.toDouble(),
              min: 3,
              max: 120,
              divisions: 117,
              label: '${settings.intervalSeconds} s',
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(intervalSeconds: v.round())),
            ),
            const Divider(height: 32),
            Text('Overlays', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ordnername/Quelle anzeigen'),
              value: settings.showSourceLabel,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(showSourceLabel: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Uhr anzeigen'),
              value: settings.showClock,
              onChanged: (v) => notifier.updateSettings((s) => s.copyWith(showClock: v)),
            ),
            const Divider(height: 32),
            Text('Anzeige-Modus', style: Theme.of(context).textTheme.titleMedium),
            RadioListTile<DisplayMode>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Einpassen (contain)'),
              value: DisplayMode.contain,
              groupValue: settings.displayMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(displayMode: v)),
            ),
            RadioListTile<DisplayMode>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ausfüllen (cover)'),
              value: DisplayMode.cover,
              groupValue: settings.displayMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(displayMode: v)),
            ),
            RadioListTile<DisplayMode>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unscharfer Hintergrund'),
              subtitle: const Text('Löst Hochkantbilder ohne schwarze Balken'),
              value: DisplayMode.blurredBackdrop,
              groupValue: settings.displayMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(displayMode: v)),
            ),
            const Divider(height: 32),
            Text('Übergänge', style: Theme.of(context).textTheme.titleMedium),
            RadioListTile<SlideshowTransition>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Überblenden (fade)'),
              value: SlideshowTransition.fade,
              groupValue: settings.transition,
              onChanged: (v) => notifier.updateSettings((s) => s.copyWith(transition: v)),
            ),
            RadioListTile<SlideshowTransition>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Schieben (slide)'),
              value: SlideshowTransition.slide,
              groupValue: settings.transition,
              onChanged: (v) => notifier.updateSettings((s) => s.copyWith(transition: v)),
            ),
            RadioListTile<SlideshowTransition>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kein Übergang'),
              value: SlideshowTransition.none,
              groupValue: settings.transition,
              onChanged: (v) => notifier.updateSettings((s) => s.copyWith(transition: v)),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ken-Burns-Effekt'),
              subtitle: const Text('Langsamer Zoom/Pan auf dem Bild'),
              value: settings.kenBurnsEnabled,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(kenBurnsEnabled: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hochkant-Paar-Layout'),
              subtitle: const Text(
                  'Zwei aufeinanderfolgende Hochkantbilder nebeneinander'),
              value: settings.portraitPairLayoutEnabled,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(portraitPairLayoutEnabled: v)),
            ),
          ],
        ),
      ),
    );
  }
}
