import { Router } from 'express';
import { getDb, runInTransaction } from '../db';
import { requireUserAuth } from '../middleware/authGuard';
import { releaseBlobRef } from '../storage/contentAddressedStore';

export const accountRouter = Router();

accountRouter.use(requireUserAuth);

/** DSGVO/GDPR data export: dumps everything tied to the calling account. */
accountRouter.get('/export', (req, res) => {
  const db = getDb();
  const user = db
    .prepare('SELECT id, username, created_at FROM users WHERE id = ?')
    .get(req.userId!);
  const frames = db.prepare('SELECT * FROM frames WHERE user_id = ?').all(req.userId!) as { id: string }[];
  const frameIds = frames.map((f) => f.id);

  let pairingMemberships: unknown[] = [];
  let images: unknown[] = [];
  if (frameIds.length > 0) {
    const placeholders = frameIds.map(() => '?').join(',');
    pairingMemberships = db
      .prepare(`SELECT * FROM pairing_members WHERE frame_id IN (${placeholders})`)
      .all(...frameIds);
    images = db
      .prepare(`SELECT id, pairing_id, uploaded_at, width, height FROM images WHERE uploaded_by_frame_id IN (${placeholders})`)
      .all(...frameIds);
  }

  res.json({ user, frames, pairingMemberships, images });
});

/**
 * DSGVO/GDPR account deletion: removes the user, cascades to frames and
 * their memberships/tokens (FK ON DELETE CASCADE), and releases blob
 * refcounts for every image the account's frames uploaded. Actual file
 * unlinking happens later via the separate GC job.
 */
accountRouter.delete('/', (req, res) => {
  const db = getDb();

  const frames = db.prepare('SELECT id FROM frames WHERE user_id = ?').all(req.userId!) as { id: string }[];

  runInTransaction(db, () => {
    for (const frame of frames) {
      const images = db
        .prepare('SELECT content_hash FROM images WHERE uploaded_by_frame_id = ?')
        .all(frame.id) as { content_hash: string }[];
      for (const image of images) {
        releaseBlobRef(image.content_hash);
      }
    }
    db.prepare('DELETE FROM users WHERE id = ?').run(req.userId!);
  });

  res.json({ ok: true });
});
