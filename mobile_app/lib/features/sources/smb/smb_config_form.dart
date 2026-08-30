import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/photo_source.dart';
import '../state/sources_providers.dart';
import 'smb_config_form_model.dart';
import 'smb_network_discovery.dart';
import 'smb_photo_source.dart';

/// Configuration screen for an SMB/network-share source.
///
/// See `smb_photo_source.dart`'s file-level "UNVERIFIED" comment: this form
/// only makes the source *configurable*; it cannot itself prove
/// `SmbPhotoSource` works against real hardware (no SMB server reachable in
/// this environment). "Verbindung testen" below calls the real
/// `SmbPhotoSource.testConnection()` and surfaces its actual result/error -
/// it just can't be exercised end-to-end here.
class SmbConfigFormScreen extends ConsumerStatefulWidget {
  const SmbConfigFormScreen({super.key});

  @override
  ConsumerState<SmbConfigFormScreen> createState() => _SmbConfigFormScreenState();
}

class _SmbConfigFormScreenState extends ConsumerState<SmbConfigFormScreen> {
  final _hostController = TextEditingController();
  final _shareController = TextEditingController();
  final _domainController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rootPathController = TextEditingController();

  bool _obscurePassword = true;
  bool _testing = false;
  bool _discovering = false;
  bool _submitted = false;
  ConnectionStatus? _lastStatus;
  String? _lastError;

  SmbConfigFormModel get _model => SmbConfigFormModel(
        host: _hostController.text,
        share: _shareController.text,
        domain: _domainController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        rootPath: _rootPathController.text,
      );

  @override
  void dispose() {
    _hostController.dispose();
    _shareController.dispose();
    _domainController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rootPathController.dispose();
    super.dispose();
  }

  SmbSourceConfig _buildConfig(SmbConfigFormModel normalized) {
    return SmbSourceConfig(
      host: normalized.host,
      share: normalized.share,
      domain: normalized.domain,
      username: normalized.username,
      password: _passwordController.text,
      rootPath: normalized.rootPath,
    );
  }

  Future<void> _testConnection() async {
    setState(() => _submitted = true);
    final errors = _model.validate();
    if (errors.isNotEmpty) return;

    setState(() {
      _testing = true;
      _lastStatus = null;
      _lastError = null;
    });

    final config = _buildConfig(_model.normalized());
    final probe = SmbPhotoSource(id: 'probe', config: config);
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

  Future<void> _discoverHosts() async {
    setState(() => _discovering = true);
    final discovery = SmbNetworkDiscovery();
    List<DiscoveredSmbHost> hosts;
    try {
      hosts = await discovery.discoverAll();
    } catch (_) {
      // discoverAll() can throw (permission denied, broadcast-socket
      // failure, ...) - without this catch the exception would propagate
      // out of an unawaited-by-the-caller Future and, critically, skip the
      // setState below, leaving "Netzwerk durchsuchen" permanently
      // disabled for the rest of this screen's lifetime.
      if (mounted) {
        setState(() => _discovering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Netzwerksuche fehlgeschlagen. Host manuell eingeben.')),
        );
      }
      return;
    } finally {
      discovery.dispose();
    }
    if (!mounted) return;
    setState(() => _discovering = false);

    if (hosts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keine Geräte gefunden. Das ist auf vielen Netzwerken normal - '
            'gib Host/IP stattdessen manuell ein.',
          ),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<DiscoveredSmbHost>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Gefundene Geräte', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final host in hosts)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(host.host),
              subtitle: Text(host.address.address),
              onTap: () => Navigator.of(context).pop(host),
            ),
        ],
      ),
    );

    if (selected != null) {
      _hostController.text = selected.address.address;
    }
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final normalized = _model.normalized();
    final errors = normalized.validate();
    if (errors.isNotEmpty) {
      setState(() {});
      return;
    }

    final id = ref.read(sourceIdGeneratorProvider).v4();
    final config = _buildConfig(normalized);
    final source = SmbPhotoSource(id: id, config: config);

    // Persist the password in the secure keychain (never in
    // shared_preferences - see SecureCredentialStore's doc comment) so a
    // future source-registry reload can restore it without asking the user
    // to retype it. Awaited (unlike before) so the write has actually landed
    // before `add()` below triggers `SourcesController`'s own descriptor
    // persistence, which no longer needs to know about it directly but
    // reads it back on the *next* app start via `SourcesController.build`.
    if (config.password.isNotEmpty) {
      await ref.read(secureCredentialStoreProvider).write(id, 'password', config.password);
    }

    await ref.read(sourcesProvider.notifier).add(source);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final errors = _submitted ? _model.validate() : const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('SMB-Netzwerkfreigabe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Hinweis: Diese Quelle wurde gegen die öffentliche Doku des '
                'verwendeten SMB-Pakets gebaut, aber noch nicht gegen eine '
                'echte Freigabe getestet. "Verbindung testen" zeigt dir den '
                'echten Fehlschlag, falls etwas nicht funktioniert.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: InputDecoration(
              labelText: 'Host / IP-Adresse',
              hintText: 'z. B. 192.168.1.20',
              errorText: errors['host'],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _discovering ? null : _discoverHosts,
            icon: _discovering
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find_outlined),
            label: const Text('Netzwerk durchsuchen'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _shareController,
            decoration: InputDecoration(
              labelText: 'Freigabename',
              hintText: 'z. B. Photos',
              errorText: errors['share'],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rootPathController,
            decoration: const InputDecoration(
              labelText: 'Unterordner (optional)',
              hintText: 'z. B. Frame/2024',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _domainController,
            decoration: const InputDecoration(
              labelText: 'Domäne (optional)',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Benutzername'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Passwort',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                child: Text(
                  'Verbunden${_lastStatus!.detail != null ? ' - ${_lastStatus!.detail}' : ''}',
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
