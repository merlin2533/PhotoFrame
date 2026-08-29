import { getDb, runInTransaction } from '../db';
import { issueDeviceToken, revokeAllTokensForFrame, type IssuedDeviceToken } from './deviceTokens';

export class RecoveryError extends Error {
  constructor(message: string, public statusCode = 400) {
    super(message);
  }
}

export interface RecoveryResult {
  frameId: string;
  deviceToken: IssuedDeviceToken;
}

/**
 * Recovers a lost/reset frame device.
 *
 * IMPORTANT: this binds the EXISTING frame_id to the new device instead of
 * creating a new frame row. The device's original private key is assumed
 * lost, so the client generates a fresh keypair and sends only the new
 * public key, which overwrites frames.public_key. Because the frame can no
 * longer decrypt anything encrypted under its old key, every config_push
 * still pending for it is marked rejected_at (not deleted, for audit) and
 * all previously issued device tokens for the frame are revoked.
 */
export function recoverFrame(
  frameId: string,
  userId: string,
  newPublicKey: string,
): RecoveryResult {
  const db = getDb();

  const frame = db
    .prepare('SELECT id, user_id FROM frames WHERE id = ?')
    .get(frameId) as { id: string; user_id: string } | undefined;

  if (!frame) {
    throw new RecoveryError('unknown frame', 404);
  }
  if (frame.user_id !== userId) {
    throw new RecoveryError('frame does not belong to this account', 403);
  }
  if (!newPublicKey || newPublicKey.length < 16) {
    throw new RecoveryError('a valid new public key is required', 400);
  }

  runInTransaction(db, () => {
    // Bind the existing frame_id to the new key material. No new frame row.
    db.prepare('UPDATE frames SET public_key = ? WHERE id = ?').run(newPublicKey, frameId);

    // Any config push still pending for the old key can never be decrypted
    // by the recovered device - reject it explicitly rather than leaving it
    // stuck in limbo.
    db.prepare(
      `UPDATE config_pushes
       SET rejected_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
       WHERE target_frame_id = ? AND applied_at IS NULL AND rejected_at IS NULL`,
    ).run(frameId);

    // Old device tokens were issued to a device that no longer holds a
    // usable private key; revoke them so a stolen/lost device cannot keep
    // acting as this frame.
    revokeAllTokensForFrame(frameId);
  });

  const deviceToken = issueDeviceToken(frameId);

  return { frameId, deviceToken };
}
