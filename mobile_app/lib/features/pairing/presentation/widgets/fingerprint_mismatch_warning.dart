import 'package:flutter/material.dart';

import '../../domain/key_fingerprint.dart';

/// Shared "Sicherheitswarnung" card shown whenever a client-side TOFU check
/// ([KeyFingerprintStore.checkOrTrust]) comes back as
/// [FingerprintTrust.mismatch] (or with no fingerprint at all) - on EITHER
/// side of a config-push:
///
/// - Receiving a push: `config_push_confirmation_screen.dart` shows this
///   before decrypting/applying a push from an unverified sender.
/// - Sending a push: `send_config_push_screen.dart` shows this before
///   encrypting a payload to a recipient public key whose fingerprint
///   doesn't match what this device previously trusted.
///
/// Both call sites need exactly the same wording and the same
/// hard-to-mis-tap confirmation checkbox for this to remain a meaningful
/// security control, so the UI lives here once rather than being duplicated
/// (and risking drifting apart) across the two screens.
class FingerprintMismatchWarning extends StatelessWidget {
  const FingerprintMismatchWarning({
    super.key,
    required this.peerLabel,
    required this.observedFingerprint,
    required this.acknowledged,
    required this.onAcknowledgedChanged,
    this.acknowledgementLabel =
        'Ich habe die Warnung gelesen und bin sicher, dass dieses Gerät '
            'vertrauenswürdig ist.',
  });

  /// Human-friendly name of the other frame in this exchange (sender when
  /// receiving, recipient when sending).
  final String peerLabel;

  /// The fingerprint currently reported by the relay for [peerLabel], or
  /// `null` if that frame has no public key on file yet at all (an even
  /// weaker state than a mismatch: nothing can be verified).
  final String? observedFingerprint;

  final bool acknowledged;
  final ValueChanged<bool> onAcknowledgedChanged;
  final String acknowledgementLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
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
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              observedFingerprint == null
                  ? 'Für dieses Gerät ist noch kein Sicherheitsschlüssel bekannt. '
                      'Eine Konfiguration kann nicht verifiziert werden.'
                  : fingerprintMismatchWarningFor(peerLabel),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
            if (observedFingerprint != null) ...[
              const SizedBox(height: 8),
              Text(
                'Neuer Sicherheitsschlüssel: $observedFingerprint',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              value: acknowledged,
              onChanged: (v) => onAcknowledgedChanged(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                acknowledgementLabel,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
