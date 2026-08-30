import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/photo_source.dart';
import '../state/sources_providers.dart';
import 'nextcloud_config_form_model.dart';
import 'nextcloud_photo_source.dart';

/// Configuration screen for a Nextcloud source, supporting both auth modes
/// modelled by [NextcloudConfigFormModel]: an account (WebDAV login) or a
/// public share link.
class NextcloudConfigFormScreen extends ConsumerStatefulWidget {
  const NextcloudConfigFormScreen({super.key});

  @override
  ConsumerState<NextcloudConfigFormScreen> createState() => _NextcloudConfigFormScreenState();
}

class _NextcloudConfigFormScreenState extends ConsumerState<NextcloudConfigFormScreen> {
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
    final normalized = _model.normalized();
    if (!normalized.isValid) return;

    setState(() {
      _testing = true;
      _lastStatus = null;
      _lastCanUpload = null;
      _lastError = null;
    });

    final config = NextcloudSourceConfig.fromForm(normalized);
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

  void _save() {
    setState(() => _submitted = true);
    final normalized = _model.normalized();
    if (!normalized.isValid) {
      setState(() {});
      return;
    }

    final id = ref.read(sourceIdGeneratorProvider).v4();
    final config = NextcloudSourceConfig.fromForm(normalized);
    final source = NextcloudPhotoSource(id: id, config: config);

    // Persist the secret (app password or share-link password) in the
    // secure keychain - see SecureCredentialStore's doc comment. As with
    // the SMB form, the rest of the (non-secret) source configuration isn't
    // yet persisted across app restarts by `SourcesController` - a
    // pre-existing gap, out of scope here.
    if (config.authPassword.isNotEmpty) {
      unawaited(
        ref.read(secureCredentialStoreProvider).write(id, 'password', config.authPassword),
      );
    }

    ref.read(sourcesProvider.notifier).add(source);
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
          TextField(
            controller: _serverUrlController,
            decoration: InputDecoration(
              labelText: 'Server-URL',
              hintText: 'https://cloud.example.com',
              errorText: errors['serverUrl'],
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          if (_authKind == NextcloudAuthKind.account) ...[
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
                helperText: 'Erstelle ein App-Passwort unter Nextcloud-Einstellungen -> Sicherheit, '
                    'nicht dein eigentliches Account-Passwort.',
                errorText: errors['appPassword'],
                suffixIcon: IconButton(
                  icon: Icon(_obscureAppPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureAppPassword = !_obscureAppPassword),
                ),
              ),
            ),
          ] else ...[
            TextField(
              controller: _shareTokenController,
              decoration: InputDecoration(
                labelText: 'Share-Link oder Token',
                hintText: 'https://cloud.example.com/s/AbCdEf oder nur AbCdEf',
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
                  icon: Icon(_obscureSharePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureSharePassword = !_obscureSharePassword),
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
                child: Text(_lastError!),
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
