import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/photo_folder.dart';
import '../domain/photo_source.dart';
import '../state/sources_providers.dart';
import 'immich_config_form_model.dart';
import 'immich_photo_source.dart';

/// Configuration screen for an Immich source: server URL and API key, plus an
/// optional album selection. Without a selection the source covers all albums
/// of the server; with one, one source per selected album is created (as the
/// Nextcloud form does per folder).
class ImmichConfigFormScreen extends ConsumerStatefulWidget {
  const ImmichConfigFormScreen({super.key, this.editing});

  /// The source being edited: prefilled, and replaced on save. `null` for a
  /// new source.
  final PhotoSource? editing;

  @override
  ConsumerState<ImmichConfigFormScreen> createState() =>
      _ImmichConfigFormScreenState();
}

class _ImmichConfigFormScreenState
    extends ConsumerState<ImmichConfigFormScreen> {
  final _serverUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _obscureApiKey = true;
  bool _submitted = false;
  bool _testing = false;
  bool _loadingAlbums = false;
  ConnectionStatus? _lastStatus;
  String? _lastError;

  /// All albums of the server once loaded, `null` before "Alben laden".
  List<PhotoFolder>? _albums;

  /// Selected albums, album id -> album name. Empty means all albums.
  final Map<String, String> _selectedAlbums = {};

  ImmichConfigFormModel get _model => ImmichConfigFormModel(
        serverUrl: _serverUrlController.text,
        apiKey: _apiKeyController.text,
      );

  @override
  void initState() {
    super.initState();
    final source = widget.editing;
    if (source is! ImmichPhotoSource) return;
    final c = source.config;
    _serverUrlController.text = c.serverUrl;
    if (c.albumId.isNotEmpty) {
      _selectedAlbums[c.albumId] =
          c.albumName.isEmpty ? c.albumId : c.albumName;
    }
    unawaited(() async {
      final store = ref.read(secureCredentialStoreProvider);
      final key = await store.read(source.id, 'password');
      if (key == null || !mounted) return;
      _apiKeyController.text = key;
    }());
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _submitted = true);
    if (!_model.isValid) return;

    setState(() {
      _testing = true;
      _lastStatus = null;
      _lastError = null;
    });

    final probe = ImmichPhotoSource(
      id: 'probe',
      config: ImmichSourceConfig.fromForm(_model),
    );
    final result = await probe.testConnection();
    await probe.dispose();

    if (!mounted) return;
    setState(() {
      _testing = false;
      result.when(
        onOk: (status) => _lastStatus = status,
        onErr: (failure) => _lastError = failure.message,
      );
    });
  }

  Future<void> _loadAlbums() async {
    setState(() => _submitted = true);
    if (!_model.isValid) return;

    setState(() {
      _loadingAlbums = true;
      _lastError = null;
    });

    final probe = ImmichPhotoSource(
      id: 'albums',
      config: ImmichSourceConfig.fromForm(_model),
    );
    final albums = <PhotoFolder>[];
    String? error;
    await for (final r in probe.listFolders()) {
      final folder = r.valueOrNull;
      if (folder != null) {
        albums.add(folder);
      } else {
        error = r.failureOrNull?.message;
      }
    }
    await probe.dispose();

    if (!mounted) return;
    albums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _loadingAlbums = false;
      if (error == null) {
        _albums = albums;
      } else {
        _lastError = error;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_model.isValid) return;

    // `fromForm` normalizes itself; the raw model is passed on purpose.
    final store = ref.read(secureCredentialStoreProvider);
    final editing = widget.editing;
    if (editing != null) {
      await ref.read(sourcesProvider.notifier).removeById(editing.id);
    }

    // No album selected = one source covering all albums.
    final List<MapEntry<String, String>> targets = _selectedAlbums.isEmpty
        ? [const MapEntry('', '')]
        : _selectedAlbums.entries.toList();

    try {
      for (final target in targets) {
        final id = ref.read(sourceIdGeneratorProvider).v4();
        final config = ImmichSourceConfig.fromForm(
          _model,
          albumId: target.key,
          albumName: target.value,
        );
        final source = ImmichPhotoSource(
          id: id,
          config: config,
          displayName:
              target.key.isEmpty ? 'Immich' : 'Immich: ${target.value}',
        );
        // Secret goes to the keychain first, then the descriptor is persisted
        // by `add()` (same order as the Nextcloud form).
        await store.write(id, 'password', config.apiKey);
        await ref.read(sourcesProvider.notifier).add(source);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final errors = _submitted ? _model.validate() : const <String, String>{};
    final albums = _albums;

    return Scaffold(
      appBar: AppBar(title: const Text('Immich')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _serverUrlController,
            decoration: InputDecoration(
              labelText: 'Server-URL',
              hintText: 'https://immich.example.com',
              errorText: errors['serverUrl'],
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: 'API-Schlüssel',
              helperText:
                  'Erstelle einen Schlüssel in Immich unter Kontoeinstellungen -> API-Schlüssel. '
                  'Er braucht Leserechte für Alben und Fotos.',
              errorText: errors['apiKey'],
              suffixIcon: IconButton(
                icon: Icon(_obscureApiKey
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: const Text('Verbindung testen'),
          ),
          if (_lastStatus != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.green.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_lastStatus!.detail ?? 'Verbunden'),
              ),
            ),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_lastError!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadingAlbums ? null : _loadAlbums,
            icon: _loadingAlbums
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_album_outlined),
            label: Text(albums == null ? 'Alben laden' : 'Alben neu laden'),
          ),
          if (albums != null) ...[
            const SizedBox(height: 8),
            if (albums.isEmpty)
              const Text(
                  'Keine Alben gefunden. Ohne Auswahl werden alle Fotos des Servers verwendet.')
            else ...[
              Text(_selectedAlbums.isEmpty
                  ? 'Keine Auswahl: alle Alben werden verwendet.'
                  : '${_selectedAlbums.length} Album(en) ausgewählt'),
              for (final album in albums)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selectedAlbums.containsKey(album.id),
                  title: Text(album.name),
                  onChanged: (on) => setState(() {
                    if (on == true) {
                      _selectedAlbums[album.id] = album.name;
                    } else {
                      _selectedAlbums.remove(album.id);
                    }
                  }),
                ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Quelle speichern'),
          ),
        ],
      ),
    );
  }
}
