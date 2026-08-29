import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_app/features/pairing/domain/frame_keypair.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('FrameKeypairStore', () {
    late _MockSecureStorage storage;
    late Map<String, String> backing;

    FrameKeypairStore newStore({List<int> Function()? seedGenerator}) =>
        FrameKeypairStore(storage: storage, seedGenerator: seedGenerator);

    setUp(() {
      storage = _MockSecureStorage();
      backing = {};

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
    });

    test('hasKeypair is false before first use and true after', () async {
      final store = newStore();
      expect(await store.hasKeypair(), isFalse);
      await store.ensurePublicKeyBase64();
      expect(await store.hasKeypair(), isTrue);
    });

    test('ensurePublicKeyBase64 generates real, non-empty key material', () async {
      final store = newStore();
      final publicKeyBase64 = await store.ensurePublicKeyBase64();
      expect(publicKeyBase64, isNotEmpty);
      // X25519 public keys are 32 raw bytes.
      expect(base64Decode(publicKeyBase64), hasLength(32));
    });

    test('ensurePublicKeyBase64 is stable across calls once generated', () async {
      final store = newStore();
      final first = await store.ensurePublicKeyBase64();
      final second = await store.ensurePublicKeyBase64();
      expect(second, first);
    });

    test('loadOrCreateKeyPair reconstructs the same keypair from persisted storage', () async {
      final store = newStore();
      final publicKeyBase64 = await store.ensurePublicKeyBase64();

      // A fresh store instance backed by the *same* storage must reconstruct
      // the identical keypair, not merely "a" keypair.
      final reloadedStore = newStore();
      final reloadedPublicKey = await reloadedStore.ensurePublicKeyBase64();
      expect(reloadedPublicKey, publicKeyBase64);
    });

    test('rotateKeypair produces a different public key than before', () async {
      final store = newStore();
      final before = await store.ensurePublicKeyBase64();
      final after = await store.rotateKeypair();
      expect(after, isNot(equals(before)));
      // And it's the value now considered "current".
      expect(await store.ensurePublicKeyBase64(), after);
    });

    test('a fixed seedGenerator makes key generation deterministic (for tests only)', () async {
      List<int> fixedSeed() => List<int>.filled(32, 7);

      final storeA = newStore(seedGenerator: fixedSeed);
      final publicKeyA = await storeA.ensurePublicKeyBase64();

      // Different backing storage, same fixed seed -> same public key.
      final otherBacking = <String, String>{};
      final storageB = _MockSecureStorage();
      when(() => storageB.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async => otherBacking[invocation.namedArguments[#key] as String],
      );
      when(() => storageB.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
        (invocation) async {
          otherBacking[invocation.namedArguments[#key] as String] =
              invocation.namedArguments[#value] as String;
        },
      );
      final storeB = FrameKeypairStore(storage: storageB, seedGenerator: fixedSeed);
      final publicKeyB = await storeB.ensurePublicKeyBase64();

      expect(publicKeyB, publicKeyA);
    });

    test('forgetForTesting removes the stored keypair', () async {
      final store = newStore();
      final before = await store.ensurePublicKeyBase64();
      await store.forgetForTesting();
      expect(await store.hasKeypair(), isFalse);
      final after = await store.ensurePublicKeyBase64();
      // Real randomness resumed - extremely unlikely to collide.
      expect(after, isNot(equals(before)));
    });
  });
}
