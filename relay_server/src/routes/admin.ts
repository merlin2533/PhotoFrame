import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb, runInTransaction } from '../db';
import { requireAdminAuth } from '../middleware/adminGuard';
import { signAdminToken, verifyAdminCredentials } from '../auth/adminAuth';
import { authRateLimiter } from '../middleware/rateLimit';
import { runGarbageCollection } from '../storage/contentAddressedStore';
import { releaseImageAccounting } from '../storage/imageCleanup';
import { runBlobConsistencyCheck } from '../storage/blobConsistencyCheck';
import { revokeAllTokensForFrame } from '../auth/deviceTokens';

export const adminRouter = Router();

// Mutable in-process flag, initialized from env at boot, toggled at runtime
// by the admin panel. Deliberately not persisted to keep this simple; a
// restart reverts to the .env value.
let registrationEnabled: boolean | null = null;

export function isRegistrationEnabled(defaultValue: boolean): boolean {
  return registrationEnabled ?? defaultValue;
}

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
});

adminRouter.post('/login', authRateLimiter, (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  if (!verifyAdminCredentials(parsed.data.username, parsed.data.password)) {
    res.status(401).json({ error: 'invalid admin credentials' });
    return;
  }

  res.json({ token: signAdminToken() });
});

adminRouter.use(requireAdminAuth);

function audit(actor: string, action: string, targetType?: string, targetId?: string) {
  const db = getDb();
  db.prepare(
    'INSERT INTO admin_audit (id, actor, action, target_type, target_id) VALUES (?, ?, ?, ?, ?)',
  ).run(uuidv4(), actor, action, targetType ?? null, targetId ?? null);
}

adminRouter.get('/users', (_req, res) => {
  const db = getDb();
  const users = db
    .prepare('SELECT id, username, storage_used_bytes, created_at FROM users ORDER BY created_at DESC')
    .all();
  res.json({ users });
});

adminRouter.get('/frames', (_req, res) => {
  const db = getDb();
  const frames = db
    .prepare(
      'SELECT id, user_id, display_name, created_at, last_seen_at, deleted_at FROM frames ORDER BY created_at DESC',
    )
    .all();
  res.json({ frames });
});

adminRouter.get('/pairings', (_req, res) => {
  const db = getDb();
  const pairings = db.prepare('SELECT * FROM pairings ORDER BY created_at DESC').all();
  res.json({ pairings });
});

adminRouter.get('/reports', (_req, res) => {
  const db = getDb();
  const reports = db.prepare('SELECT * FROM reports ORDER BY created_at DESC').all();
  res.json({ reports });
});

/**
 * Deletes a user (and, via ON DELETE CASCADE, their frames/device tokens/
 * pairing memberships/images). ON DELETE CASCADE knows nothing about
 * blobs.refcount or other users' storage_used_bytes, so - like the pairing
 * cascade-delete in routes/pairing.ts - we select every affected image's
 * accounting BEFORE the cascade fires and release it in the same
 * transaction as the DELETE (previously a leak, Code-Review-Backlog).
 */
adminRouter.delete('/users/:userId', (req, res) => {
  const db = getDb();
  const frames = db.prepare('SELECT id FROM frames WHERE user_id = ?').all(req.params.userId) as {
    id: string;
  }[];

  let images: { content_hash: string; uploaded_by_frame_id: string }[] = [];
  if (frames.length > 0) {
    const placeholders = frames.map(() => '?').join(',');
    images = db
      .prepare(`SELECT content_hash, uploaded_by_frame_id FROM images WHERE uploaded_by_frame_id IN (${placeholders})`)
      .all(...frames.map((f) => f.id)) as { content_hash: string; uploaded_by_frame_id: string }[];
  }

  runInTransaction(db, () => {
    releaseImageAccounting(images);
    db.prepare('DELETE FROM users WHERE id = ?').run(req.params.userId);
  });
  audit('admin', 'delete_user', 'user', req.params.userId);
  res.json({ ok: true });
});

/**
 * Deletes/revokes a SINGLE frame - e.g. a lost device - without touching the
 * user's account, other frames, or any images.
 *
 * Unlike DELETE /users/:userId, this deliberately does NOT `DELETE FROM
 * frames`: `images.uploaded_by_frame_id` has `ON DELETE CASCADE` back to
 * `frames(id)` (001_init.sql), so removing the frame row would cascade into
 * deleting every image it ever uploaded - including images other members of
 * a shared pairing still see. That would turn "I lost my frame" into "my
 * pairing lost its photos", which is not what this endpoint is for.
 *
 * Instead the frame row is kept and marked `deleted_at` (003 migration),
 * and every OTHER frame-scoped side effect is cleaned up explicitly, in one
 * transaction:
 *  - device_tokens: revoked via the same revokeAllTokensForFrame() used by
 *    the account-recovery flow, so the lost device can no longer authenticate.
 *  - pairing_members: this frame's membership row(s) are removed, same as
 *    POST /:pairingId/leave / DELETE /:pairingId/members/:frameId in
 *    routes/pairing.ts - and, matching that existing pattern, a pairing is
 *    NOT auto-deleted just because this was its last member (neither of
 *    those routes does that either; only an explicit
 *    DELETE /:pairingId does).
 *  - config_pushes: rows where this frame is sender OR target are removed
 *    (both FKs cascade-delete on the frame today, but since the frame row
 *    itself is deliberately not deleted, they're cleaned up here instead).
 *  - image_hidden / reports: this frame's own rows are removed; the images
 *    themselves, and other frames' hidden-state/reports on them, are
 *    untouched.
 * `images.uploaded_by_frame_id` is intentionally left pointing at the now-
 * deleted frame - the images stay owned/visible exactly as before, so no
 * releaseImageAccounting() call is needed here (no image row is deleted).
 */
adminRouter.delete('/frames/:frameId', (req, res) => {
  const db = getDb();
  const frame = db.prepare('SELECT id, deleted_at FROM frames WHERE id = ?').get(req.params.frameId) as
    | { id: string; deleted_at: string | null }
    | undefined;

  if (!frame) {
    res.status(404).json({ error: 'frame not found' });
    return;
  }

  if (frame.deleted_at) {
    // Idempotent no-op rather than re-running the cleanup: without this, a
    // second click bumps deleted_at to "now" again (found in review),
    // making the audit trail lie about when the frame was actually
    // deactivated. Every side effect below was already applied by the
    // first delete.
    res.json({ ok: true, alreadyDeleted: true, deletedAt: frame.deleted_at });
    return;
  }

  runInTransaction(db, () => {
    revokeAllTokensForFrame(frame.id);
    db.prepare('DELETE FROM pairing_members WHERE frame_id = ?').run(frame.id);
    db.prepare('DELETE FROM config_pushes WHERE target_frame_id = ? OR sender_frame_id = ?').run(
      frame.id,
      frame.id,
    );
    db.prepare('DELETE FROM image_hidden WHERE frame_id = ?').run(frame.id);
    db.prepare('DELETE FROM reports WHERE reporter_frame_id = ?').run(frame.id);
    db.prepare("UPDATE frames SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?").run(
      frame.id,
    );
  });

  audit('admin', 'delete_frame', 'frame', frame.id);
  res.json({ ok: true });
});

adminRouter.delete('/images/:imageId', (req, res) => {
  const db = getDb();
  const image = db.prepare('SELECT content_hash, uploaded_by_frame_id FROM images WHERE id = ?').get(
    req.params.imageId,
  ) as { content_hash: string; uploaded_by_frame_id: string } | undefined;
  if (image) {
    runInTransaction(db, () => {
      db.prepare('DELETE FROM images WHERE id = ?').run(req.params.imageId);
      releaseImageAccounting([image]);
    });
    audit('admin', 'delete_image', 'image', req.params.imageId);
  }
  res.json({ ok: true });
});

const toggleSchema = z.object({ enabled: z.boolean() });

adminRouter.post('/registration', (req, res) => {
  const parsed = toggleSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }
  registrationEnabled = parsed.data.enabled;
  audit('admin', 'toggle_registration', 'setting', String(parsed.data.enabled));
  res.json({ registrationEnabled });
});

adminRouter.get('/registration', (_req, res) => {
  res.json({ registrationEnabled });
});

adminRouter.post('/gc', (_req, res) => {
  const result = runGarbageCollection();
  audit('admin', 'run_gc', 'system', undefined);
  res.json(result);
});

adminRouter.get('/blob-consistency-report', (_req, res) => {
  const report = runBlobConsistencyCheck();
  audit('admin', 'run_blob_consistency_check', 'system', undefined);
  res.json(report);
});

adminRouter.get('/audit', (_req, res) => {
  const db = getDb();
  const entries = db.prepare('SELECT * FROM admin_audit ORDER BY at DESC LIMIT 200').all();
  res.json({ entries });
});
