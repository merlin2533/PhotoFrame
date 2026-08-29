import crypto from 'node:crypto';

/**
 * Derives the out-of-band TOFU (trust-on-first-use) key fingerprint for a
 * frame's public key, per docs/PLAN.md "Relay-Server: Datenmodell & Ablauf"
 * point 9 (Key-Fingerprint-Verifikation).
 *
 * Threat model: the relay operator (or an attacker with DB access) controls
 * `frames.public_key` and could substitute it server-side to intercept
 * config-push payloads (e.g. SMB credentials) meant for a different frame.
 * The fingerprint itself travels over an out-of-band channel the relay does
 * NOT control (the pairing QR/deep-link `&fp=<fingerprint>`), so a receiving
 * client can compare what the server later claims is a frame's public_key
 * against the fingerprint it captured at pairing time - a server-side key
 * swap changes the fingerprint and becomes detectable.
 *
 * This module only derives the fingerprint from a given public key; it is
 * intentionally the single place that does so (SHA-256 + Crockford Base32),
 * used identically by pairing.ts (create-code / GET /:pairingId) and
 * recovery.ts, so the three call sites can never drift out of sync.
 */

// Crockford Base32 alphabet: excludes I, L, O, U to avoid visual confusion
// when a human reads/types the fingerprint (matches the alphabet already
// used for pairing codes in auth/pairingCode.ts).
const CROCKFORD_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const FINGERPRINT_LENGTH = 8; // 8 chars * 5 bits = 40 bits = first 5 bytes of the SHA-256 digest

/**
 * Computes the 8-character Crockford-Base32 fingerprint of a frame's public
 * key. Returns null when there is no public key yet (e.g. a frame created
 * before it ever completed its keypair setup / config-push handshake) -
 * callers must treat null as "no fingerprint available yet", not as an
 * error, and should surface that explicitly to API consumers.
 */
export function deriveKeyFingerprint(publicKey: string | null | undefined): string | null {
  if (!publicKey) return null;

  const digest = crypto.createHash('sha256').update(publicKey).digest();

  let out = '';
  for (let i = 0; i < FINGERPRINT_LENGTH; i++) {
    // Walk the digest 5 bits at a time, starting from the most significant
    // bit of the first byte, across a 40-bit (5-byte) window.
    const bitOffset = i * 5;
    const byteIndex = Math.floor(bitOffset / 8);
    const bitIndexInByte = bitOffset % 8;

    // Read up to 2 bytes as a 16-bit window so a 5-bit group that spans a
    // byte boundary can still be extracted in one shift.
    const window = (digest[byteIndex] << 8) | (digest[byteIndex + 1] ?? 0);
    const shift = 8 - bitIndexInByte - 5 + 8; // position the 5 bits we want at the low end
    const fiveBits = (window >> shift) & 0b11111;

    out += CROCKFORD_ALPHABET[fiveBits];
  }

  return out;
}
