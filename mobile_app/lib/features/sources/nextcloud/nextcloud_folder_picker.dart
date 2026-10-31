import 'package:flutter/material.dart';

import '../domain/photo_folder.dart';
import 'nextcloud_photo_source.dart';

/// Lets the user browse the folders of a connected Nextcloud and tick one or
/// several of them. Returns the chosen paths (relative to the WebDAV root),
/// or `null` if cancelled.
Future<List<String>?> showNextcloudFolderPicker(
  BuildContext context, {
  required NextcloudPhotoSource source,
  List<String> initiallySelected = const [],
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.85,
      child:
          _FolderPicker(source: source, initiallySelected: initiallySelected),
    ),
  );
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({required this.source, required this.initiallySelected});

  final NextcloudPhotoSource source;
  final List<String> initiallySelected;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late final Set<String> _selected = {...widget.initiallySelected};
  String _path = '';
  List<PhotoFolder>? _folders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _folders = null;
      _error = null;
    });
    final folders = <PhotoFolder>[];
    String? error;
    final parent = _path.isEmpty
        ? null
        : PhotoFolder(id: _path, name: _path.split('/').last, path: _path);
    await for (final r in widget.source.listFolders(parent: parent)) {
      final f = r.valueOrNull;
      if (f != null) {
        folders.add(f);
      } else {
        error = r.failureOrNull?.message;
      }
    }
    folders
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _error = error;
    });
  }

  void _enter(String path) {
    _path = path;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    return Column(
      children: [
        ListTile(
          title: Text(_path.isEmpty ? 'Hauptordner' : _path),
          subtitle: Text('${_selected.length} Ordner ausgewählt'),
          leading: _path.isEmpty
              ? const Icon(Icons.cloud_outlined)
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    final i = _path.lastIndexOf('/');
                    _enter(i < 0 ? '' : _path.substring(0, i));
                  },
                ),
        ),
        const Divider(height: 1),
        Expanded(
          child: folders == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : folders.isEmpty
                      ? const Center(child: Text('Keine Unterordner'))
                      : ListView(
                          children: [
                            for (final f in folders)
                              ListTile(
                                leading: Checkbox(
                                  value: _selected.contains(f.path),
                                  onChanged: (on) => setState(() {
                                    if (on == true) {
                                      _selected.add(f.path);
                                    } else {
                                      _selected.remove(f.path);
                                    }
                                  }),
                                ),
                                title: Text(f.name),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _enter(f.path),
                              ),
                          ],
                        ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected.toList()..sort()),
                  child: const Text('Übernehmen'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
