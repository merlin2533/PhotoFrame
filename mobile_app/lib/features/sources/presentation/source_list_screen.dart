import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/photo_source.dart';
import '../domain/uploadable_photo_source.dart';
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
        onPressed: () => context.push('/settings/sources/add'),
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
                itemBuilder: (context, index) => _SourceTile(source: sources[index]),
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
    final canUpload =
        widget.source is UploadablePhotoSource && (widget.source as UploadablePhotoSource).canUpload;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(context),
        child: Icon(_iconForType(widget.source.type), color: Colors.white, size: 18),
      ),
      title: Text(widget.source.displayName),
      subtitle: Text(_subtitle()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canUpload) const Icon(Icons.upload_outlined, size: 18),
          IconButton(
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _testing ? null : _test,
            tooltip: 'Verbindung erneut testen',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Quelle entfernen',
            onPressed: () =>
                ref.read(sourcesProvider.notifier).removeById(widget.source.id),
          ),
        ],
      ),
    );
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
