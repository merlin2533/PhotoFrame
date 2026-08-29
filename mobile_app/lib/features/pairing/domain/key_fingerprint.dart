import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Outcome of comparing a freshly-observed key fingerprint for a frame
/// against what this device has previously trusted for that same frame id.
///
/// This implements the client half of TOFU (trust-on-first-use) per
/// docs/PLAN.md "Relay-Server: Datenmodell & Ablauf" point 9. The relay
/// server computes and exposes fingerprints (see
/// relay_server/src/auth/keyFingerprint.ts) but deliberately does not - and
/// cannot - judge whether a change is expected: only the client that
/// captured a fingerprint out-of-band (via the pairing QR/deep-link's `fp`
/// parameter) is in a position to notice a mismatch.
enum FingerprintTrust {
  /// No fingerprint had been stored for this frame yet; the given one has
  /// now been recorded as trusted. Expected on first contact with a frame
  /// (e.g. right after redeeming a pairing code/QR).
  trusted,

  /// The given fingerprint equals the one already stored for this frame.
  /// Safe to proceed.
  match,

  /// The given fingerprint does NOT match the one already stored for this
  /// frame. This is either a legitimate key rotation (the frame went
  /// through `/frames/:id/recover` after losing its private key) or a
  /// server-side/MITM substitution of that frame's public key - the app
  /// cannot tell the difference on its own and MUST NOT silently accept
  /// it.
  mismatch,
}

/// User-facing warning text shown before a mismatched fingerprint is
/// accepted. Centralized here (rather than duplicated across the
/// confirmation screens that need it) so the wording used for a genuinely
/// security-relevant decision can't drift between call sites.
const String kFingerprintMismatchWarning =
    'Der Sicherheitsschlüssel von Frame XY hat sich geändert. Das kann '
    'bedeuten, dass das Gerät neu eingerichtet wurde (normal nach '
    "'Wiederherstellung') ODER dass jemand versucht, sich als dieses Gerät "
    'auszugeben. Nur bestätigen, wenn du sicher bist.';

/// Fills in the frame's display name into [kFingerprintMismatchWarning].
String fingerprintMismatchWarningFor(String frameLabel) =>
    kFingerprintMismatchWarning.replaceFirst('Frame XY', frameLabel);

/// Manages the locally-stored trust map of `frameId -> fingerprint` and
/// implements the TOFU decision described by [FingerprintTrust].
///
/// This class only contains domain/state logic - no UI. Callers (the
/// pairing UI, `SlideshowEngine`'s config-push handling, etc.) MUST call
/// [checkOrTrust] before applying anything that arrived tied to a given
/// frame id (a config-push payload, a newly displayed shared-album member,
/// ...), and on [FingerprintTrust.mismatch] MUST surface
/// [fingerprintMismatchWarningFor] and require explicit user confirmation
/// (see `config_push_confirmation_screen.dart`) before calling
/// [acceptFingerprint] to trust the new value. Never call
/// [acceptFingerprint] automatically on a mismatch.
class KeyFingerprintStore {
  KeyFingerprintStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'pf_trusted_fingerprint_';

  String _storageKey(String frameId) => '$_keyPrefix$frameId';

  /// Returns the fingerprint currently trusted for [frameId], or `null` if
  /// this device has never seen a fingerprint for that frame.
  Future<String?> trustedFingerprintFor(String frameId) => _storage.read(key: _storageKey(frameId));

  /// Compares [observedFingerprint] against the locally stored value for
  /// [frameId] and returns the outcome. On first contact
  /// ([FingerprintTrust.trusted]) the value is stored immediately - there is
  /// nothing to warn about yet, by definition. On [FingerprintTrust.match]
  /// or [FingerprintTrust.mismatch] nothing is written; a mismatch is only
  /// persisted once the caller explicitly calls [acceptFingerprint].
  ///
  /// A `null` [observedFingerprint] (the frame has no public_key yet on the
  /// server) is never trusted or compared - it always returns
  /// [FingerprintTrust.mismatch]-safe handling is the caller's job for that
  /// case; this method simply refuses to establish or match against an
  /// absent fingerprint by throwing [ArgumentError], since silently
  /// treating "no key yet" as "trusted" would defeat the whole point of
  /// TOFU.
  Future<FingerprintTrust> checkOrTrust(String frameId, String observedFingerprint) async {
    if (observedFingerprint.isEmpty) {
      throw ArgumentError.value(observedFingerprint, 'observedFingerprint', 'must not be empty');
    }

    final stored = await trustedFingerprintFor(frameId);
    if (stored == null) {
      await _storage.write(key: _storageKey(frameId), value: observedFingerprint);
      return FingerprintTrust.trusted;
    }
    if (stored == observedFingerprint) {
      return FingerprintTrust.match;
    }
    return FingerprintTrust.mismatch;
  }

  /// Explicitly trusts [newFingerprint] for [frameId] after the user has
  /// confirmed the [kFingerprintMismatchWarning] dialog following a
  /// [FingerprintTrust.mismatch]. Overwrites whatever was previously
  /// trusted.
  Future<void> acceptFingerprint(String frameId, String newFingerprint) =>
      _storage.write(key: _storageKey(frameId), value: newFingerprint);

  /// Forgets the trusted fingerprint for [frameId] (e.g. the pairing was
  /// left/deleted). Mostly useful for tests and cleanup; not required for
  /// correct TOFU behaviour.
  Future<void> forget(String frameId) => _storage.delete(key: _storageKey(frameId));
}
