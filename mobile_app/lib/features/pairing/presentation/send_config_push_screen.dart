import 'package:flutter/material.dart';

import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';
import 'widgets/fingerprint_mismatch_warning.dart';

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
///
/// Client-side TOFU on the sending side: before any encryption happens,
/// [_send] calls [PairingRepository.resolveConfigPushRecipient] to fetch the
/// target's current public key AND fingerprint from a single relay
/// snapshot and check that fingerprint against local trust state. A
/// [ConfigPushRecipient.isSafeToSend] result (first contact or an
/// unchanged, already-trusted key) proceeds straight to encryption via
/// [_encryptAndSend]. Anything else - a changed fingerprint, or no
/// fingerprint at all - surfaces the same [FingerprintMismatchWarning] used
/// on the receiving side (`config_push_confirmation_screen.dart`) and
/// requires an explicit, hard-to-mis-tap confirmation before
/// [PairingRepository.confirmSenderTrust] is called and the payload is
/// finally encrypted. This closes the send/receive asymmetry a relay
/// operator could otherwise exploit by handing out a substituted public
/// key for the target frame id.
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

  /// Set while [_send] found a [ConfigPushRecipient] that is NOT
  /// [ConfigPushRecipient.isSafeToSend]: the warning card is shown instead
  /// of proceeding, and nothing is encrypted until the user explicitly
  /// confirms via [_confirmMismatchAndSend].
  ConfigPushRecipient? _pendingRecipient;
  bool _mismatchAcknowledged = false;

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
      _pendingRecipient = null;
      _mismatchAcknowledged = false;
    });

    final targetFrameId = _targetFrameIdController.text.trim();

    // Client-side TOFU check BEFORE any encryption: resolve the target's
    // current public key and fingerprint together from a single relay
    // snapshot and compare against local trust state. See
    // `key_fingerprint.dart` / `pairing_repository.dart` doc comments for
    // the full threat model this guards against (a relay operator swapping
    // in a substituted public key for the target frame).
    final recipientResult = await widget.repository.resolveConfigPushRecipient(
      pairingId: widget.pairingId,
      targetFrameId: targetFrameId,
    );

    if (!mounted) return;

    if (recipientResult.isErr) {
      setState(() {
        _sending = false;
        _error = recipientResult.failureOrNull!.message;
      });
      return;
    }

    final recipient = recipientResult.valueOrNull!;
    if (recipient.publicKey == null) {
      setState(() {
        _sending = false;
        _error = 'Für Frame $targetFrameId liegt noch kein Sicherheitsschlüssel auf dem Relay-Server vor - '
            'eine verschlüsselte Konfiguration kann noch nicht gesendet werden.';
      });
      return;
    }

    if (!recipient.isSafeToSend) {
      // Do NOT encrypt/send automatically: surface the same warning used on
      // the receiving side and require explicit confirmation first.
      setState(() {
        _sending = false;
        _pendingRecipient = recipient;
      });
      return;
    }

    await _encryptAndSend(targetFrameId);
  }

  /// Called after the user ticks the acknowledgement checkbox and confirms
  /// the [FingerprintMismatchWarning] shown for [_pendingRecipient]. Trusts
  /// the newly-observed fingerprint (mirroring
  /// `config_push_confirmation_screen.dart`'s `_accept`) and only THEN
  /// encrypts and sends.
  Future<void> _confirmMismatchAndSend() async {
    final recipient = _pendingRecipient;
    if (recipient == null || !_mismatchAcknowledged) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    final fingerprint = recipient.fingerprint;
    if (fingerprint != null) {
      await widget.repository.confirmSenderTrust(
        frameId: recipient.frameId,
        fingerprint: fingerprint,
      );
    }

    if (!mounted) return;
    setState(() => _pendingRecipient = null);
    await _encryptAndSend(recipient.frameId);
  }

  Future<void> _encryptAndSend(String targetFrameId) async {
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
      targetFrameId: targetFrameId,
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
              if (_pendingRecipient != null) ...[
                FingerprintMismatchWarning(
                  peerLabel: _targetFrameIdController.text.trim(),
                  observedFingerprint: _pendingRecipient!.fingerprint,
                  acknowledged: _mismatchAcknowledged,
                  onAcknowledgedChanged: (v) => setState(() => _mismatchAcknowledged = v),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() {
                                _pendingRecipient = null;
                                _mismatchAcknowledged = false;
                              }),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: (_sending || !_mismatchAcknowledged) ? null : _confirmMismatchAndSend,
                      child: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Trotzdem senden'),
                    ),
                  ],
                ),
              ] else
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
