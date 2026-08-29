import '../../../core/utils/result.dart';
import '../../../services/relay/relay_api_client.dart';
import '../domain/key_fingerprint.dart';
import '../domain/pairing_models.dart';
import '../domain/pairing_repository.dart';

/// [PairingRepository] implementation backed by [RelayApiClient] (HTTP) and
/// [KeyFingerprintStore] (local TOFU state).
class RelayPairingRepository implements PairingRepository {
  RelayPairingRepository({
    required RelayApiClient apiClient,
    required KeyFingerprintStore fingerprintStore,
  })  : _api = apiClient,
        _fingerprints = fingerprintStore;

  final RelayApiClient _api;
  final KeyFingerprintStore _fingerprints;

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
