import '../../../core/utils/result.dart';
import 'pairing_models.dart';

/// Application-facing interface for the pairing feature, sitting above
/// `RelayApiClient` (raw HTTP) and `KeyFingerprintStore` (TOFU state).
///
/// Kept as an interface (unlike `RelayApiClient`) because pairing business
/// rules - especially the TOFU verification folded into [redeemInvite] and
/// [pendingConfigPushes] - are exactly the kind of logic presentation-layer
/// tests want to exercise against a fake, without spinning up Dio/sockets.
abstract class PairingRepository {
  /// Creates a new pairing (if [existingPairingId] is omitted) or an
  /// invite code into an existing one, for the local device's frame.
  Future<Result<PairingInvite>> createInvite({String? pairingName, String? existingPairingId});

  /// Redeems a scanned/typed invite. [localFrameId] is required to
  /// distinguish "self" when resolving which pairing member the invite's
  /// out-of-band fingerprint refers to (see [RedeemOutcome]).
  Future<Result<RedeemResult>> redeemInvite({
    required String code,
    required String? linkFingerprint,
    required String localFrameId,
  });

  /// Explicitly trusts the fingerprint identified by a [RedeemResult] that
  /// had [RedeemResult.requiresUserConfirmation] set, after the user has
  /// confirmed the warning dialog. No-op (and safe to skip) for outcomes
  /// that didn't require confirmation.
  Future<void> confirmRedeemTrust(RedeemResult result);

  Future<Result<Pairing>> getPairing(String pairingId);

  Future<Result<void>> rename(String pairingId, String name);

  /// Removes the local device from the pairing (`POST /:id/leave`).
  Future<Result<void>> leave(String pairingId);

  /// Owner-only: removes another member (`DELETE /:id/members/:frameId`).
  Future<Result<void>> removeMember(String pairingId, String frameId);

  /// Owner-only: deletes the pairing entirely.
  Future<Result<void>> deletePairing(String pairingId);

  /// Sends an already-encrypted config blob to [targetFrameId]. Encryption
  /// itself (deriving a shared key from the recipient's public key, per
  /// PLAN.md "Frame-Fernkonfiguration") is out of scope for this
  /// repository - it is intentionally as opaque here as it is on the
  /// relay; callers own the crypto and pass the resulting ciphertext.
  Future<Result<String>> sendConfigPush({required String targetFrameId, required String ciphertext});

  /// Fetches pending config-pushes targeting [localFrameId] together with
  /// the TOFU verdict for each sender, resolved against [pairingId]'s
  /// current member list.
  Future<Result<List<PendingConfigPush>>> pendingConfigPushes({
    required String pairingId,
    required String localFrameId,
  });

  Future<Result<void>> ackConfigPush(String pushId);

  /// Explicitly trusts [fingerprint] for [frameId] after the user confirmed
  /// the mismatch warning shown by `config_push_confirmation_screen.dart`
  /// for a [PendingConfigPush] whose `trust` was
  /// `FingerprintTrust.mismatch`. Mirrors [confirmRedeemTrust] but for the
  /// config-push flow rather than the invite-redemption flow.
  Future<void> confirmSenderTrust({required String frameId, required String fingerprint});
}
