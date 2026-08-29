import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cacheInfo = ref.watch(cacheInfoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cacheScreenTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonError(e.toString()))),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.cacheUsedStorageLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: cacheInfo.usedFraction),
                    const SizedBox(height: 8),
                    Text(
                      l10n.cacheUsedOfLimit(
                        _formatBytes(cacheInfo.usedBytes),
                        _formatBytes(cacheInfo.limitBytes),
                      ),
                    ),
                    // TODO(parallel-agent/ImageCacheManager): this reads a
                    // placeholder value until the real cache manager lands
                    // (see settings_providers.dart -> cacheInfoProvider).
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(l10n.cacheLimitLabel(_formatBytes(settings.cacheLimitBytes)),
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
            Text(
              l10n.cacheLimitDeviceCapHint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () {
                // TODO(parallel-agent/ImageCacheManager): wire to the real
                // cache clear once it exists; for now just confirm to the
                // user that this is a placeholder action.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.cacheClearedSnackbar)),
                );
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.cacheClearButton),
            ),
          ],
        ),
      ),
    );
  }
}
