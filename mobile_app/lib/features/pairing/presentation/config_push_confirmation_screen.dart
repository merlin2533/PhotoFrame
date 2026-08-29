import 'package:flutter/material.dart';

import '../domain/key_fingerprint.dart';
import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';

/// Gatekeeper screen shown before a received config-push is applied.
///
/// This is where the client-side TOFU check from
/// `key_fingerprint.dart` is actually enforced in the UI: a push whose
/// sender fingerprint is [FingerprintTrust.match] can be applied with a
/// single tap, but [FingerprintTrust.mismatch] (or no fingerprint at all)
/// forces the user through the explicit warning text from
/// [fingerprintMismatchWarningFor] and a distinct, harder-to-mis-tap
/// confirmation before the sender's new fingerprint is trusted and
/// [onAccept] is invoked. There is deliberately no path that applies a
/// mismatched push without this screen.
class ConfigPushConfirmationScreen extends StatefulWidget {
  const ConfigPushConfirmationScreen({
    super.key,
    required this.push,
    required this.senderLabel,
    required this.repository,
    required this.onAccept,
    required this.onReject,
  });

  final PendingConfigPush push;

  /// Human-friendly name for the sending frame (e.g. its display name),
  /// used to fill [fingerprintMismatchWarningFor].
  final String senderLabel;

  final PairingRepository repository;

  /// Called once the user has accepted the push (and, if needed, the new
  /// fingerprint). Receives the still-opaque ciphertext for the caller to
  /// decrypt/apply; this screen never touches plaintext.
  final void Function(String ciphertext) onAccept;

  /// Called when the user declines to apply the push. The push is left
  /// un-acked so it can be revisited later.
  final VoidCallback onReject;

  @override
  State<ConfigPushConfirmationScreen> createState() => _ConfigPushConfirmationScreenState();
}

class _ConfigPushConfirmationScreenState extends State<ConfigPushConfirmationScreen> {
  bool _mismatchAcknowledged = false;
  bool _busy = false;

  bool get _isMismatch =>
      widget.push.trust == FingerprintTrust.mismatch || widget.push.senderFingerprint == null;

  Future<void> _accept() async {
    setState(() => _busy = true);
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
      await widget.repository.ackConfigPush(widget.push.id);
      widget.onAccept(widget.push.ciphertext);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            const SizedBox(height: 16),
            if (_isMismatch) ...[
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Text(
                            'Sicherheitswarnung',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: theme.colorScheme.onErrorContainer),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.push.senderFingerprint == null
                            ? 'Für dieses Gerät ist noch kein Sicherheitsschlüssel bekannt. '
                                'Eine Konfiguration kann nicht verifiziert werden.'
                            : fingerprintMismatchWarningFor(widget.senderLabel),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                      ),
                      if (widget.push.senderFingerprint != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Neuer Sicherheitsschlüssel: ${widget.push.senderFingerprint}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onErrorContainer),
                        ),
                      ],
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _mismatchAcknowledged,
                        onChanged: (v) => setState(() => _mismatchAcknowledged = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          'Ich habe die Warnung gelesen und bin sicher, dass dieses Gerät '
                          'vertrauenswürdig ist.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
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
