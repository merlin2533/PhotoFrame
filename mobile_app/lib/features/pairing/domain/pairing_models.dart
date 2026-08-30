import 'key_fingerprint.dart';

/// Role of a frame within a pairing, mirrored from `pairing_members.role`
/// on the relay (`'owner' | 'member'`).
enum PairingRole { owner, member }

PairingRole pairingRoleFromWire(String role) => role == 'owner' ? PairingRole.owner : PairingRole.member;

/// One member (frame) of a [Pairing], as last observed from the relay.
class PairingMember {
  const PairingMember({
    required this.frameId,
    required this.role,
    required this.joinedAt,
    required this.keyFingerprint,
    this.publicKey,
  });

  final String frameId;
  final PairingRole role;
  final DateTime joinedAt;

  /// The member's current key fingerprint as reported by the relay right
  /// now (`null` if that frame has no public_key yet). Compare against
  /// [KeyFingerprintStore] to detect an unexpected change - this class
  /// intentionally does not embed a trust verdict itself, since the same
  /// [PairingMember] snapshot may be checked at different times with
  /// different outcomes.
  final String? keyFingerprint;

  /// The member's raw base64 X25519 public key, needed to actually encrypt
  /// a config-push to this frame (see `config_push_crypto.dart`) - the
  /// fingerprint alone is one-way and cannot be used for encryption.
  ///
  /// SERVER GAP: as of this writing, `GET /pairing/:id`
  /// (relay_server/src/routes/pairing.ts) only returns each member's
  /// *derived* `keyFingerprint`, not the raw `public_key` column. This
  /// field is wired up to parse a `publicKey` property if/when the server
  /// starts sending one (see [PairingMemberInfo.publicKey] in
  /// `relay_api_client.dart`), but will be `null` against the current
  /// server - `sendEncryptedConfigPush` fails clearly in that case rather
  /// than silently sending plaintext or garbage. Sending the raw public
  /// key over the same channel as the fingerprint is fine security-wise:
  /// the public key is, by definition, public - only the out-of-band
  /// fingerprint check protects against a substituted key.
  final String? publicKey;

  bool get isOwner => role == PairingRole.owner;
}

/// A pairing (one "PhotoFrame + companions" group) and its current
/// members, as last fetched from `GET /pairing/:id`.
class Pairing {
  const Pairing({required this.id, required this.name, required this.members});

  final String id;
  final String name;
  final List<PairingMember> members;

  PairingMember? memberById(String frameId) {
    for (final m in members) {
      if (m.frameId == frameId) return m;
    }
    return null;
  }

  bool isOwnedBy(String frameId) => memberById(frameId)?.isOwner ?? false;
}

/// A freshly created invite, ready to be shown as a QR code / deep link.
class PairingInvite {
  const PairingInvite({
    required this.pairingId,
    required this.code,
    required this.expiresAt,
    required this.fingerprint,
    this.fingerprintReason,
    this.registrationInviteCode,
  });

  final String pairingId;
  final String code;
  final DateTime expiresAt;

  /// TOFU fingerprint of the frame that created this invite, to travel
  /// out-of-band via the QR/deep-link's `fp` parameter. `null` when that
  /// frame has no public_key yet (see [fingerprintReason]).
  final String? fingerprint;
  final String? fingerprintReason;

  /// Server registration invite code (`REGISTRATION_INVITE_CODE`), needed
  /// only when the scanning device doesn't have a relay account yet and
  /// must call `/auth/register`. `null`/empty when the relay has open
  /// registration.
  final String? registrationInviteCode;

  /// Builds the `photoframe://pair?...` deep link per docs/PLAN.md
  /// "Relay-Server: Datenmodell & Ablauf" point 2:
  /// `u=<relay>&c=<code>&i=<invite>&fp=<fingerprint>`.
  Uri toDeepLink({required String relayUrl}) {
    return Uri(
      scheme: 'photoframe',
      host: 'pair',
      queryParameters: {
        'u': relayUrl,
        'c': code,
        if (registrationInviteCode != null && registrationInviteCode!.isNotEmpty)
          'i': registrationInviteCode,
        if (fingerprint != null) 'fp': fingerprint,
      },
    );
  }

  /// Parses a `photoframe://pair?...` deep link (e.g. from a scanned QR
  /// code). Returns `null` if [uri] isn't a recognizable pairing link.
  /// The returned invite has [pairingId] left empty - it isn't known until
  /// the code is redeemed - callers should only use [code], [fingerprint],
  /// [registrationInviteCode] and the relay URL (`u`) from a parsed link.
  static ParsedPairingLink? tryParse(Uri uri) {
    if (uri.scheme != 'photoframe' || uri.host != 'pair') return null;
    final params = uri.queryParameters;
    final relayUrl = params['u'];
    final code = params['c'];
    if (relayUrl == null || relayUrl.isEmpty || code == null || code.isEmpty) return null;

    return ParsedPairingLink(
      relayUrl: relayUrl,
      code: code,
      fingerprint: (params['fp']?.isEmpty ?? true) ? null : params['fp'],
      registrationInviteCode: (params['i']?.isEmpty ?? true) ? null : params['i'],
    );
  }
}

/// Result of parsing a scanned pairing deep link, before redemption.
class ParsedPairingLink {
  const ParsedPairingLink({
    required this.relayUrl,
    required this.code,
    required this.fingerprint,
    required this.registrationInviteCode,
  });

  final String relayUrl;
  final String code;
  final String? fingerprint;
  final String? registrationInviteCode;
}

/// Outcome of redeeming a pairing invite, folding in the client-side TOFU
/// check against the invite's out-of-band fingerprint (see
/// key_fingerprint.dart doc comments for the full threat model).
enum RedeemOutcome {
  /// The invite carried no fingerprint (inviting frame has no public_key
  /// yet) - nothing to verify. Legitimate but weaker: config-push TOFU
  /// protection for that frame only starts once it later gets a key.
  noFingerprintInLink,

  /// Exactly one current member's server-reported fingerprint matches the
  /// link's fingerprint, and this device had never seen that frame before:
  /// trusted and stored.
  verifiedNewTrust,

  /// The matched member's fingerprint equals what this device already had
  /// stored for it: consistent, no action needed.
  verifiedMatchesExistingTrust,

  /// The matched member's fingerprint differs from what this device had
  /// previously stored for that same frame id. Could be a legitimate key
  /// rotation (recovery) - the caller MUST warn and require explicit
  /// confirmation (`config_push_confirmation_screen.dart`'s pattern)
  /// before calling [KeyFingerprintStore.acceptFingerprint].
  verifiedButLocalTrustMismatch,

  /// No current member's server-reported fingerprint matches the link's
  /// fingerprint at all. This is more alarming than a simple mismatch: it
  /// means either the invite is stale (the inviting frame's key changed
  /// after the QR was generated) or the relay is misreporting member keys.
  /// The app must not silently proceed.
  noMatchingMember,
}

class RedeemResult {
  const RedeemResult({
    required this.pairingId,
    required this.outcome,
    this.matchedFrameId,
    this.matchedFingerprint,
  });

  final String pairingId;
  final RedeemOutcome outcome;

  /// The frame id identified as the inviter, when [outcome] is one of the
  /// `verified*` values.
  final String? matchedFrameId;
  final String? matchedFingerprint;

  bool get requiresUserConfirmation =>
      outcome == RedeemOutcome.verifiedButLocalTrustMismatch || outcome == RedeemOutcome.noMatchingMember;
}

/// A pending config-push, joined with the client-side TOFU verdict for its
/// sender so the confirmation UI can render the right warning level
/// without re-deriving it.
class PendingConfigPush {
  const PendingConfigPush({
    required this.id,
    required this.senderFrameId,
    required this.ciphertext,
    required this.createdAt,
    required this.senderFingerprint,
    required this.trust,
  });

  final String id;
  final String senderFrameId;
  final String ciphertext;
  final DateTime createdAt;

  /// The sender's CURRENT fingerprint as reported by the relay at the time
  /// this push was fetched.
  final String? senderFingerprint;

  /// TOFU verdict for [senderFingerprint] against what was previously
  /// trusted for [senderFrameId]. `null` if [senderFingerprint] itself is
  /// `null` (sender has no public key - config-push should not be trusted
  /// at all in that case; treat like [FingerprintTrust.mismatch]).
  final FingerprintTrust? trust;

  bool get isSafeToAutoDisplay => trust == FingerprintTrust.match;
}

/// A recipient resolved for an about-to-be-sent config-push, together with
/// the client-side TOFU verdict for its current fingerprint - the
/// sending-side mirror of [PendingConfigPush]/[FingerprintTrust] used on
/// receipt. [publicKey] and [fingerprint] are read from the very same
/// `GET /pairing/:id` snapshot so they are guaranteed to describe the same
/// server-side state (a relay operator cannot hand out a substituted public
/// key alongside a stale/unrelated fingerprint).
class ConfigPushRecipient {
  const ConfigPushRecipient({
    required this.frameId,
    required this.publicKey,
    required this.fingerprint,
    required this.trust,
  });

  final String frameId;

  /// Raw base64 X25519 public key to encrypt to, or `null` if the relay
  /// has no key on file yet for this frame (see [PairingMember.publicKey]).
  final String? publicKey;

  /// The recipient's CURRENT fingerprint as reported by the relay at the
  /// time this was resolved.
  final String? fingerprint;

  /// TOFU verdict for [fingerprint] against what was previously trusted for
  /// [frameId]. `null` if [fingerprint] itself is `null` (recipient has no
  /// public key - nothing to verify, and nothing safe to encrypt to
  /// either).
  final FingerprintTrust? trust;

  /// Whether encryption may proceed without further user confirmation:
  /// either first contact ([FingerprintTrust.trusted]) or an unchanged,
  /// already-trusted key ([FingerprintTrust.match]). A [FingerprintTrust
  /// .mismatch] (or no fingerprint at all) MUST NOT be encrypted to without
  /// the user explicitly confirming the warning first (see
  /// `send_config_push_screen.dart`).
  bool get isSafeToSend => trust == FingerprintTrust.trusted || trust == FingerprintTrust.match;
}
