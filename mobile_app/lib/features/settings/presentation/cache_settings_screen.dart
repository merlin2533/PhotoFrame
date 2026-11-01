import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../cache/small_photo_cache.dart';
import '../../cache/small_photo_usage_provider.dart';
import '../../sources/domain/photo_source.dart';
import '../../sources/state/sources_providers.dart';
import '../state/settings_providers.dart';

class CacheSettingsScreen extends ConsumerWidget {
  const CacheSettingsScreen({super.key});

  static String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
    return '${(bytes / kb).toStringAsFixed(0)} KB';
  }

  /// Runs after the small-photo cache was changed: the usage numbers are read
  /// again and the worker forgets what it prepared, so the next index run
  /// creates the deleted copies again instead of skipping them.
  void _cacheChanged(WidgetRef ref) {
    ref.read(smallPhotoWorkerProvider.notifier).reset();
    ref.invalidate(smallPhotoCacheUsageProvider);
  }

  Future<void> _deleteSource(
    BuildContext context,
    WidgetRef ref, {
    required String? sourceId,
    required String name,
    required int count,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cacheDeleteSourceTitle),
        content: Text(sourceId == null
            ? l10n.cacheDeleteUnassignedBody(count)
            : l10n.cacheDeleteSourceBody(count, name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cacheDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cache = ref.read(smallPhotoCacheProvider);
    final deleted = sourceId == null
        ? await cache.deleteUnassigned(_knownSourceIds(ref))
        : await cache.deleteForSource(sourceId);
    _cacheChanged(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.cacheDeletedSnackbar(deleted))),
    );
  }

  Iterable<String> _knownSourceIds(WidgetRef ref) =>
      (ref.read(sourcesProvider).value ?? const <PhotoSource>[])
          .map((source) => source.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final usageAsync = ref.watch(smallPhotoCacheUsageProvider);
    final sourceNames = {
      for (final source
          in ref.watch(sourcesProvider).value ?? const <PhotoSource>[])
        source.id: source.displayName,
    };

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
                child: usageAsync.when(
                  loading: () => const Center(
                      child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  )),
                  error: (e, _) => Text(l10n.commonError(e.toString())),
                  data: (usage) {
                    final limit = settings.cacheLimitBytes;
                    final fraction = limit <= 0
                        ? 0.0
                        : (usage.totalBytes / limit).clamp(0, 1).toDouble();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.cacheUsedStorageLabel,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: fraction),
                        const SizedBox(height: 8),
                        Text(
                          l10n.cacheUsedOfLimit(
                            _formatBytes(usage.totalBytes),
                            _formatBytes(limit),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(l10n.cacheImageCount(usage.count)),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(l10n.cacheBySourceTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            usageAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (usage) => Card(
                child: Column(
                  children: [
                    for (final entry in usage.bySource)
                      ListTile(
                        title:
                            Text(sourceNames[entry.sourceId] ?? entry.sourceId),
                        subtitle: Text(l10n.cacheSourceUsage(
                            entry.count, _formatBytes(entry.bytes))),
                        trailing: IconButton(
                          tooltip: l10n.cacheDeleteSourceTooltip,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: entry.count == 0
                              ? null
                              : () => _deleteSource(
                                    context,
                                    ref,
                                    sourceId: entry.sourceId,
                                    name: sourceNames[entry.sourceId] ??
                                        entry.sourceId,
                                    count: entry.count,
                                  ),
                        ),
                      ),
                    if (usage.unassignedCount > 0)
                      ListTile(
                        title: Text(l10n.cacheUnknownSource),
                        subtitle: Text(
                          '${l10n.cacheUnknownSourceHint}\n'
                          '${l10n.cacheSourceUsage(usage.unassignedCount, _formatBytes(usage.unassignedBytes))}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: l10n.cacheDeleteSourceTooltip,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteSource(
                            context,
                            ref,
                            sourceId: null,
                            name: l10n.cacheUnknownSource,
                            count: usage.unassignedCount,
                          ),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur geprüfte, verkleinerte Fotos anzeigen'),
              subtitle: const Text(
                  'Zeigt nie das heruntergeladene Original, das beschädigt '
                  'sein kann. Fotos erscheinen, sobald ihre verkleinerte '
                  'Kopie fertig und geprüft ist.'),
              value: settings.onlyPreparedPhotos,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(onlyPreparedPhotos: v)),
            ),
            const SizedBox(height: 16),
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
                _cacheChanged(ref);
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
                // Deletes every prepared copy (all sources), the same as
                // "Verkleinerte Dias neu aufbauen" above.
                await ref.read(smallPhotoCacheProvider).clear();
                await ref.read(imageCacheManagerProvider).clear();
                _cacheChanged(ref);
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
