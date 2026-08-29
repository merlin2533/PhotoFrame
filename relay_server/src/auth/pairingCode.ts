import crypto from 'node:crypto';
import { env } from '../config/env';

const CODE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // no 0/O/1/I to avoid confusion
const CODE_LENGTH = 8;

/**
 * Generates a random human-typeable pairing code, e.g. "7K4P-9QRT".
 */
export function generatePairingCode(): string {
  const bytes = crypto.randomBytes(CODE_LENGTH);
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/**
 * HMAC-SHA256(pepper, code) - deterministic and indexable so redemption can
 * look codes up by their hash directly (unlike bcrypt, which is intentionally
 * not doable). The pepper is never stored alongside the hash.
 */
export function hashPairingCode(code: string): string {
  const normalized = code.trim().toUpperCase();
  return crypto.createHmac('sha256', env.PAIRING_CODE_PEPPER).update(normalized).digest('hex');
}
