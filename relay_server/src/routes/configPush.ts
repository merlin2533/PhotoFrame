import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb } from '../db';
import { requireDeviceAuth } from '../middleware/authGuard';
import { getIo } from '../realtime/socket';

export const configPushRouter = Router();

configPushRouter.use(requireDeviceAuth);

const pushSchema = z.object({
  targetFrameId: z.string().min(1),
  ciphertext: z.string().min(1),
});

/**
 * Pushes an end-to-end encrypted config blob to another frame in a shared
 * pairing. The relay never sees plaintext - `ciphertext` is opaque to it.
 */
configPushRouter.post('/', (req, res) => {
  const parsed = pushSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  const db = getDb();
  const { targetFrameId, ciphertext } = parsed.data;

  const sharedPairing = db
    .prepare(
      `SELECT pm1.pairing_id FROM pairing_members pm1
       JOIN pairing_members pm2 ON pm1.pairing_id = pm2.pairing_id
       WHERE pm1.frame_id = ? AND pm2.frame_id = ?`,
    )
    .get(req.frameId!, targetFrameId);

  if (!sharedPairing) {
    res.status(403).json({ error: 'target frame is not in a shared pairing' });
    return;
  }

  const id = uuidv4();
  db.prepare(
    'INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext) VALUES (?, ?, ?, ?)',
  ).run(id, targetFrameId, req.frameId!, ciphertext);

  getIo()?.to(`frame:${targetFrameId}`).emit('config_push', { id, senderFrameId: req.frameId });

  res.status(201).json({ id });
});

/** Polls for pending (not yet applied/rejected) config pushes targeting the caller. */
configPushRouter.get('/pending', (req, res) => {
  const db = getDb();
  const pushes = db
    .prepare(
      'SELECT id, sender_frame_id, ciphertext, created_at FROM config_pushes WHERE target_frame_id = ? AND applied_at IS NULL AND rejected_at IS NULL',
    )
    .all(req.frameId!);
  res.json({ pushes });
});

configPushRouter.post('/:pushId/ack', (req, res) => {
  const db = getDb();
  const push = db.prepare('SELECT * FROM config_pushes WHERE id = ?').get(req.params.pushId) as
    | { id: string; target_frame_id: string }
    | undefined;

  if (!push || push.target_frame_id !== req.frameId) {
    res.status(404).json({ error: 'not found' });
    return;
  }

  db.prepare(
    "UPDATE config_pushes SET applied_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?",
  ).run(req.params.pushId);
  res.json({ ok: true });
});
