import 'package:flutter/material.dart';

import '../../../services/relay/relay_api_client.dart';
import '../domain/frame_keypair.dart';

/// Lets the user recover a lost/reset frame device by rebinding its
/// `frameId` to a freshly generated keypair on this device
/// (`POST /frames/:frameId/recover`, see relay_server/src/auth/recovery.ts).
///
/// Keypair generation goes through [FrameKeypairStore.rotateKeypair]: this
/// device gets a brand-new X25519 keypair (private key persisted only in
/// `flutter_secure_storage`, never sent to the relay), and only the public
/// key is submitted with the recovery request. The old keypair (if any -
/// e.g. this really is a reset device that lost its original private key)
/// is unconditionally overwritten, matching the server's own behaviour of
/// discarding any `config_pushes` that were encrypted for the previous
/// key.
class RecoveryCodeScreen extends StatefulWidget {
  RecoveryCodeScreen({
    super.key,
    required this.apiClient,
    required this.onRecovered,
    FrameKeypairStore? keypairStore,
  }) : keypairStore = keypairStore ?? FrameKeypairStore();

  final RelayApiClient apiClient;
  final FrameKeypairStore keypairStore;

  /// Called with the recovered frame's new `deviceToken` and (if
  /// available) its new fingerprint once recovery succeeds.
  final void Function(String frameId, String deviceToken, String? newFingerprint) onRecovered;

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  final _frameIdController = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _newFingerprint;

  @override
  void dispose() {
    _frameIdController.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final frameId = _frameIdController.text.trim();
    if (frameId.isEmpty) {
      setState(() => _error = 'Frame-ID erforderlich');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final newPublicKey = await widget.keypairStore.rotateKeypair();
    final result = await widget.apiClient.recoverFrame(frameId: frameId, newPublicKey: newPublicKey);

    if (!mounted) return;
    result.when(
      onOk: (recovery) {
        setState(() => _newFingerprint = recovery.fingerprint);
        widget.onRecovered(recovery.frameId, recovery.deviceToken, recovery.fingerprint);
      },
      onErr: (failure) => setState(() => _error = failure.message),
    );
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gerät wiederherstellen')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wenn dieses Gerät den ursprünglichen Sicherheitsschlüssel eines '
              'gepaarten Frames verloren hat (z. B. nach einem Reset), kann es '
              'hier dessen Frame-ID reaktivieren. Andere gepaarte Geräte werden '
              'danach eine Sicherheitswarnung sehen, bis du ihnen den neuen '
              'Schlüssel erneut mitteilst (z. B. per neuem QR-Code).',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _frameIdController,
              decoration: const InputDecoration(labelText: 'Frame-ID'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_newFingerprint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Wiederherstellung erfolgreich. Neuer Sicherheitsschlüssel: '
                  '$_newFingerprint\nBitte anderen gepaarten Geräten einen neuen '
                  'QR-Code zeigen, damit sie diesen Schlüssel bestätigen können.',
                ),
              ),
            FilledButton(
              onPressed: _submitting ? null : _recover,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Wiederherstellen'),
            ),
          ],
        ),
      ),
    );
  }
}
