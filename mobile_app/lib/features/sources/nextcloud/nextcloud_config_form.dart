import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../index/background_jobs.dart';
import '../domain/photo_source.dart';
import '../state/sources_providers.dart';
import 'nextcloud_config_form_model.dart';
import 'nextcloud_folder_picker.dart';
import 'nextcloud_photo_source.dart';

/// Configuration screen for a Nextcloud source, supporting both auth modes
/// modelled by [NextcloudConfigFormModel]: an account (WebDAV login) or a
/// public share link.
class NextcloudConfigFormScreen extends ConsumerStatefulWidget {
  const NextcloudConfigFormScreen({super.key, this.editing});

  /// The source being edited: prefilled, and replaced on save. `null` for a
  /// new source.
  final PhotoSource? editing;

  @override
  ConsumerState<NextcloudConfigFormScreen> createState() =>
      _NextcloudConfigFormScreenState();
}

class _NextcloudConfigFormScreenState
    extends ConsumerState<NextcloudConfigFormScreen> {
  NextcloudAuthKind _authKind = NextcloudAuthKind.account;

  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _appPasswordController = TextEditingController();
  final _shareTokenController = TextEditingController();
  final _sharePasswordController = TextEditingController();
  final _folderPathController = TextEditingController();

  bool _obscureAppPassword = true;
  bool _obscureSharePassword = true;
  bool _testing = false;
  bool _submitted = false;
  List<String> _selectedFolders = [];
  ConnectionStatus? _lastStatus;
  bool? _lastCanUpload;
  String? _lastError;

  NextcloudConfigFormModel get _model => NextcloudConfigFormModel(
        authKind: _authKind,
        serverUrl: _serverUrlController.text,
        username: _usernameController.text,
        appPassword: _appPasswordController.text,
        shareToken: _shareTokenController.text,
        sharePassword: _sharePasswordController.text,
        folderPath: _folderPathController.text,
      );

  @override
  void initState() {
    super.initState();
    final source = widget.editing;
    if (source is! NextcloudPhotoSource) return;
    final c = source.config;
    _folderPathController.text = c.rootPath;
    if (c.isShareLink) {
      _authKind = NextcloudAuthKind.shareLink;
      _serverUrlController.text =
          c.davBaseUrl.replaceAll('/public.php/webdav', '');
      _shareTokenController.text = c.authUsername;
    } else {
      _authKind = NextcloudAuthKind.account;
      _serverUrlController.text =
          c.davBaseUrl.replaceAll(RegExp(r'/remote\.php/dav/files/.*$'), '');
      _usernameController.text = c.authUsername;
    }
    unawaited(() async {
      final store = ref.read(secureCredentialStoreProvider);
      final pw = await store.read(source.id, 'password');
      if (pw == null || !mounted) return;
      if (c.isShareLink) {
        _sharePasswordController.text = pw;
      } else {
        _appPasswordController.text = pw;
      }
    }());
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _appPasswordController.dispose();
    _shareTokenController.dispose();
    _sharePasswordController.dispose();
    _folderPathController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _submitted = true);
    // Validate the raw input: `normalized()` already reduced a pasted share
    // link to its bare token, which the share-link validation rejects.
    if (!_model.isValid) return;

    setState(() {
      _testing = true;
      _lastStatus = null;
      _lastCanUpload = null;
      _lastError = null;
    });

    final config = NextcloudSourceConfig.fromForm(_model);
    final probe = NextcloudPhotoSource(id: 'probe', config: config);
    final result = await probe.testConnection();
    final canUpload = probe.canUpload;
    await probe.dispose();

    if (!mounted) return;
    setState(() {
      _testing = false;
      result.when(
        onOk: (status) {
          _lastStatus = status;
          _lastCanUpload = canUpload;
        },
        onErr: (failure) => _lastError = failure.message,
      );
    });
  }

  /// Splits a pasted share link into the server and token fields and drops
  /// everything that doesn't belong (query, `/download`, trailing slashes).
  void _onLinkFieldChanged(String text) {
    final parsed = NextcloudConfigFormModel.parseShareLink(text);
    if (parsed == null) return;
    setState(() {
      _serverUrlController.text = parsed.serverUrl;
      _shareTokenController.text = parsed.token;
    });
  }

  /// Cuts app paths and query off a pasted Nextcloud URL (account mode).
  void _onAccountServerChanged(String text) {
    final cleaned = NextcloudConfigFormModel.cleanServerUrl(text);
    if (cleaned != text.trim() && text.length - cleaned.length > 1) {
      _serverUrlController.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
  }

  Future<void> _pickFolders() async {
    if (!_model.isValid) return;
    final config =
        NextcloudSourceConfig.fromForm(_model.copyWith(folderPath: ''));
    final probe = NextcloudPhotoSource(id: 'browse', config: config);
    final picked = await showNextcloudFolderPicker(
      context,
      source: probe,
      initiallySelected: _selectedFolders,
    );
    await probe.dispose();
    if (picked != null && mounted) setState(() => _selectedFolders = picked);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_model.isValid) {
      setState(() {});
      return;
    }
    // `fromForm` normalizes itself - pass the raw model (normalizing twice
    // loses the server URL of a pasted share link).
    final folders = _selectedFolders.isNotEmpty
        ? _selectedFolders
        : [_model.normalized().folderPath];
    final store = ref.read(secureCredentialStoreProvider);
    final editing = widget.editing;
    if (editing != null) {
      await ref.read(sourcesProvider.notifier).removeById(editing.id);
    }

    try {
      for (final folder in folders) {
        final id = ref.read(sourceIdGeneratorProvider).v4();
        final config =
            NextcloudSourceConfig.fromForm(_model.copyWith(folderPath: folder));
        final source = NextcloudPhotoSource(
          id: id,
          config: config,
          displayName: folder.isEmpty ? 'Nextcloud' : 'Nextcloud: $folder',
        );
        // Persist the secret in the secure keychain first (see
        // SecureCredentialStore); awaited so it has landed before `add()`
        // persists the descriptor.
        if (config.authPassword.isNotEmpty) {
          await store.write(id, 'password', config.authPassword);
        }
        await ref.read(sourcesProvider.notifier).add(source);
        unawaited(ref.read(backgroundJobsProvider.notifier).runOnce());
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

    return Scaffold(
      appBar: AppBar(title: const Text('Nextcloud')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<NextcloudAuthKind>(
            segments: const [
              ButtonSegment(
                value: NextcloudAuthKind.account,
                label: Text('Account'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: NextcloudAuthKind.shareLink,
                label: Text('Öffentlicher Link'),
                icon: Icon(Icons.link),
              ),
            ],
            selected: {_authKind},
            onSelectionChanged: (selection) {
              setState(() {
                _authKind = selection.first;
                _lastStatus = null;
                _lastCanUpload = null;
                _lastError = null;
              });
            },
          ),
          const SizedBox(height: 16),
          if (_authKind == NextcloudAuthKind.account) ...[
            TextField(
              controller: _serverUrlController,
              onChanged: _onAccountServerChanged,
              decoration: InputDecoration(
                labelText: 'Server-URL',
                hintText: 'https://cloud.example.com',
                errorText: errors['serverUrl'],
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Benutzername',
                errorText: errors['username'],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _appPasswordController,
              obscureText: _obscureAppPassword,
              decoration: InputDecoration(
                labelText: 'App-Passwort',
                helperText:
                    'Erstelle ein App-Passwort unter Nextcloud-Einstellungen -> Sicherheit, '
                    'nicht dein eigentliches Account-Passwort.',
                errorText: errors['appPassword'],
                suffixIcon: IconButton(
                  icon: Icon(_obscureAppPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(
                      () => _obscureAppPassword = !_obscureAppPassword),
                ),
              ),
            ),
          ] else ...[
            TextField(
              controller: _serverUrlController,
              onChanged: _onLinkFieldChanged,
              decoration: InputDecoration(
                labelText: 'Server-URL',
                hintText: 'https://cloud.example.com',
                helperText:
                    'Den kompletten Freigabe-Link hier oder unten einfügen - er wird automatisch in Server und Token zerlegt.',
                errorText: errors['serverUrl'],
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _shareTokenController,
              onChanged: _onLinkFieldChanged,
              decoration: InputDecoration(
                labelText: 'Freigabe-Token',
                hintText: 'AbCdEf',
                errorText: errors['shareToken'],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sharePasswordController,
              obscureText: _obscureSharePassword,
              decoration: InputDecoration(
                labelText: 'Link-Passwort (falls gesetzt)',
                suffixIcon: IconButton(
                  icon: Icon(_obscureSharePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(
                      () => _obscureSharePassword = !_obscureSharePassword),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _folderPathController,
            decoration: const InputDecoration(
              labelText: 'Unterordner (optional)',
              hintText: 'z. B. Fotos/Rahmen',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickFolders,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(_selectedFolders.isEmpty
                ? 'Ordner auswählen'
                : '${_selectedFolders.length} Ordner ausgewählt'),
          ),
          if (_selectedFolders.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final f in _selectedFolders)
                  Chip(
                    label: Text(f),
                    onDeleted: () => setState(() => _selectedFolders.remove(f)),
                  ),
              ],
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
                child: Text(
                  _lastCanUpload == true
                      ? 'Verbunden - Lese- und Schreibzugriff erkannt'
                      : 'Verbunden - nur Lesezugriff (kein Upload möglich)',
                ),
              ),
            ),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_lastError!),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Erneut versuchen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
