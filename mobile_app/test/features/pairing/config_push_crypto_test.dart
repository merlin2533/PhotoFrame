import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_app/features/pairing/domain/config_push_crypto.dart';
import 'package:mobile_app/features/pairing/domain/frame_keypair.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// An in-memory [FlutterSecureStorage] stand-in, so each simulated "device"
/// (recipient, wrong-recipient, ...) gets its own independent keypair
/// without touching a real platform keychain.
_MockSecureStorage _fakeSecureStorage() {
  final storage = _MockSecureStorage();
  final backing = <String, String>{};
  when(() => storage.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => backing[invocation.namedArguments[#key] as String],
  );
  when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
    (invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        backing.remove(key);
      } else {
        backing[key] = value;
      }
    },
  );
  when(() => storage.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async {
      backing.remove(invocation.namedArguments[#key] as String);
    },
  );
  return storage;
}

void main() {
  group('ConfigPushCrypto', () {
    late FrameKeypairStore recipientKeypairStore;
    late ConfigPushCrypto senderCrypto;
    late ConfigPushCrypto recipientCrypto;

    setUp(() {
      // Sender's own keypair store is irrelevant to encryptForRecipient (it
      // never decrypts), but ConfigPushCrypto's constructor still requires
      // one - use a throwaway store.
      senderCrypto = ConfigPushCrypto(keypairStore: FrameKeypairStore(storage: _fakeSecureStorage()));

      recipientKeypairStore = FrameKeypairStore(storage: _fakeSecureStorage());
      recipientCrypto = ConfigPushCrypto(keypairStore: recipientKeypairStore);
    });

    test('round trip: recipient can decrypt what the sender encrypted for it', () async {
      final recipientPublicKey = await recipientKeypairStore.ensurePublicKeyBase64();
      const plaintext = '{"type":"smb","host":"nas.local","password":"hunter2"}';

      final ciphertext = await senderCrypto.encryptForRecipient(
        recipientPublicKeyBase64: recipientPublicKey,
        plaintextJson: plaintext,
      );

      // The wire envelope must never contain the plaintext in the clear.
      expect(ciphertext, isNot(contains('hunter2')));
      expect(ciphertext, isNot(contains('nas.local')));

      final decrypted = await recipientCrypto.decryptFromSender(ciphertext: ciphertext);
      expect(decrypted, plaintext);
    });

    test('envelope has the documented shape', () async {
      final recipientPublicKey = await recipientKeypairStore.ensurePublicKeyBase64();
      final ciphertext = await senderCrypto.encryptForRecipient(
        recipientPublicKeyBase64: recipientPublicKey,
        plaintextJson: '{"a":1}',
      );

      final envelope = jsonDecode(ciphertext) as Map<String, dynamic>;
      expect(envelope['v'], 1);
      expect(envelope['ephemeralPublicKey'], isA<String>());
      expect(envelope['nonce'], isA<String>());
      expect(envelope['ciphertext'], isA<String>());
      expect(envelope['mac'], isA<String>());
      // All fields must be valid base64.
      for (final key in ['ephemeralPublicKey', 'nonce', 'ciphertext', 'mac']) {
        expect(() => base64Decode(envelope[key] as String), returnsNormally);
      }
    });

    test('a different ephemeral keypair is used for every call (no key reuse)', () async {
      final recipientPublicKey = await recipientKeypairStore.ensurePublicKeyBase64();
      final ciphertextA = await senderCrypto.encryptForRecipient(
        recipientPublicKeyBase64: recipientPublicKey,
        plaintextJson: '{"a":1}',
      );
      final ciphertextB = await senderCrypto.encryptForRecipient(
        recipientPublicKeyBase64: recipientPublicKey,
        plaintextJson: '{"a":1}',
      );

      final envelopeA = jsonDecode(ciphertextA) as Map<String, dynamic>;
      final envelopeB = jsonDecode(ciphertextB) as Map<String, dynamic>;
      expect(envelopeA['ephemeralPublicKey'], isNot(equals(envelopeB['ephemeralPublicKey'])));
      expect(envelopeA['ciphertext'], isNot(equals(envelopeB['ciphertext'])));
    });

    test('the wrong recipient cannot decrypt the payload', () async {
      final recipientPublicKey = await recipientKeypairStore.ensurePublicKeyBase64();
      final ciphertext = await senderCrypto.encryptForRecipient(
        recipientPublicKeyBase64: recipientPublicKey,
        plaintextJson: '{"secret":"only-for-recipient"}',
      );

      final wrongRecipientCrypto = ConfigPushCrypto(
        keypairStore: FrameKeypairStore(storage: _fakeSecureStorage()),
      );

      expect(
        () => wrongRecipientCrypto.decryptFromSender(ciphertext: ciphertext),
        throwsA(isA<ConfigPushDecryptionException>()),
      );
    });

    test('a corrupted ciphertext throws ConfigPushDecryptionException', () async {
      final recipientPublicKey = await recipientKeypairStore.ensurePublicKeyBase64();
      final ciphertext = await senderCrypto.encryptForRecipient(
        recipientPublicKeyBase64: recipientPublicKey,
        plaintextJson: '{"a":1}',
      );

      final envelope = jsonDecode(ciphertext) as Map<String, dynamic>;
      // Flip the ciphertext bytes so the AEAD tag check fails.
      final tampered = Map<String, dynamic>.from(envelope);
      tampered['ciphertext'] = base64Encode(List<int>.filled(16, 0));

      expect(
        () => recipientCrypto.decryptFromSender(ciphertext: jsonEncode(tampered)),
        throwsA(isA<ConfigPushDecryptionException>()),
      );
    });

    test('malformed (non-JSON) ciphertext throws ConfigPushDecryptionException', () async {
      expect(
        () => recipientCrypto.decryptFromSender(ciphertext: 'not json at all'),
        throwsA(isA<ConfigPushDecryptionException>()),
      );
    });

    test('JSON missing required fields throws ConfigPushDecryptionException', () async {
      expect(
        () => recipientCrypto.decryptFromSender(ciphertext: jsonEncode({'v': 1})),
        throwsA(isA<ConfigPushDecryptionException>()),
      );
    });
  });
}
