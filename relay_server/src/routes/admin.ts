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
    .prepare('SELECT id, user_id, display_name, created_at, last_seen_at FROM frames ORDER BY created_at DESC')
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
