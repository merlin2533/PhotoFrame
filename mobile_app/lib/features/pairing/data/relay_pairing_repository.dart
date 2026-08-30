import '../../../core/errors/failure.dart';
import '../../../core/utils/result.dart';
import '../../../services/relay/relay_api_client.dart';
import '../domain/config_push_crypto.dart';
import '../domain/frame_keypair.dart';
import '../domain/key_fingerprint.dart';
import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';

/// [PairingRepository] implementation backed by [RelayApiClient] (HTTP),
/// [KeyFingerprintStore] (local TOFU state) and [ConfigPushCrypto]
/// (end-to-end encryption for the config-push payload).
class RelayPairingRepository implements PairingRepository {
  RelayPairingRepository({
    required RelayApiClient apiClient,
    required KeyFingerprintStore fingerprintStore,
    ConfigPushCrypto? crypto,
  })  : _api = apiClient,
        _fingerprints = fingerprintStore,
        _crypto = crypto ?? ConfigPushCrypto(keypairStore: FrameKeypairStore());

  final RelayApiClient _api;
  final KeyFingerprintStore _fingerprints;
  final ConfigPushCrypto _crypto;

  @override
  Future<Result<PairingInvite>> createInvite({String? pairingName, String? existingPairingId}) async {
    final result = await _api.createPairingCode(pairingName: pairingName, pairingId: existingPairingId);
    return result.map((created) => PairingInvite(
          pairingId: created.pairingId,
          code: created.code,
          expiresAt: created.expiresAt,
          fingerprint: created.fingerprint,
          fingerprintReason: created.fingerprintReason,
        ));
  }

  @override
  Future<Result<RedeemResult>> redeemInvite({
    required String code,
    required String? linkFingerprint,
    required String localFrameId,
  }) async {
    final redeemResult = await _api.redeemPairingCode(code);
    if (redeemResult.isErr) return Result.err(redeemResult.failureOrNull!);
    final pairingId = redeemResult.valueOrNull!;

    if (linkFingerprint == null) {
      return Result.ok(RedeemResult(pairingId: pairingId, outcome: RedeemOutcome.noFingerprintInLink));
    }

    final pairingResult = await _api.getPairing(pairingId);
    if (pairingResult.isErr) return Result.err(pairingResult.failureOrNull!);
    final pairing = pairingResult.valueOrNull!;

    final candidates = pairing.members.where(
      (m) => m.frameId != localFrameId && m.keyFingerprint == linkFingerprint,
    );

    if (candidates.isEmpty) {
      return Result.ok(RedeemResult(pairingId: pairingId, outcome: RedeemOutcome.noMatchingMember));
    }

    // Fingerprints are 40-bit; a collision between two real members is not
    // realistically expected. If it ever happens, treat conservatively as
    // "cannot verify" rather than guessing which one is the real inviter.
    if (candidates.length > 1) {
      return Result.ok(RedeemResult(pairingId: pairingId, outcome: RedeemOutcome.noMatchingMember));
    }

    final matched = candidates.first;
    final trust = await _fingerprints.checkOrTrust(matched.frameId, linkFingerprint);

    switch (trust) {
      case FingerprintTrust.trusted:
        return Result.ok(RedeemResult(
          pairingId: pairingId,
          outcome: RedeemOutcome.verifiedNewTrust,
          matchedFrameId: matched.frameId,
          matchedFingerprint: linkFingerprint,
        ));
      case FingerprintTrust.match:
        return Result.ok(RedeemResult(
          pairingId: pairingId,
          outcome: RedeemOutcome.verifiedMatchesExistingTrust,
          matchedFrameId: matched.frameId,
          matchedFingerprint: linkFingerprint,
        ));
      case FingerprintTrust.mismatch:
        return Result.ok(RedeemResult(
          pairingId: pairingId,
          outcome: RedeemOutcome.verifiedButLocalTrustMismatch,
          matchedFrameId: matched.frameId,
          matchedFingerprint: linkFingerprint,
        ));
    }
  }

  @override
  Future<void> confirmRedeemTrust(RedeemResult result) async {
    if (!result.requiresUserConfirmation) return;
    final frameId = result.matchedFrameId;
    final fingerprint = result.matchedFingerprint;
    if (frameId == null || fingerprint == null) return;
    await _fingerprints.acceptFingerprint(frameId, fingerprint);
  }

  @override
  Future<Result<Pairing>> getPairing(String pairingId) async {
    final result = await _api.getPairing(pairingId);
    return result.map((details) => Pairing(
          id: details.pairingId,
          name: details.name,
          members: details.members
              .map((m) => PairingMember(
                    frameId: m.frameId,
                    role: pairingRoleFromWire(m.role),
                    joinedAt: m.joinedAt,
                    keyFingerprint: m.keyFingerprint,
                    publicKey: m.publicKey,
                  ))
              .toList(),
        ));
  }

  @override
  Future<Result<void>> rename(String pairingId, String name) => _api.renamePairing(pairingId, name);

  @override
  Future<Result<void>> leave(String pairingId) => _api.leavePairing(pairingId);

  @override
  Future<Result<void>> removeMember(String pairingId, String frameId) => _api.removeMember(pairingId, frameId);

  @override
  Future<Result<void>> deletePairing(String pairingId) => _api.deletePairing(pairingId);

  @override
  Future<Result<String>> sendConfigPush({required String targetFrameId, required String ciphertext}) =>
      _api.sendConfigPush(targetFrameId: targetFrameId, ciphertext: ciphertext);

  @override
  Future<Result<ConfigPushRecipient>> resolveConfigPushRecipient({
    required String pairingId,
    required String targetFrameId,
  }) async {
    final pairingResult = await getPairing(pairingId);
    if (pairingResult.isErr) return Result.err(pairingResult.failureOrNull!);

    final target = pairingResult.valueOrNull!.memberById(targetFrameId);
    if (target == null) {
      return Result.err(Unsupported('Frame $targetFrameId ist kein Mitglied dieses Pairings (mehr).'));
    }

    // publicKey and fingerprint both come from this single GET /pairing/:id
    // response, so they are guaranteed to describe the same server-side
    // state - a malicious relay cannot pair a substituted public key with a
    // stale/unrelated fingerprint to slip past this check.
    final fingerprint = target.keyFingerprint;
    FingerprintTrust? trust;
    if (fingerprint != null) {
      trust = await _fingerprints.checkOrTrust(targetFrameId, fingerprint);
    }

    return Result.ok(ConfigPushRecipient(
      frameId: targetFrameId,
      publicKey: target.publicKey,
      fingerprint: fingerprint,
      trust: trust,
    ));
  }

  @override
  Future<Result<String>> sendEncryptedConfigPush({
    required String pairingId,
    required String targetFrameId,
    required String plaintextJson,
  }) async {
    final recipientResult = await resolveConfigPushRecipient(
      pairingId: pairingId,
      targetFrameId: targetFrameId,
    );
    if (recipientResult.isErr) return Result.err(recipientResult.failureOrNull!);
    final recipient = recipientResult.valueOrNull!;

    final publicKey = recipient.publicKey;
    if (publicKey == null) {
      return Result.err(Unsupported(
        'No public key on file for frame $targetFrameId - the relay server '
        'must expose PairingMember.publicKey from GET /pairing/:id before a '
        'config-push can be encrypted to it (see PairingMember.publicKey doc '
        'comment).',
      ));
    }

    // Defense in depth: even if a caller skipped the
    // resolveConfigPushRecipient()-driven mismatch-confirmation UI, this
    // guards against ever encrypting to an unverified/changed key. A true
    // mismatch is only cleared once the caller has explicitly confirmed the
    // warning via confirmSenderTrust, at which point this same check
    // observes FingerprintTrust.match instead.
    if (!recipient.isSafeToSend) {
      return Result.err(Unsupported(
        'Der Sicherheitsschlüssel von Frame $targetFrameId konnte nicht verifiziert werden oder hat '
        'sich seit dem letzten Kontakt geändert. Bitte zunächst die Sicherheitswarnung bestätigen.',
      ));
    }

    final ciphertext = await _crypto.encryptForRecipient(
      recipientPublicKeyBase64: publicKey,
      plaintextJson: plaintextJson,
    );
    return sendConfigPush(targetFrameId: targetFrameId, ciphertext: ciphertext);
  }

  @override
  Future<Result<List<PendingConfigPush>>> pendingConfigPushes({
    required String pairingId,
    required String localFrameId,
  }) async {
    final pendingResult = await _api.pendingConfigPushes();
    if (pendingResult.isErr) return Result.err(pendingResult.failureOrNull!);
    final pushes = pendingResult.valueOrNull!;
    if (pushes.isEmpty) return Result.ok(const <PendingConfigPush>[]);

    final pairingResult = await _api.getPairing(pairingId);
    if (pairingResult.isErr) return Result.err(pairingResult.failureOrNull!);
    final members = pairingResult.valueOrNull!.members;

    final result = <PendingConfigPush>[];
    for (final push in pushes) {
      final sender = members.where((m) => m.frameId == push.senderFrameId).cast<PairingMemberInfo?>().firstOrNull;
      final senderFingerprint = sender?.keyFingerprint;

      FingerprintTrust? trust;
      if (senderFingerprint == null) {
        // No key on file for the sender at all: never treat as safe.
        trust = FingerprintTrust.mismatch;
      } else {
        trust = await _fingerprints.checkOrTrust(push.senderFrameId, senderFingerprint);
      }

      result.add(PendingConfigPush(
        id: push.id,
        senderFrameId: push.senderFrameId,
        ciphertext: push.ciphertext,
        createdAt: push.createdAt,
        senderFingerprint: senderFingerprint,
        trust: trust,
      ));
    }
    return Result.ok(result);
  }

  @override
  Future<Result<void>> ackConfigPush(String pushId) => _api.ackConfigPush(pushId);

  @override
  Future<void> confirmSenderTrust({required String frameId, required String fingerprint}) =>
      _fingerprints.acceptFingerprint(frameId, fingerprint);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
