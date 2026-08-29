import 'package:flutter/material.dart';

import '../../../core/utils/result.dart';
import '../../../services/relay/relay_api_client.dart';
import '../../../services/relay/relay_token_storage.dart';
import '../domain/frame_keypair.dart';

/// First screen of the relay pairing flow: lets the user enter/confirm the
/// relay server's URL, creates a user account/session on it, and then
/// registers this device as a `Frame` with a real end-to-end-encryption
/// keypair (see [FrameKeypairStore]) so that "Frame-Fernkonfiguration"
/// config-pushes can later be encrypted to it.
///
/// Per the task brief this happens "auto on first start" where possible:
/// if no account exists yet for this relay, [_submit] transparently falls
/// back from login to registration (with a generated throwaway username)
/// rather than making the user think about accounts at all - a PhotoFrame
/// companion app user shouldn't need to understand "login vs. register".
/// An explicit username/password toggle is still offered for the
/// multi-device case (the phone joining an account that already owns
/// frames on the relay).
class RelayServerSetupScreen extends StatefulWidget {
  RelayServerSetupScreen({
    super.key,
    required this.tokenStorage,
    required this.onConnected,
    this.buildApiClient,
    FrameKeypairStore? keypairStore,
  }) : keypairStore = keypairStore ?? FrameKeypairStore();

  final RelayTokenStorage tokenStorage;

  /// Called once a session has been established AND this device has been
  /// registered as a frame with a real public key, with the ready-to-use
  /// client so the caller (typically a router redirect) can proceed to the
  /// pairing screen.
  final void Function(RelayApiClient client) onConnected;

  /// Overridable for tests; defaults to constructing a real [RelayApiClient].
  final RelayApiClient Function(String baseUrl, RelayTokenStorage storage)? buildApiClient;

  /// Source of this device's E2E keypair for frame registration. Overridable
  /// for tests; defaults to a real [FrameKeypairStore] backed by
  /// `flutter_secure_storage`.
  final FrameKeypairStore keypairStore;

  @override
  State<RelayServerSetupScreen> createState() => _RelayServerSetupScreenState();
}

class _RelayServerSetupScreenState extends State<RelayServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(text: 'https://');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isExistingAccount = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  RelayApiClient _clientFor(String baseUrl) {
    return widget.buildApiClient?.call(baseUrl, widget.tokenStorage) ??
        RelayApiClient(baseUrl: baseUrl, tokenStorage: widget.tokenStorage);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final baseUrl = _urlController.text.trim();
    final client = _clientFor(baseUrl);

    Result<AuthSession> result;
    if (_isExistingAccount) {
      result = await client.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
    } else {
      final username = _usernameController.text.trim().isEmpty
          ? 'frame-${DateTime.now().millisecondsSinceEpoch}'
          : _usernameController.text.trim();
      result = await client.register(username: username, password: _passwordController.text);
    }

    if (!mounted) return;

    if (result.isErr) {
      setState(() {
        _error = result.failureOrNull!.message;
        _submitting = false;
      });
      return;
    }

    // Account/session established - now make sure this device has a real
    // Frame identity with a genuine E2E keypair (see FrameKeypairStore doc
    // comment) rather than sending no public key at all. Skipped if this
    // device already registered a frame in a previous run (e.g. app
    // restart re-entering this screen because the user session, but not
    // the device session, needed refreshing).
    if (!await widget.tokenStorage.hasDeviceSession) {
      final publicKey = await widget.keypairStore.ensurePublicKeyBase64();
      final frameResult = await client.registerFrame(
        displayName: _usernameController.text.trim().isEmpty
            ? 'PhotoFrame'
            : _usernameController.text.trim(),
        publicKey: publicKey,
      );
      if (!mounted) return;
      if (frameResult.isErr) {
        setState(() {
          _error = frameResult.failureOrNull!.message;
          _submitting = false;
        });
        return;
      }
    }

    widget.onConnected(client);
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relay-Server einrichten')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'Relay-URL'),
                keyboardType: TextInputType.url,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Relay-URL erforderlich' : null,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Ich habe bereits ein Konto'),
                value: _isExistingAccount,
                onChanged: (v) => setState(() => _isExistingAccount = v),
              ),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: _isExistingAccount ? 'Benutzername' : 'Benutzername (optional)',
                ),
                validator: (v) =>
                    _isExistingAccount && (v == null || v.trim().isEmpty) ? 'Benutzername erforderlich' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Passwort'),
                obscureText: true,
                validator: (v) => (v == null || v.length < 8) ? 'Mindestens 8 Zeichen' : null,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verbinden'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
