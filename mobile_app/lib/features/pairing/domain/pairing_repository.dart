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

  /// Resolves [targetFrameId]'s current public key AND fingerprint from a
  /// single [getPairing] snapshot, and checks that fingerprint against
  /// local TOFU state (see [KeyFingerprintStore.checkOrTrust]) - the
  /// sending-side mirror of what [pendingConfigPushes] computes for
  /// received pushes.
  ///
  /// Callers (`send_config_push_screen.dart`) MUST call this - and check
  /// [ConfigPushRecipient.isSafeToSend] - BEFORE letting the user proceed
  /// to [sendEncryptedConfigPush]. A relay operator who has swapped in a
  /// substituted public key for [targetFrameId] would otherwise go
  /// undetected: the fingerprint travels alongside the public key from the
  /// very same relay response, so this is the only client-side signal that
  /// the two ever disagreed with what this device previously trusted.
  ///
  /// On [FingerprintTrust.trusted] (first contact) the new fingerprint is
  /// trusted and stored immediately, same as on receipt. On
  /// [FingerprintTrust.mismatch] (or no fingerprint at all) nothing is
  /// stored; the caller MUST surface [fingerprintMismatchWarningFor] and
  /// require explicit user confirmation before calling [confirmSenderTrust]
  /// and only THEN [sendEncryptedConfigPush].
  Future<Result<ConfigPushRecipient>> resolveConfigPushRecipient({
    required String pairingId,
    required String targetFrameId,
  });

  /// Convenience that does the encryption for the caller: looks up
  /// [targetFrameId]'s current public key within [pairingId] (via
  /// [resolveConfigPushRecipient]), encrypts [plaintextJson] to it
  /// (`ConfigPushCrypto.encryptForRecipient`), and forwards the resulting
  /// ciphertext to [sendConfigPush].
  ///
  /// This re-checks [ConfigPushRecipient.isSafeToSend] itself and refuses
  /// (returns an [Unsupported] failure, encrypting/sending nothing) if it
  /// is not safe - callers must not skip [resolveConfigPushRecipient] and
  /// the mismatch-confirmation UI it drives and call this directly hoping
  /// it will "just work" for an unverified recipient.
  ///
  /// Also returns an [Unsupported] failure if the target frame has no
  /// public key on file yet - which, against the relay server as of this
  /// writing, is every frame (see the "SERVER GAP" note on
  /// `PairingMember.publicKey`) until the server starts returning raw
  /// public keys from `GET /pairing/:id`.
  Future<Result<String>> sendEncryptedConfigPush({
    required String pairingId,
    required String targetFrameId,
    required String plaintextJson,
  });

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
