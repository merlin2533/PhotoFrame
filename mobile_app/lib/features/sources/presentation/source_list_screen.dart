import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../index/source_indexer.dart';
import '../../settings/state/settings_providers.dart';
import '../domain/photo_source.dart';
import '../domain/uploadable_photo_source.dart';
import '../nextcloud/nextcloud_photo_source.dart';
import '../smb/smb_photo_source.dart';
import '../state/source_stats.dart';
import '../state/sources_providers.dart';

/// Lists configured [PhotoSource]s with a connection-status indicator and a
/// retry action, per `docs/PLAN.md`'s "Verbindungstests" section.
///
/// Works against the `PhotoSource` interface only, so it needs no changes
/// regardless of which concrete source type (`SmbPhotoSource`,
/// `NextcloudPhotoSource`, `LocalFolderSource`, `MockPhotoSource`, ...) was
/// added via `add_source_screen.dart`.
class SourceListScreen extends ConsumerWidget {
  const SourceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourcesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Quellen')),
      floatingActionButton: FloatingActionButton.extended(
        // Deliberately disabled while sourcesProvider isn't in a Data state
        // (still loading, or - critically - failed to load): SourcesController
        // persists the *entire* source list on every add()/removeById(), read
        // from `state.value ?? []`. Reaching "Quelle hinzufügen" while
        // the provider is in AsyncLoading/AsyncError would make add() treat
        // the not-yet-loaded (or unrecoverably failed) list as empty and
        // overwrite every previously configured source's persisted
        // descriptor with just the one being added - a real, reachable data
        // loss path found in review, not just a timing theoretical.
        onPressed: sourcesAsync.hasValue
            ? () => context.push('/settings/sources/add')
            : null,
        icon: const Icon(Icons.add),
        label: const Text('Quelle hinzufügen'),
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Quellen konnten nicht geladen werden: $error'),
        ),
        data: (sources) => sources.isEmpty
            ? const Center(child: Text('Noch keine Quelle konfiguriert.'))
            : ListView.separated(
                itemCount: sources.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _SourceTile(source: sources[index]),
              ),
      ),
    );
  }
}

class _SourceTile extends ConsumerStatefulWidget {
  const _SourceTile({required this.source});

  final PhotoSource source;

  @override
  ConsumerState<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends ConsumerState<_SourceTile> {
  bool _testing = false;
  ConnectionStatus? _status;
  String? _error;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _error = null;
    });
    final result = await widget.source.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      result.when(
        onOk: (status) => _status = status,
        onErr: (failure) => _error = failure.message,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_test());
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = widget.source is UploadablePhotoSource &&
        (widget.source as UploadablePhotoSource).canUpload;

    final stats = ref.watch(sourceStatsProvider)[widget.source.id];
    final indexStatus = ref.watch(sourceIndexerProvider)[widget.source.id];
    final editable = widget.source.type == SourceType.smb ||
        widget.source.type == SourceType.nextcloud;
    final disabled = ref.watch(settingsProvider.select(
            (s) => s.value?.disabledSourceIds.contains(widget.source.id))) ??
        false;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(context),
        child: Icon(_iconForType(widget.source.type),
            color: Colors.white, size: 18),
      ),
      title: Text(widget.source.displayName),
      subtitle: Text([
        disabled ? 'Deaktiviert (wird nicht abgespielt)' : _subtitle(),
        if (stats != null) _statsLine(stats),
        if (indexStatus != null) _indexLine(indexStatus),
      ].join('\n')),
      // Compact trailing: switch + overflow menu. Three separate icon buttons
      // overflowed the ListTile on phone widths and hid the switch.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canUpload) const Icon(Icons.upload_outlined, size: 18),
          Switch(
            value: !disabled,
            onChanged: (on) =>
                ref.read(settingsProvider.notifier).updateSettings((s) {
              final ids = s.disabledSourceIds
                  .where((i) => i != widget.source.id)
                  .toList();
              if (!on) ids.add(widget.source.id);
              return s.copyWith(disabledSourceIds: ids);
            }),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Details',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(widget.source.displayName),
                content: Text(_details()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'test') {
                _test();
              } else if (value == 'index') {
                unawaited(ref
                    .read(sourceIndexerProvider.notifier)
                    .buildIndex(widget.source));
              } else if (value == 'edit') {
                final path = widget.source.type == SourceType.smb
                    ? '/settings/sources/add/smb'
                    : '/settings/sources/add/nextcloud';
                context.push(path, extra: widget.source);
              } else if (value == 'remove') {
                ref.read(sourcesProvider.notifier).removeById(widget.source.id);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'test', child: Text('Verbindung erneut testen')),
              const PopupMenuItem(
                  value: 'index', child: Text('Index jetzt aufbauen')),
              if (editable)
                const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
              const PopupMenuItem(
                  value: 'remove', child: Text('Quelle entfernen')),
            ],
          ),
        ],
      ),
    );
  }

  /// Index status line: running count, finished count, or the error.
  String _indexLine(SourceIndexStatus status) {
    if (status.error != null) return 'Index-Fehler: ${status.error}';
    if (status.running) {
      return 'Index läuft … ${status.imageCount} Bilder gefunden';
    }
    return 'Index: ${status.imageCount} Bilder';
  }

  /// Directory details without network addresses (no IP/host is shown).
  String _details() {
    final source = widget.source;
    if (source is SmbPhotoSource) {
      final folder = source.config.rootPath;
      return 'Freigabe: ${source.config.share}\n'
          'Ordner: ${folder.isEmpty ? '(Hauptordner)' : folder}';
    }
    if (source is NextcloudPhotoSource) {
      final folder = source.config.rootPath;
      return 'Ordner: ${folder.isEmpty ? '(Hauptordner)' : folder}';
    }
    return widget.source.type.name;
  }

  String _statsLine(SourceStats stats) {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = stats.updatedAt;
    return '${stats.imageCount} Bilder · Stand ${two(t.day)}.${two(t.month)}. '
        '${two(t.hour)}:${two(t.minute)}';
  }

  String _subtitle() {
    if (_testing) return 'Verbindung wird geprüft…';
    if (_error != null) return 'Fehler: $_error';
    if (_status != null) {
      return _status!.reachable
          ? 'Verbunden${_status!.detail != null ? ' - ${_status!.detail}' : ''}'
          : 'Nicht erreichbar';
    }
    return widget.source.type.name;
  }

  Color _statusColor(BuildContext context) {
    if (_testing) return Colors.grey;
    if (_error != null || _status?.reachable == false) return Colors.red;
    if (_status?.reachable == true) return Colors.green;
    return Colors.grey;
  }

  IconData _iconForType(SourceType type) {
    switch (type) {
      case SourceType.smb:
        return Icons.dns_outlined;
      case SourceType.nextcloud:
        return Icons.cloud_outlined;
      case SourceType.local:
        return Icons.folder_outlined;
      case SourceType.sharedAlbum:
        return Icons.people_outline;
      case SourceType.mock:
        return Icons.science_outlined;
    }
  }
}
