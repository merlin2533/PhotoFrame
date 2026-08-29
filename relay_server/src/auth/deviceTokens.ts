import crypto from 'node:crypto';
import { v4 as uuidv4 } from 'uuid';
import { getDb } from '../db';

/**
 * Device tokens authenticate a paired frame (as opposed to a user account).
 * The raw token is only ever returned once, at issuance; we persist a
 * SHA-256 hash so a DB leak does not expose usable tokens.
 */

function hashToken(rawToken: string): string {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

export interface IssuedDeviceToken {
  id: string;
  rawToken: string;
}

export function issueDeviceToken(frameId: string): IssuedDeviceToken {
  const db = getDb();
  const id = uuidv4();
  const rawToken = `${id}.${crypto.randomBytes(32).toString('base64url')}`;
  const tokenHash = hashToken(rawToken);

  db.prepare(
    'INSERT INTO device_tokens (id, frame_id, token_hash) VALUES (?, ?, ?)',
  ).run(id, frameId, tokenHash);

  return { id, rawToken };
}

export interface DeviceTokenRow {
  id: string;
  frame_id: string;
  token_hash: string;
  last_seen_at: string | null;
  revoked_at: string | null;
  created_at: string;
}

export function verifyDeviceToken(rawToken: string): DeviceTokenRow | null {
  const db = getDb();
  const tokenHash = hashToken(rawToken);
  const row = db
    .prepare('SELECT * FROM device_tokens WHERE token_hash = ?')
    .get(tokenHash) as DeviceTokenRow | undefined;

  if (!row || row.revoked_at) return null;

  db.prepare(
    'UPDATE device_tokens SET last_seen_at = strftime(\'%Y-%m-%dT%H:%M:%fZ\', \'now\') WHERE id = ?',
  ).run(row.id);
  db.prepare(
    'UPDATE frames SET last_seen_at = strftime(\'%Y-%m-%dT%H:%M:%fZ\', \'now\') WHERE id = ?',
  ).run(row.frame_id);

  return row;
}

export function revokeDeviceToken(tokenId: string): void {
  const db = getDb();
  db.prepare(
    'UPDATE device_tokens SET revoked_at = strftime(\'%Y-%m-%dT%H:%M:%fZ\', \'now\') WHERE id = ?',
  ).run(tokenId);
}

export function revokeAllTokensForFrame(frameId: string): void {
  const db = getDb();
  db.prepare(
    "UPDATE device_tokens SET revoked_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE frame_id = ? AND revoked_at IS NULL",
  ).run(frameId);
}
