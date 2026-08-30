import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../services/relay/relay_api_client.dart';
import '../domain/frame_keypair.dart';

/// Lets the user recover a lost/reset frame device by rebinding its
/// `frameId` to a freshly generated keypair on this device
/// (`POST /frames/:frameId/recover`, see relay_server/src/auth/recovery.ts).
///
/// Keypair generation goes through
/// [FrameKeypairStore.generateCandidateKeypair]: this device gets a
/// brand-new X25519 keypair, but its private key is held only in memory
/// (never persisted) until the server has actually confirmed the recovery
/// request with that key's public half. Only then is the candidate
/// committed to `flutter_secure_storage`, overwriting whatever keypair (if
/// any) existed before - matching the server's own behaviour of discarding
/// any `config_pushes` that were encrypted for the previous key. If the
/// request fails for any reason (network error, wrong frame ID, rate
/// limit, ...), the candidate is simply discarded and this device's
/// existing keypair - if it had one - is left completely untouched.
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

    // Generate the new keypair as an unpersisted candidate first - its
    // private key is only committed to secure storage below, after the
    // server has actually accepted the public key. A failed request must
    // never destroy this device's existing identity (see class doc).
    final candidate = await widget.keypairStore.generateCandidateKeypair();
    final result = await widget.apiClient.recoverFrame(
      frameId: frameId,
      newPublicKey: candidate.publicKeyBase64,
    );

    // fold (not when) because committing the candidate is itself async and
    // must complete - and be awaited - before this method proceeds; when()
    // invokes its callbacks synchronously and would let an async onOk race
    // with the setState below.
    //
    // Deliberately NOT gated on `mounted` before this point: if the server
    // already accepted the recovery (result is Ok), the candidate MUST be
    // committed regardless of whether this screen is still on-screen -
    // skipping the commit here would leave the server's `frames.public_key`
    // rotated to a key this device never actually persisted, desyncing the
    // two in a way that is worse than the original bug (a *successful*
    // recovery the device can no longer act on). `mounted` is only checked
    // before touching `setState`/`context`-dependent callbacks afterwards.
    String? recoveredFingerprint;
    Failure? recoveryError;
    await result.fold<Future<void>>(
      (recovery) async {
        try {
          await candidate.commit();
          recoveredFingerprint = recovery.fingerprint;
          if (mounted) {
            widget.onRecovered(recovery.frameId, recovery.deviceToken, recovery.fingerprint);
          }
        } on StateError catch (e) {
          // Candidate expired (>60 min since generation, e.g. the user left
          // this screen open for a long time before the network call
          // finally completed). The server has already rotated its key to
          // one this device cannot persist/use - surface it as an error
          // rather than silently losing the recovery.
          recoveryError = Unsupported(
            'Wiederherstellung fehlgeschlagen: der neue Schlüssel ist abgelaufen (${e.message}). '
            'Bitte erneut versuchen.',
          );
        }
      },
      (failure) async {
        recoveryError = failure;
      },
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (recoveredFingerprint != null) {
        _newFingerprint = recoveredFingerprint;
      }
      if (recoveryError != null) {
        _error = recoveryError!.message;
      }
    });
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
