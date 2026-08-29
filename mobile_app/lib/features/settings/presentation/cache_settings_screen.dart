import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_providers.dart';

class CacheSettingsScreen extends ConsumerWidget {
  const CacheSettingsScreen({super.key});

  static String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cacheInfo = ref.watch(cacheInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cache-Verwaltung')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Belegter Speicher', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: cacheInfo.usedFraction),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatBytes(cacheInfo.usedBytes)} von '
                      '${_formatBytes(cacheInfo.limitBytes)} belegt',
                    ),
                    // TODO(parallel-agent/ImageCacheManager): this reads a
                    // placeholder value until the real cache manager lands
                    // (see settings_providers.dart -> cacheInfoProvider).
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Cache-Limit: ${_formatBytes(settings.cacheLimitBytes)}',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.cacheLimitBytes.toDouble(),
              min: 100 * 1024 * 1024,
              max: 5 * 1024 * 1024 * 1024,
              divisions: 49,
              label: _formatBytes(settings.cacheLimitBytes),
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(cacheLimitBytes: v.round())),
            ),
            const Text(
              'Das Limit wird zusätzlich gegen den tatsächlich freien '
              'Gerätespeicher gedeckelt (mind. 1 GB/10% Reserve), sobald der '
              'reale ImageCacheManager verfügbar ist.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () {
                // TODO(parallel-agent/ImageCacheManager): wire to the real
                // cache clear once it exists; for now just confirm to the
                // user that this is a placeholder action.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache geleert (Platzhalter)')),
                );
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Cache leeren'),
            ),
          ],
        ),
      ),
    );
  }
}
