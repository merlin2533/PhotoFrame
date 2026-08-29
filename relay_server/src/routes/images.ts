import fs from 'node:fs';
import path from 'node:path';
import { Router } from 'express';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { env, UPLOAD_TMP_DIR } from '../config/env';
import { getDb, runInTransaction } from '../db';
import { requireDeviceAuth, requirePairingMembership } from '../middleware/authGuard';
import { checkUploadQuota, QuotaError } from '../middleware/quota';
import { commitBlob, originalPath, releaseBlobRef, thumbPath } from '../storage/contentAddressedStore';
import { processImage } from '../storage/thumbnails';

export const imagesRouter = Router();

imagesRouter.use(requireDeviceAuth);

const ALLOWED_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']);

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOAD_TMP_DIR),
    filename: (_req, _file, cb) => cb(null, `${uuidv4()}.tmp`),
  }),
  limits: { fileSize: env.MAX_UPLOAD_BYTES },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_MIME_TYPES.has(file.mimetype)) {
      cb(new Error('unsupported file type'));
      return;
    }
    cb(null, true);
  },
});

const uploadMetaSchema = z.object({
  pairingId: z.string().min(1),
  clientUploadId: z.string().min(1),
});

/**
 * Uploads an image into a pairing. The uploaded file is first buffered to a
 * temp file on disk by multer, then re-encoded (EXIF/GPS stripped, rotated,
 * thumbnailed) and committed into the content-addressed blob store via an
 * atomic rename. client_upload_id gives idempotent retries.
 */
imagesRouter.post('/', upload.single('file'), async (req, res, next) => {
  const parsed = uploadMetaSchema.safeParse(req.body);
  if (!parsed.success || !req.file) {
    if (req.file) fs.unlinkSync(req.file.path);
    res.status(400).json({ error: 'invalid request: pairingId, clientUploadId and file are required' });
    return;
  }

  const { pairingId, clientUploadId } = parsed.data;
  const db = getDb();

  const membership = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, req.frameId!);
  if (!membership) {
    fs.unlinkSync(req.file.path);
    res.status(403).json({ error: 'not a member of this pairing' });
    return;
  }

  const existingByClientId = db
    .prepare('SELECT id FROM images WHERE client_upload_id = ?')
    .get(clientUploadId) as { id: string } | undefined;
  if (existingByClientId) {
    fs.unlinkSync(req.file.path);
    res.status(200).json({ imageId: existingByClientId.id, deduped: true });
    return;
  }

  const frame = db
    .prepare('SELECT f.user_id FROM frames f WHERE f.id = ?')
    .get(req.frameId!) as { user_id: string } | undefined;

  try {
    if (frame) {
      checkUploadQuota(pairingId, frame.user_id, req.file.size);
    }

    const inputBuffer = fs.readFileSync(req.file.path);
    const processed = await processImage(inputBuffer);

    // Write the re-encoded original to a fresh temp file, then commit -
    // commitBlob hashes and atomically renames it into the blob store.
    const tmpOriginal = path.join(UPLOAD_TMP_DIR, `${uuidv4()}.orig.tmp`);
    fs.writeFileSync(tmpOriginal, processed.originalBuffer);
    const hash = commitBlob(tmpOriginal, processed.originalBuffer.length);

    // Thumbnail is derived and stored alongside; not part of the refcounted
    // dedup key, but named after the same hash for co-location/cleanup.
    fs.writeFileSync(thumbPath(hash), processed.thumbnailBuffer);

    fs.unlinkSync(req.file.path);

    const imageId = uuidv4();
    runInTransaction(db, () => {
      db.prepare(
        `INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, width, height, client_upload_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).run(imageId, pairingId, req.frameId!, hash, processed.width, processed.height, clientUploadId);

      if (frame) {
        db.prepare('UPDATE users SET storage_used_bytes = storage_used_bytes + ? WHERE id = ?').run(
          processed.originalBuffer.length,
          frame.user_id,
        );
      }
    });

    res.status(201).json({ imageId, contentHash: hash, width: processed.width, height: processed.height });
  } catch (err) {
    if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
    if (err instanceof QuotaError) {
      res.status(413).json({ error: err.message });
      return;
    }
    // Express 4 does not catch rejections from async handlers itself - pass
    // to next() explicitly so the central error handler responds instead of
    // the process crashing on an unhandled rejection (e.g. a corrupt image
    // that fails sharp processing).
    next(err);
  }
});

imagesRouter.get('/pairing/:pairingId', requirePairingMembership, (req, res) => {
  const db = getDb();
  const images = db
    .prepare(
      `SELECT i.id, i.uploaded_by_frame_id, i.uploaded_at, i.width, i.height, i.content_hash
       FROM images i
       WHERE i.pairing_id = ?
         AND NOT EXISTS (SELECT 1 FROM image_hidden h WHERE h.image_id = i.id AND h.frame_id = ?)
       ORDER BY i.uploaded_at DESC`,
    )
    .all(req.params.pairingId, req.frameId!);
  res.json({ images });
});

/** Loads an image row and 403s unless the calling frame is a member of its pairing. */
function loadImageForMember(
  req: Parameters<Parameters<typeof imagesRouter.get>[1]>[0],
  res: Parameters<Parameters<typeof imagesRouter.get>[1]>[1],
  imageId: string,
): { id: string; pairing_id: string; uploaded_by_frame_id: string; content_hash: string } | undefined {
  const db = getDb();
  const image = db.prepare('SELECT * FROM images WHERE id = ?').get(imageId) as
    | { id: string; pairing_id: string; uploaded_by_frame_id: string; content_hash: string }
    | undefined;

  if (!image) {
    res.status(404).json({ error: 'not found' });
    return undefined;
  }

  const membership = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(image.pairing_id, req.frameId!);
  if (!membership) {
    res.status(403).json({ error: 'not a member of this pairing' });
    return undefined;
  }

  return image;
}

/** Hides an image locally for the calling frame only (server-side, per-member). */
imagesRouter.post('/:imageId/hide', (req, res) => {
  const image = loadImageForMember(req, res, req.params.imageId);
  if (!image) return;

  getDb()
    .prepare('INSERT OR IGNORE INTO image_hidden (image_id, frame_id) VALUES (?, ?)')
    .run(image.id, req.frameId!);
  res.json({ ok: true });
});

imagesRouter.post('/:imageId/unhide', (req, res) => {
  const image = loadImageForMember(req, res, req.params.imageId);
  if (!image) return;

  getDb()
    .prepare('DELETE FROM image_hidden WHERE image_id = ? AND frame_id = ?')
    .run(image.id, req.frameId!);
  res.json({ ok: true });
});

/**
 * Deletes an image row and releases its blob refcount (GC runs separately).
 * Only the original uploader or a pairing `owner` may delete - any other
 * member can only hide the image locally via POST /:imageId/hide.
 */
imagesRouter.delete('/:imageId', (req, res) => {
  const image = loadImageForMember(req, res, req.params.imageId);
  if (!image) return;

  const db = getDb();
  const membership = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(image.pairing_id, req.frameId!) as { role: string } | undefined;

  const isUploader = image.uploaded_by_frame_id === req.frameId;
  const isOwner = membership?.role === 'owner';
  if (!isUploader && !isOwner) {
    res.status(403).json({ error: 'only the uploader or a pairing owner may delete this image' });
    return;
  }

  db.prepare('DELETE FROM images WHERE id = ?').run(image.id);
  releaseBlobRef(image.content_hash);

  res.json({ ok: true });
});

/**
 * Serves the re-encoded image bytes directly (never via express.static, so
 * we control headers precisely and never serve raw filesystem paths).
 */
imagesRouter.get('/:imageId/file', (req, res) => {
  const db = getDb();
  const image = db.prepare('SELECT * FROM images WHERE id = ?').get(req.params.imageId) as
    | { id: string; pairing_id: string; content_hash: string }
    | undefined;

  if (!image) {
    res.status(404).json({ error: 'not found' });
    return;
  }

  const membership = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(image.pairing_id, req.frameId!);
  if (!membership) {
    res.status(403).json({ error: 'not a member of this pairing' });
    return;
  }

  const wantsThumb = req.query.variant === 'thumb';
  const filePath = wantsThumb ? thumbPath(image.content_hash) : originalPath(image.content_hash);

  if (!fs.existsSync(filePath)) {
    res.status(404).json({ error: 'blob missing' });
    return;
  }

  const etag = `"${image.content_hash}${wantsThumb ? '-thumb' : ''}"`;
  res.set({
    'Content-Type': 'image/jpeg',
    'Cache-Control': 'public, max-age=31536000, immutable',
    ETag: etag,
    'X-Content-Type-Options': 'nosniff',
  });

  if (req.headers['if-none-match'] === etag) {
    res.status(304).end();
    return;
  }

  fs.createReadStream(filePath).pipe(res);
});
