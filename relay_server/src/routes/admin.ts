import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb } from '../db';
import { requireAdminAuth } from '../middleware/adminGuard';
import { signAdminToken, verifyAdminCredentials } from '../auth/adminAuth';
import { authRateLimiter } from '../middleware/rateLimit';
import { runGarbageCollection } from '../storage/contentAddressedStore';

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

adminRouter.delete('/users/:userId', (req, res) => {
  const db = getDb();
  db.prepare('DELETE FROM users WHERE id = ?').run(req.params.userId);
  audit('admin', 'delete_user', 'user', req.params.userId);
  res.json({ ok: true });
});

adminRouter.delete('/images/:imageId', (req, res) => {
  const db = getDb();
  const image = db.prepare('SELECT content_hash FROM images WHERE id = ?').get(req.params.imageId) as
    | { content_hash: string }
    | undefined;
  if (image) {
    db.prepare('DELETE FROM images WHERE id = ?').run(req.params.imageId);
    db.prepare('UPDATE blobs SET refcount = MAX(refcount - 1, 0) WHERE hash = ?').run(image.content_hash);
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

adminRouter.get('/audit', (_req, res) => {
  const db = getDb();
  const entries = db.prepare('SELECT * FROM admin_audit ORDER BY at DESC LIMIT 200').all();
  res.json({ entries });
});
