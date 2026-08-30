import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'frame_keypair.dart';

/// Thrown by [ConfigPushCrypto.decryptFromSender] whenever a ciphertext
/// cannot be turned back into plaintext: malformed envelope JSON, a
/// recipient public key that doesn't match this device's private key (i.e.
/// the push wasn't actually addressed to us), or a failed AEAD
/// authentication tag check (corruption or tampering in transit/at rest on
/// the relay). Deliberately a single exception type with a `reason` rather
/// than several subtypes - distinguishing "wrong recipient" from "corrupt
/// bytes" from the outside is not reliably possible (and not meaningfully
/// actionable for the caller: either way, the push must be rejected).
class ConfigPushDecryptionException implements Exception {
  const ConfigPushDecryptionException(this.reason);

  final String reason;

  @override
  String toString() => 'ConfigPushDecryptionException: $reason';
}

/// Encrypts/decrypts the "Frame-Fernkonfiguration" config-push payload
/// described in docs/PLAN.md, "Relay-Server: Datenmodell & Ablauf" point 9.
///
/// ## Construction (anonymous-sender ECDH, deliberately NOT libsodium
/// `crypto_box_seal`)
///
/// `package:cryptography` has no built-in "sealed box" primitive, so this
/// implements the equivalent construction directly on top of primitives it
/// does provide well:
///
/// 1. The sender generates a fresh, one-time **ephemeral** X25519 keypair
///    for this single message (never persisted, never reused).
/// 2. The sender computes an ECDH shared secret between that ephemeral
///    private key and the recipient's long-lived public key
///    ([FrameKeypairStore]'s key on the recipient's device, published to the
///    relay as `frames.public_key`).
/// 3. That shared secret is run through HKDF-SHA256 (salt = ephemeral public
///    key bytes ++ recipient public key bytes, info = a fixed context
///    string) to derive a 256-bit AES-GCM key. Using both public keys as
///    salt binds the derived key to this specific (ephemeral, recipient)
///    pair, and costs nothing to include since both values are already
///    being transmitted in the clear alongside the ciphertext.
/// 4. The plaintext JSON is encrypted with AES-256-GCM under that derived
///    key with a fresh random nonce.
/// 5. The envelope sent over the wire is `{ephemeralPublicKey, nonce,
///    ciphertext, mac}`, all base64 - see [encryptForRecipient].
///
/// This has the key "sealed box" property the plan asks for: the recipient
/// can decrypt using only their own long-lived private key plus the
/// ephemeral public key riding along in the envelope - no shared secret or
/// session needs to have been set up in advance. It does NOT, by itself,
/// authenticate the sender's identity: anyone who has the recipient's
/// public key (which the relay hands out to any paired frame) can produce a
/// message the recipient will accept as "successfully decrypted". For this
/// app's threat model that is intentional and sufficient - sender
/// authentication is handled one layer up, by the relay only ever
/// delivering a push labelled with `sender_frame_id` from an authenticated
/// session, plus the receiving app's out-of-band TOFU fingerprint check
/// (`key_fingerprint.dart`) on that `sender_frame_id` before the user is
/// asked to apply anything. Adding a real cryptographic sender signature
/// (e.g. also signing the envelope with the sender's Ed25519 key) is a
/// reasonable future hardening step but out of scope here.
class ConfigPushCrypto {
  ConfigPushCrypto({
    required FrameKeypairStore keypairStore,
    X25519? keyExchangeAlgorithm,
    AesGcm? cipherAlgorithm,
  })  : _keypairStore = keypairStore,
        _keyExchange = keyExchangeAlgorithm ?? X25519(),
        _cipher = cipherAlgorithm ?? AesGcm.with256bits();

  final FrameKeypairStore _keypairStore;
  final X25519 _keyExchange;
  final AesGcm _cipher;

  /// Domain-separation context for HKDF; bumping the trailing version
  /// breaks compatibility with any ciphertext produced by an older client,
  /// which is intentional if the envelope shape or KDF inputs ever change.
  static final List<int> _hkdfInfo = utf8.encode('photoframe-config-push-v1');

  Hkdf get _hkdf => Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Encrypts [plaintextJson] (e.g. `{"type":"smb","host":...}`) so that
  /// only the holder of the private key matching
  /// [recipientPublicKeyBase64] can read it, and returns the wire envelope
  /// as a JSON string ready to hand to `RelayApiClient.sendConfigPush`'s
  /// `ciphertext` parameter.
  ///
  /// Envelope format (documented here since it is this method's contract
  /// with [decryptFromSender], not enforced by any shared schema):
  /// ```json
  /// {
  ///   "v": 1,
  ///   "ephemeralPublicKey": "<base64, 32 bytes>",
  ///   "nonce": "<base64, 12 bytes>",
  ///   "ciphertext": "<base64>",
  ///   "mac": "<base64, 16 bytes>"
  /// }
  /// ```
  Future<String> encryptForRecipient({
    required String recipientPublicKeyBase64,
    required String plaintextJson,
  }) async {
    final recipientPublicKeyBytes = base64Decode(recipientPublicKeyBase64);
    final recipientPublicKey = SimplePublicKey(recipientPublicKeyBytes, type: KeyPairType.x25519);

    final ephemeralKeyPair = await _keyExchange.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: [...ephemeralPublicKey.bytes, ...recipientPublicKeyBytes],
      info: _hkdfInfo,
    );

    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintextJson),
      secretKey: derivedKey,
    );

    final envelope = <String, Object?>{
      'v': 1,
      'ephemeralPublicKey': base64Encode(ephemeralPublicKey.bytes),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return jsonEncode(envelope);
  }

  /// Decrypts an envelope produced by [encryptForRecipient], using this
  /// device's own keypair from [FrameKeypairStore] as the recipient
  /// private key. Throws [ConfigPushDecryptionException] - never returns a
  /// partially-decrypted or unauthenticated result - if [ciphertext] is
  /// malformed, was not actually addressed to this device's public key, or
  /// fails AEAD authentication.
  Future<String> decryptFromSender({required String ciphertext}) async {
    late final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(ciphertext);
      if (decoded is! Map<String, dynamic>) {
        throw const ConfigPushDecryptionException('envelope is not a JSON object');
      }
      envelope = decoded;
    } on ConfigPushDecryptionException {
      rethrow;
    } catch (e) {
      throw ConfigPushDecryptionException('envelope is not valid JSON: $e');
    }

    final List<int> ephemeralPublicKeyBytes;
    final List<int> nonce;
    final List<int> cipherTextBytes;
    final List<int> macBytes;
    try {
      ephemeralPublicKeyBytes = base64Decode(envelope['ephemeralPublicKey'] as String);
      nonce = base64Decode(envelope['nonce'] as String);
      cipherTextBytes = base64Decode(envelope['ciphertext'] as String);
      macBytes = base64Decode(envelope['mac'] as String);
    } catch (e) {
      throw ConfigPushDecryptionException('envelope fields missing or not valid base64: $e');
    }

    final keyPair = await _keypairStore.loadOrCreateKeyPair();
    final myPublicKey = await keyPair.extractPublicKey();
    final ephemeralPublicKey = SimplePublicKey(ephemeralPublicKeyBytes, type: KeyPairType.x25519);

    try {
      final sharedSecret = await _keyExchange.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: ephemeralPublicKey,
      );

      final derivedKey = await _hkdf.deriveKey(
        secretKey: sharedSecret,
        nonce: [...ephemeralPublicKeyBytes, ...myPublicKey.bytes],
        info: _hkdfInfo,
      );

      final secretBox = SecretBox(cipherTextBytes, nonce: nonce, mac: Mac(macBytes));
      final clearTextBytes = await _cipher.decrypt(secretBox, secretKey: derivedKey);
      return utf8.decode(clearTextBytes);
    } on ConfigPushDecryptionException {
      rethrow;
    } catch (e) {
      // Covers both a wrong-recipient key exchange (which yields a
      // plausible-looking but wrong AES key, so this still fails at the
      // GCM tag check) and genuine corruption - see class doc comment for
      // why these aren't distinguished.
      throw ConfigPushDecryptionException('could not decrypt/authenticate payload: $e');
    }
  }
}
