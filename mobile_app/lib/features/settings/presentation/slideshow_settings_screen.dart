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
            RadioGroup<DisplayMode>(
              groupValue: settings.displayMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(displayMode: v)),
              child: const Column(
                children: [
                  RadioListTile<DisplayMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Einpassen (contain)'),
                    value: DisplayMode.contain,
                  ),
                  RadioListTile<DisplayMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Ausfüllen (cover)'),
                    value: DisplayMode.cover,
                  ),
                  RadioListTile<DisplayMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Unscharfer Hintergrund'),
                    subtitle:
                        Text('Löst Hochkantbilder ohne schwarze Balken'),
                    value: DisplayMode.blurredBackdrop,
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            Text('Übergänge', style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<SlideshowTransition>(
              groupValue: settings.transition,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(transition: v)),
              child: const Column(
                children: [
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Überblenden (fade)'),
                    value: SlideshowTransition.fade,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Schieben (slide)'),
                    value: SlideshowTransition.slide,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Kein Übergang'),
                    value: SlideshowTransition.none,
                  ),
                ],
              ),
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
            const Divider(height: 32),
            Text('Favoriten & Datum', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur Favoriten zeigen'),
              subtitle: const Text(
                  'Diashow speist sich nur aus favorisierten Bildern'),
              value: settings.favoritesOnlyMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(favoritesOnlyMode: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Heute vor N Jahren bevorzugen'),
              subtitle: const Text(
                  'Bevorzugt Bilder von diesem Tag in der Vergangenheit zeigen'),
              value: settings.preferOnThisDayEnabled,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(preferOnThisDayEnabled: v)),
            ),
          ],
        ),
      ),
    );
  }
}
