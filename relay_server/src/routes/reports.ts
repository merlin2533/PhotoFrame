import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { getDb } from '../db';
import { requireDeviceAuth } from '../middleware/authGuard';

export const reportsRouter = Router();

reportsRouter.use(requireDeviceAuth);

const reportSchema = z.object({
  imageId: z.string().min(1),
  reason: z.string().min(1).max(500),
});

/** UGC moderation: lets a frame flag an image in a shared pairing for review. */
reportsRouter.post('/', (req, res) => {
  const parsed = reportSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'invalid request' });
    return;
  }

  const db = getDb();
  const image = db
    .prepare('SELECT pairing_id FROM images WHERE id = ?')
    .get(parsed.data.imageId) as { pairing_id: string } | undefined;

  if (!image) {
    res.status(404).json({ error: 'image not found' });
    return;
  }

  const membership = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(image.pairing_id, req.frameId!);
  if (!membership) {
    res.status(403).json({ error: 'not a member of this pairing' });
    return;
  }

  const id = uuidv4();
  db.prepare(
    'INSERT INTO reports (id, image_id, reporter_frame_id, reason) VALUES (?, ?, ?, ?)',
  ).run(id, parsed.data.imageId, req.frameId!, parsed.data.reason);

  res.status(201).json({ id });
});
