import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_app/core/utils/result.dart';
import 'package:mobile_app/features/pairing/data/relay_pairing_repository.dart';
import 'package:mobile_app/features/pairing/domain/key_fingerprint.dart';
import 'package:mobile_app/features/pairing/domain/pairing_models.dart';
import 'package:mobile_app/services/relay/relay_api_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockRelayApiClient extends Mock implements RelayApiClient {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('RelayPairingRepository.redeemInvite (client-side TOFU)', () {
    late _MockRelayApiClient api;
    late KeyFingerprintStore fingerprintStore;
    late RelayPairingRepository repository;

    const pairingId = 'pairing-1';
    const localFrameId = 'frame-self';
    const inviterFrameId = 'frame-inviter';

    PairingDetails detailsWithInviterFingerprint(String? fingerprint) {
      return PairingDetails(
        pairingId: pairingId,
        name: 'Test Pairing',
        members: [
          PairingMemberInfo(
            frameId: inviterFrameId,
            role: 'owner',
            joinedAt: DateTime(2026, 1, 1),
            keyFingerprint: fingerprint,
          ),
          PairingMemberInfo(
            frameId: localFrameId,
            role: 'member',
            joinedAt: DateTime(2026, 1, 2),
            keyFingerprint: null,
          ),
        ],
      );
    }

    setUp(() {
      api = _MockRelayApiClient();
      final mockStorage = _MockSecureStorage();
      final backing = <String, String>{};
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (i) async => backing[i.namedArguments[#key] as String],
      );
      when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
        (i) async {
          final key = i.namedArguments[#key] as String;
          final value = i.namedArguments[#value] as String?;
          if (value == null) {
            backing.remove(key);
          } else {
            backing[key] = value;
          }
        },
      );
      when(() => mockStorage.delete(key: any(named: 'key'))).thenAnswer((i) async {
        backing.remove(i.namedArguments[#key] as String);
      });
      fingerprintStore = KeyFingerprintStore(storage: mockStorage);
      repository = RelayPairingRepository(apiClient: api, fingerprintStore: fingerprintStore);

      when(() => api.redeemPairingCode(any())).thenAnswer((_) async => Result.ok(pairingId));
    });

    test('no fingerprint in the link yields noFingerprintInLink without calling getPairing', () async {
      final result = await repository.redeemInvite(
        code: 'CODE1',
        linkFingerprint: null,
        localFrameId: localFrameId,
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.outcome, RedeemOutcome.noFingerprintInLink);
      verifyNever(() => api.getPairing(any()));
    });

    test('a fingerprint matching exactly one member on first contact yields verifiedNewTrust', () async {
      when(() => api.getPairing(pairingId)).thenAnswer((_) async => Result.ok(detailsWithInviterFingerprint('FP001')));

      final result = await repository.redeemInvite(
        code: 'CODE1',
        linkFingerprint: 'FP001',
        localFrameId: localFrameId,
      );

      expect(result.valueOrNull!.outcome, RedeemOutcome.verifiedNewTrust);
      expect(result.valueOrNull!.matchedFrameId, inviterFrameId);
      expect(await fingerprintStore.trustedFingerprintFor(inviterFrameId), 'FP001');
    });

    test('a fingerprint matching an already-trusted value yields verifiedMatchesExistingTrust', () async {
      await fingerprintStore.checkOrTrust(inviterFrameId, 'FP001');
      when(() => api.getPairing(pairingId)).thenAnswer((_) async => Result.ok(detailsWithInviterFingerprint('FP001')));

      final result = await repository.redeemInvite(
        code: 'CODE1',
        linkFingerprint: 'FP001',
        localFrameId: localFrameId,
      );

      expect(result.valueOrNull!.outcome, RedeemOutcome.verifiedMatchesExistingTrust);
    });

    test('a fingerprint conflicting with a previously trusted value requires confirmation', () async {
      await fingerprintStore.checkOrTrust(inviterFrameId, 'OLDFP');
      when(() => api.getPairing(pairingId)).thenAnswer((_) async => Result.ok(detailsWithInviterFingerprint('NEWFP')));

      final result = await repository.redeemInvite(
        code: 'CODE1',
        linkFingerprint: 'NEWFP',
        localFrameId: localFrameId,
      );

      final redeemResult = result.valueOrNull!;
      expect(redeemResult.outcome, RedeemOutcome.verifiedButLocalTrustMismatch);
      expect(redeemResult.requiresUserConfirmation, isTrue);

      // Must NOT have silently overwritten the trusted value.
      expect(await fingerprintStore.trustedFingerprintFor(inviterFrameId), 'OLDFP');

      await repository.confirmRedeemTrust(redeemResult);
      expect(await fingerprintStore.trustedFingerprintFor(inviterFrameId), 'NEWFP');
    });

    test('a link fingerprint matching no member yields noMatchingMember and requires confirmation', () async {
      when(() => api.getPairing(pairingId)).thenAnswer((_) async => Result.ok(detailsWithInviterFingerprint('SERVERFP')));

      final result = await repository.redeemInvite(
        code: 'CODE1',
        linkFingerprint: 'LINKFP-DOES-NOT-MATCH',
        localFrameId: localFrameId,
      );

      final redeemResult = result.valueOrNull!;
      expect(redeemResult.outcome, RedeemOutcome.noMatchingMember);
      expect(redeemResult.requiresUserConfirmation, isTrue);
      expect(await fingerprintStore.trustedFingerprintFor(inviterFrameId), isNull);
    });

    test('confirmRedeemTrust is a no-op for outcomes that do not require confirmation', () async {
      when(() => api.getPairing(pairingId)).thenAnswer((_) async => Result.ok(detailsWithInviterFingerprint('FP001')));
      final result = await repository.redeemInvite(
        code: 'CODE1',
        linkFingerprint: 'FP001',
        localFrameId: localFrameId,
      );
      final redeemResult = result.valueOrNull!;
      expect(redeemResult.requiresUserConfirmation, isFalse);

      // Should not throw or store anything odd.
      await repository.confirmRedeemTrust(redeemResult);
      expect(await fingerprintStore.trustedFingerprintFor(inviterFrameId), 'FP001');
    });
  });
}
