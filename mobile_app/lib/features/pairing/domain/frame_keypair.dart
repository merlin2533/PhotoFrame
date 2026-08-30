import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns this device's X25519 identity keypair for the "Frame-Fernkonfiguration"
/// feature (see docs/PLAN.md, "Relay-Server: Datenmodell & Ablauf" point 9).
///
/// Only the PUBLIC half of the keypair is ever meant to leave this device
/// (sent to the relay as `frames.public_key` via
/// `RelayApiClient.registerFrame`/`recoverFrame`). The private half - here,
/// a 32-byte X25519 seed - is persisted exclusively in
/// [FlutterSecureStorage] (Keychain/Keystore-backed) and is never logged,
/// never included in any request body, and never written to any other
/// storage (shared_preferences, files, ...).
///
/// Persistence strategy: `package:cryptography`'s [X25519] supports
/// regenerating the exact same [SimpleKeyPair] from a 32-byte seed via
/// [X25519.newKeyPairFromSeed] (see the package's own
/// `KeyExchangeAlgorithm.newKeyPairFromSeed` doc comment). Storing the seed
/// - rather than trying to serialize a [SimpleKeyPair] object - keeps
/// reconstruction a single, well-defined operation and also means tests can
/// get fully deterministic key material by supplying a fixed seed via
/// [seedGenerator], without this class needing any special "test mode".
class FrameKeypairStore {
  FrameKeypairStore({
    FlutterSecureStorage? storage,
    X25519? algorithm,
    List<int> Function()? seedGenerator,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _algorithm = algorithm ?? X25519(),
        _seedGenerator = seedGenerator ?? _randomSeed;

  final FlutterSecureStorage _storage;
  final X25519 _algorithm;
  final List<int> Function() _seedGenerator;

  static const _seedStorageKey = 'pf_frame_keypair_seed_v1';
  static const _seedLength = 32;

  static List<int> _randomSeed() {
    final random = Random.secure();
    return List<int>.generate(_seedLength, (_) => random.nextInt(256));
  }

  Future<List<int>?> _readSeed() async {
    final raw = await _storage.read(key: _seedStorageKey);
    if (raw == null) return null;
    return base64Decode(raw);
  }

  Future<void> _writeSeed(List<int> seed) =>
      _storage.write(key: _seedStorageKey, value: base64Encode(seed));

  /// Returns this device's current keypair, generating and persisting a new
  /// one on first use. Safe to call repeatedly/concurrently - it always
  /// reconstructs the same [SimpleKeyPair] from whatever seed is currently
  /// stored, generating one only if none exists yet.
  Future<SimpleKeyPair> loadOrCreateKeyPair() async {
    final existingSeed = await _readSeed();
    if (existingSeed != null) {
      return _algorithm.newKeyPairFromSeed(existingSeed);
    }
    final newSeed = _seedGenerator();
    await _writeSeed(newSeed);
    return _algorithm.newKeyPairFromSeed(newSeed);
  }

  /// Convenience for callers (e.g. `relay_server_setup_screen.dart`) that
  /// only need the public key to send to the relay, base64-encoded (raw
  /// 32-byte X25519 public key bytes).
  Future<String> ensurePublicKeyBase64() async {
    final keyPair = await loadOrCreateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Whether a keypair has already been generated for this device, without
  /// generating one as a side effect (unlike [loadOrCreateKeyPair]).
  Future<bool> hasKeypair() async => (await _readSeed()) != null;

  /// Generates a brand-new candidate keypair WITHOUT persisting it yet.
  ///
  /// Used by the account-recovery flow (`recovery_code_screen.dart`): per
  /// docs/PLAN.md, a device that lost its original private key reactivates
  /// its `frameId` on a new device by rotating to a fresh keypair. The old
  /// private key is not needed afterwards - the server rotates
  /// `frames.public_key` in the same call and discards any `config_pushes`
  /// that were encrypted for the old key (they are no longer decryptable by
  /// anyone once the private key is gone, which is the intended, safe
  /// outcome rather than a bug).
  ///
  /// Deliberately two-phase (generate, then [CandidateFrameKeypair.commit])
  /// rather than a single rotate-and-persist call: the candidate's private
  /// key lives only in memory until the *server* has actually accepted the
  /// new public key. If the recovery request fails (network error, wrong
  /// frame ID, rate limit, ...) the caller simply discards the candidate by
  /// never calling [CandidateFrameKeypair.commit] - any previously stored
  /// keypair is left completely untouched, so a failed recovery attempt
  /// never permanently destroys this device's existing identity.
  Future<CandidateFrameKeypair> generateCandidateKeypair() async {
    final seed = _seedGenerator();
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return CandidateFrameKeypair._(seed, base64Encode(publicKey.bytes), this, DateTime.now());
  }

  /// Deletes the locally stored keypair entirely. Mostly useful for tests;
  /// not part of any normal app flow (there is intentionally no "reset my
  /// keypair without rotating on the server" feature - that would silently
  /// desynchronize this device from `frames.public_key`).
  Future<void> forgetForTesting() => _storage.delete(key: _seedStorageKey);
}

/// A freshly generated keypair whose private key has NOT been persisted
/// yet - only [publicKeyBase64] exists anywhere outside this object until
/// [commit] is called.
///
/// Valid for [maxAge] (60 minutes) from generation. This bounds how long an
/// unpersisted private key may be held in memory (e.g. while a recovery
/// screen is waiting on a slow network call or a user who walked away) and
/// forces a fresh candidate - fresh key material - rather than committing
/// something that has been sitting in memory indefinitely. [commit] throws
/// a [StateError] once expired; the caller should call
/// [FrameKeypairStore.generateCandidateKeypair] again and retry.
class CandidateFrameKeypair {
  CandidateFrameKeypair._(this._seed, this.publicKeyBase64, this._store, this._generatedAt);

  final List<int> _seed;
  final String publicKeyBase64;
  final FrameKeypairStore _store;
  final DateTime _generatedAt;

  static const maxAge = Duration(minutes: 60);

  bool get isExpired => DateTime.now().difference(_generatedAt) > maxAge;

  /// Persists this candidate's private key, making it this device's new
  /// keypair. Call ONLY after the server has confirmed it accepted
  /// [publicKeyBase64] (e.g. a successful `recoverFrame`/`registerFrame`
  /// response) - never speculatively before that call, and never if the
  /// call failed.
  Future<void> commit() async {
    if (isExpired) {
      throw StateError(
        'CandidateFrameKeypair expired (older than ${maxAge.inMinutes} min) - '
        'generate a new candidate instead of committing a stale one.',
      );
    }
    await _store._writeSeed(_seed);
  }
}
