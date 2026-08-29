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
