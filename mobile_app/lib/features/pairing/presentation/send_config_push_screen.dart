import 'package:flutter/material.dart';

import '../domain/pairing_repository.dart';

/// Minimal UI for the sending side of "Frame-Fernkonfiguration"
/// (docs/PLAN.md point 9): lets the user type a target frame id plus an SMB
/// host/share/username/password, and pushes it - end-to-end encrypted via
/// [PairingRepository.sendEncryptedConfigPush] - to that frame.
///
/// This intentionally supports only the SMB use case named in the plan
/// (the original motivation: pushing SMB credentials onto a frame device
/// too keyboard-hostile to type them on). Extending the payload shape to
/// other source types is a straightforward follow-up once this flow is
/// exercised end-to-end - the encryption layer (`config_push_crypto.dart`)
/// is payload-shape-agnostic (it only ever sees `plaintextJson`).
class SendConfigPushScreen extends StatefulWidget {
  const SendConfigPushScreen({
    super.key,
    required this.pairingId,
    required this.repository,
    this.initialTargetFrameId,
  });

  final String pairingId;
  final PairingRepository repository;

  /// Pre-fills the target frame id field, e.g. when navigated to from a
  /// specific member row in `pairing_screen.dart`.
  final String? initialTargetFrameId;

  @override
  State<SendConfigPushScreen> createState() => _SendConfigPushScreenState();
}

class _SendConfigPushScreenState extends State<SendConfigPushScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _targetFrameIdController =
      TextEditingController(text: widget.initialTargetFrameId ?? '');
  final _hostController = TextEditingController();
  final _shareController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _sending = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _targetFrameIdController.dispose();
    _hostController.dispose();
    _shareController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });

    // Payload shape is this screen's own contract with the receiving
    // frame's application code (which must parse the same `type`/fields
    // back out after `ConfigPushCrypto.decryptFromSender` - see
    // `config_push_confirmation_screen.dart`). Kept as a flat JSON object
    // rather than a shared model class since the relay/crypto layers never
    // need to understand its shape - only the two frame apps do.
    final plaintextJson = '{'
        '"type":"smb",'
        '"host":${_jsonString(_hostController.text.trim())},'
        '"share":${_jsonString(_shareController.text.trim())},'
        '"username":${_jsonString(_usernameController.text.trim())},'
        '"password":${_jsonString(_passwordController.text)}'
        '}';

    final result = await widget.repository.sendEncryptedConfigPush(
      pairingId: widget.pairingId,
      targetFrameId: _targetFrameIdController.text.trim(),
      plaintextJson: plaintextJson,
    );

    if (!mounted) return;
    result.when(
      onOk: (_) => setState(() => _sent = true),
      onErr: (failure) => setState(() => _error = failure.message),
    );
    setState(() => _sending = false);
  }

  String _jsonString(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMB-Zugangsdaten senden')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Die Zugangsdaten werden Ende-zu-Ende-verschlüsselt für das '
                'Ziel-Gerät übertragen - der Relay-Server sieht nur '
                'Chiffrat.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetFrameIdController,
                decoration: const InputDecoration(labelText: 'Ziel-Frame-ID'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ziel-Frame-ID erforderlich' : null,
              ),
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: 'SMB-Host'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Host erforderlich' : null,
              ),
              TextFormField(
                controller: _shareController,
                decoration: const InputDecoration(labelText: 'Freigabename'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Freigabename erforderlich' : null,
              ),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Benutzername (optional)'),
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Passwort (optional)'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (_sent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('Konfiguration wurde verschlüsselt gesendet.'),
                ),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Senden'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
