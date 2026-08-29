import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/pairing_models.dart';

/// Displays a [PairingInvite] as a scannable QR code encoding the
/// `photoframe://pair?...` deep link (see [PairingInvite.toDeepLink]).
class PairingQrDisplayScreen extends StatelessWidget {
  const PairingQrDisplayScreen({super.key, required this.invite, required this.relayUrl});

  final PairingInvite invite;
  final String relayUrl;

  @override
  Widget build(BuildContext context) {
    final deepLink = invite.toDeepLink(relayUrl: relayUrl);
    final remaining = invite.expiresAt.difference(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Gerät einladen')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: deepLink.toString(),
                version: QrVersions.auto,
                size: 260,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Code: ${invite.code}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              remaining.isNegative
                  ? 'Dieser Code ist abgelaufen.'
                  : 'Gültig für weitere ${remaining.inMinutes} Minute(n).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (invite.fingerprint != null)
              Text(
                'Sicherheitsschlüssel: ${invite.fingerprint}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Hinweis: Dieses Gerät hat noch keinen Sicherheitsschlüssel '
                  '(${invite.fingerprintReason ?? "unbekannter Grund"}). Die '
                  'Fingerabdruck-Prüfung greift erst, sobald einer erzeugt wurde.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
