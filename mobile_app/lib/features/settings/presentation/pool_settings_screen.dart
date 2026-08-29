import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_providers.dart';

/// Settings for the "Working-Set Pool" described in `docs/PLAN.md`
/// ("Arbeitsmenge (Working-Set-Pool) & Auffüll-Job").
class PoolSettingsScreen extends ConsumerWidget {
  const PoolSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Pool/Index')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Die Diashow zieht Bilder aus einer begrenzten "Arbeitsmenge" '
              'statt aus dem gesamten Index, damit neue Fotos zuverlässig '
              'zeitnah auftauchen.',
            ),
            const SizedBox(height: 16),
            Text('Pool-Größe: ${settings.poolTargetSize}',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.poolTargetSize.toDouble(),
              min: 50,
              max: 5000,
              divisions: 99,
              label: '${settings.poolTargetSize}',
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(poolTargetSize: v.round())),
            ),
            const SizedBox(height: 16),
            Text('Auffüll-Intervall: alle ${settings.poolRefillIntervalHours} h',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.poolRefillIntervalHours.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              label: '${settings.poolRefillIntervalHours} h',
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(poolRefillIntervalHours: v.round())),
            ),
            const SizedBox(height: 16),
            Text(
              'Anteil neuer Bilder (newImageQuota): '
              '${(settings.poolNewImageQuota * 100).round()}%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: settings.poolNewImageQuota,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(poolNewImageQuota: v)),
            ),
          ],
        ),
      ),
    );
  }
}
