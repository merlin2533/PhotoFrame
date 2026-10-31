import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../cache/small_photo_cache.dart';
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
              onChanged: (v) => notifier.updateSettings(
                  (s) => s.copyWith(cacheLimitBytes: v.round())),
            ),
            Text(
              l10n.cacheLimitDeviceCapHint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Text('Dias pro Batch: ${settings.smallPhotoBatchSize}',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.smallPhotoBatchSize.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              label: '${settings.smallPhotoBatchSize}',
              onChanged: (v) => notifier.updateSettings(
                  (s) => s.copyWith(smallPhotoBatchSize: v.round())),
            ),
            const Text(
              'So viele Fotos werden pro Durchlauf eingereiht und dann '
              'einzeln nacheinander verkleinert.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () async {
                await ref.read(smallPhotoCacheProvider).clear();
                ref.read(smallPhotoWorkerProvider.notifier).reset();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Verkleinerte Dias gelöscht – sie werden '
                          'beim nächsten Index-Lauf neu erstellt.')),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Verkleinerte Dias neu aufbauen'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () async {
                await ref.read(imageCacheManagerProvider).clear();
                // The manager mutates its own internal LRU state without
                // notifying Riverpod (it isn't a ChangeNotifier/Notifier),
                // so `cacheInfoProvider` needs an explicit nudge to re-read
                // the now-empty size.
                ref.invalidate(cacheInfoProvider);
                if (!context.mounted) return;
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
