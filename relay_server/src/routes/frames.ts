import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb } from '../db';
import { requireUserAuth } from '../middleware/authGuard';
import { issueDeviceToken } from '../auth/deviceTokens';
import { recoverFrame, RecoveryError } from '../auth/recovery';
import { recoveryRateLimiter } from '../middleware/rateLimit';

export const framesRouter = Router();

framesRouter.use(requireUserAuth);

const createFrameSchema = z.object({
  displayName: z.string().min(1).max(128),
  publicKey: z.string().min(16),
});

/** Registers a brand-new frame device belonging to the calling user. */
framesRouter.post('/', (req, res) => {
  const parsed = createFrameSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request', details: parsed.error.flatten() });
    return;
  }

  const db = getDb();
  const id = uuidv4();
  db.prepare(
    'INSERT INTO frames (id, user_id, display_name, public_key) VALUES (?, ?, ?, ?)',
  ).run(id, req.userId!, parsed.data.displayName, parsed.data.publicKey);

  const deviceToken = issueDeviceToken(id);

  res.status(201).json({
    frameId: id,
    deviceToken: deviceToken.rawToken,
  });
});

framesRouter.get('/', (req, res) => {
  const db = getDb();
  const frames = db
    .prepare('SELECT id, display_name, public_key, created_at, last_seen_at FROM frames WHERE user_id = ?')
    .all(req.userId!);
  res.json({ frames });
});

const recoverSchema = z.object({
  newPublicKey: z.string().min(16),
});

/**
 * Key-rotation / recovery endpoint: reclaims an existing frame_id for a new
 * physical device after the old one lost its private key. See
 * src/auth/recovery.ts for the full semantics.
 */
framesRouter.post('/:frameId/recover', recoveryRateLimiter, (req, res) => {
  const parsed = recoverSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request', details: parsed.error.flatten() });
    return;
  }

  try {
    const result = recoverFrame(req.params.frameId, req.userId!, parsed.data.newPublicKey);
    res.json({
      frameId: result.frameId,
      deviceToken: result.deviceToken.rawToken,
    });
  } catch (err) {
    if (err instanceof RecoveryError) {
      res.status(err.statusCode).json({ error: err.message });
      return;
    }
    throw err;
  }
});
