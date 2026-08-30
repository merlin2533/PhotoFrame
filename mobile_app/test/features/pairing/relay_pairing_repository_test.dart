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

  group('RelayPairingRepository.sendEncryptedConfigPush (client-side TOFU, sending side)', () {
    late _MockRelayApiClient api;
    late KeyFingerprintStore fingerprintStore;
    late RelayPairingRepository repository;

    const pairingId = 'pairing-1';
    const localFrameId = 'frame-self';
    const targetFrameId = 'frame-target';

    // A syntactically valid (32-byte, base64) X25519 public key placeholder
    // - not tied to any real private key, since these tests only assert on
    // the TOFU gate (whether encryption is attempted at all), not on
    // `ConfigPushCrypto`'s actual cryptography, which is covered separately
    // in config_push_crypto_test.dart. `encryptForRecipient` only validates
    // the key's *shape* (32 bytes), so this is enough to exercise the
    // success path without throwing on decode.
    const targetPublicKeyBase64 = 'MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MGE=';

    PairingDetails detailsWithTarget({required String? fingerprint, String? publicKey}) {
      return PairingDetails(
        pairingId: pairingId,
        name: 'Test Pairing',
        members: [
          PairingMemberInfo(
            frameId: localFrameId,
            role: 'owner',
            joinedAt: DateTime(2026, 1, 1),
            keyFingerprint: null,
          ),
          PairingMemberInfo(
            frameId: targetFrameId,
            role: 'member',
            joinedAt: DateTime(2026, 1, 2),
            keyFingerprint: fingerprint,
            publicKey: publicKey,
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

      when(() => api.sendConfigPush(targetFrameId: any(named: 'targetFrameId'), ciphertext: any(named: 'ciphertext')))
          .thenAnswer((_) async => Result.ok('push-id-1'));
    });

    test('first contact (trusted) resolves as safe to send and encrypts normally', () async {
      when(() => api.getPairing(pairingId)).thenAnswer(
        (_) async => Result.ok(detailsWithTarget(fingerprint: 'FPNEW', publicKey: targetPublicKeyBase64)),
      );

      final recipientResult = await repository.resolveConfigPushRecipient(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
      );
      final recipient = recipientResult.valueOrNull!;
      expect(recipient.trust, FingerprintTrust.trusted);
      expect(recipient.isSafeToSend, isTrue);
      expect(await fingerprintStore.trustedFingerprintFor(targetFrameId), 'FPNEW');

      final sendResult = await repository.sendEncryptedConfigPush(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
        plaintextJson: '{"type":"smb"}',
      );

      expect(sendResult.isOk, isTrue);
      verify(() => api.sendConfigPush(targetFrameId: targetFrameId, ciphertext: any(named: 'ciphertext'))).called(1);
    });

    test('fingerprint matching existing trust (match) resolves as safe to send and encrypts normally', () async {
      await fingerprintStore.checkOrTrust(targetFrameId, 'FPKNOWN');
      when(() => api.getPairing(pairingId)).thenAnswer(
        (_) async => Result.ok(detailsWithTarget(fingerprint: 'FPKNOWN', publicKey: targetPublicKeyBase64)),
      );

      final recipientResult = await repository.resolveConfigPushRecipient(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
      );
      expect(recipientResult.valueOrNull!.trust, FingerprintTrust.match);
      expect(recipientResult.valueOrNull!.isSafeToSend, isTrue);

      final sendResult = await repository.sendEncryptedConfigPush(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
        plaintextJson: '{"type":"smb"}',
      );

      expect(sendResult.isOk, isTrue);
      verify(() => api.sendConfigPush(targetFrameId: targetFrameId, ciphertext: any(named: 'ciphertext'))).called(1);
    });

    test('a changed fingerprint (mismatch) is NOT sent/encrypted without explicit confirmation', () async {
      await fingerprintStore.checkOrTrust(targetFrameId, 'OLDFP');
      when(() => api.getPairing(pairingId)).thenAnswer(
        (_) async => Result.ok(detailsWithTarget(fingerprint: 'NEWFP', publicKey: targetPublicKeyBase64)),
      );

      final recipientResult = await repository.resolveConfigPushRecipient(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
      );
      final recipient = recipientResult.valueOrNull!;
      expect(recipient.trust, FingerprintTrust.mismatch);
      expect(recipient.isSafeToSend, isFalse);

      // The old value must still be what's trusted - resolving must not
      // silently overwrite it.
      expect(await fingerprintStore.trustedFingerprintFor(targetFrameId), 'OLDFP');

      // Attempting to send anyway (as if the UI's confirmation gate were
      // skipped/buggy) must refuse without encrypting/sending anything.
      final sendResult = await repository.sendEncryptedConfigPush(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
        plaintextJson: '{"type":"smb"}',
      );

      expect(sendResult.isErr, isTrue);
      verifyNever(() => api.sendConfigPush(targetFrameId: any(named: 'targetFrameId'), ciphertext: any(named: 'ciphertext')));
    });

    test('after explicit confirmation of a mismatch, the new fingerprint is trusted and sending proceeds', () async {
      await fingerprintStore.checkOrTrust(targetFrameId, 'OLDFP');
      when(() => api.getPairing(pairingId)).thenAnswer(
        (_) async => Result.ok(detailsWithTarget(fingerprint: 'NEWFP', publicKey: targetPublicKeyBase64)),
      );

      final recipientResult = await repository.resolveConfigPushRecipient(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
      );
      final recipient = recipientResult.valueOrNull!;
      expect(recipient.isSafeToSend, isFalse);

      // User explicitly confirms the mismatch warning - mirrors what
      // `send_config_push_screen.dart`'s `_confirmMismatchAndSend` does.
      await repository.confirmSenderTrust(frameId: targetFrameId, fingerprint: 'NEWFP');
      expect(await fingerprintStore.trustedFingerprintFor(targetFrameId), 'NEWFP');

      final sendResult = await repository.sendEncryptedConfigPush(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
        plaintextJson: '{"type":"smb"}',
      );

      expect(sendResult.isOk, isTrue);
      verify(() => api.sendConfigPush(targetFrameId: targetFrameId, ciphertext: any(named: 'ciphertext'))).called(1);
    });

    test('no public key on file refuses to send regardless of fingerprint', () async {
      when(() => api.getPairing(pairingId)).thenAnswer(
        (_) async => Result.ok(detailsWithTarget(fingerprint: 'FPNEW', publicKey: null)),
      );

      final sendResult = await repository.sendEncryptedConfigPush(
        pairingId: pairingId,
        targetFrameId: targetFrameId,
        plaintextJson: '{"type":"smb"}',
      );

      expect(sendResult.isErr, isTrue);
      verifyNever(() => api.sendConfigPush(targetFrameId: any(named: 'targetFrameId'), ciphertext: any(named: 'ciphertext')));
    });
  });
}
