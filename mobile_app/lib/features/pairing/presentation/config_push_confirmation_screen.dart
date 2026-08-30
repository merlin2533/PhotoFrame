import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/config_push_crypto.dart';
import '../domain/frame_keypair.dart';
import '../domain/key_fingerprint.dart';
import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';
import 'widgets/fingerprint_mismatch_warning.dart';

/// Gatekeeper screen shown before a received config-push is applied.
///
/// This is where the client-side TOFU check from
/// `key_fingerprint.dart` is actually enforced in the UI: a push whose
/// sender fingerprint is [FingerprintTrust.match] can be applied with a
/// single tap, but [FingerprintTrust.mismatch] (or no fingerprint at all)
/// forces the user through the explicit warning text from
/// [fingerprintMismatchWarningFor] and a distinct, harder-to-mis-tap
/// confirmation before the sender's new fingerprint is trusted. Only once
/// that verification has passed does this screen actually decrypt the
/// payload (via [ConfigPushCrypto.decryptFromSender], using this device's
/// own private key) and hand the resulting PLAINTEXT JSON to [onAccept] -
/// there is deliberately no path that applies (or even decrypts) a
/// mismatched push without going through this screen.
class ConfigPushConfirmationScreen extends StatefulWidget {
  ConfigPushConfirmationScreen({
    super.key,
    required this.push,
    required this.senderLabel,
    required this.repository,
    required this.onAccept,
    required this.onReject,
    ConfigPushCrypto? crypto,
  }) : crypto = crypto ?? ConfigPushCrypto(keypairStore: FrameKeypairStore());

  final PendingConfigPush push;

  /// Human-friendly name for the sending frame (e.g. its display name),
  /// used to fill [fingerprintMismatchWarningFor].
  final String senderLabel;

  final PairingRepository repository;

  /// Decrypts [PendingConfigPush.ciphertext] using this device's own
  /// keypair. Overridable for tests.
  final ConfigPushCrypto crypto;

  /// Called once the user has accepted the push (and, if needed, the new
  /// fingerprint) AND decryption succeeded. Receives the decrypted
  /// plaintext JSON payload (e.g. SMB credentials) ready for the caller to
  /// parse and apply.
  final void Function(String plaintextJson) onAccept;

  /// Called when the user declines to apply the push, OR when decryption
  /// fails after an otherwise-accepted push (wrong recipient/corrupt
  /// ciphertext - see [ConfigPushDecryptionException]). Either way the push
  /// is left un-acked so it can be revisited/re-sent.
  final VoidCallback onReject;

  @override
  State<ConfigPushConfirmationScreen> createState() => _ConfigPushConfirmationScreenState();
}

class _ConfigPushConfirmationScreenState extends State<ConfigPushConfirmationScreen> {
  bool _mismatchAcknowledged = false;
  bool _busy = false;
  String? _decryptError;

  bool get _isMismatch =>
      widget.push.trust == FingerprintTrust.mismatch || widget.push.senderFingerprint == null;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _decryptError = null;
    });
    try {
      if (_isMismatch) {
        final fingerprint = widget.push.senderFingerprint;
        if (fingerprint != null) {
          await widget.repository.confirmSenderTrust(
            frameId: widget.push.senderFrameId,
            fingerprint: fingerprint,
          );
        }
      }

      // Decrypt BEFORE acking: if decryption fails (wrong recipient, or a
      // corrupt/tampered ciphertext), the push must stay pending/un-acked
      // so it can be revisited or the sender can be asked to resend,
      // rather than being marked handled while nothing was actually
      // applied.
      final String plaintextJson;
      try {
        plaintextJson = await widget.crypto.decryptFromSender(ciphertext: widget.push.ciphertext);
      } on ConfigPushDecryptionException catch (e) {
        if (mounted) setState(() => _decryptError = 'Entschlüsselung fehlgeschlagen: ${e.reason}');
        return;
      }

      await widget.repository.ackConfigPush(widget.push.id);
      widget.onAccept(plaintextJson);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Konfiguration erhalten')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Von: ${widget.senderLabel}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Frame-ID: ${widget.push.senderFrameId}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            // Only SMB config-push payloads exist today (see
            // `send_config_push_screen.dart`'s doc comment) - this question
            // is shown up front, before decryption even happens, per the
            // docs/PLAN.md point 9 wording. If/when other payload types are
            // added, this should become conditional on the decrypted
            // `type` field instead of always assuming "smb".
            Text(
              l10n.configPushConfirmSmbTitle(widget.senderLabel),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            if (_isMismatch) ...[
              FingerprintMismatchWarning(
                peerLabel: widget.senderLabel,
                observedFingerprint: widget.push.senderFingerprint,
                acknowledged: _mismatchAcknowledged,
                onAcknowledgedChanged: (v) => setState(() => _mismatchAcknowledged = v),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.verified, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sicherheitsschlüssel bestätigt (${widget.push.senderFingerprint}). '
                      'Diese Konfiguration kann sicher übernommen werden.',
                    ),
                  ),
                ],
              ),
            ],
            if (_decryptError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_decryptError!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : widget.onReject,
                  child: const Text('Ablehnen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_busy || (_isMismatch && !_mismatchAcknowledged)) ? null : _accept,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Übernehmen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
