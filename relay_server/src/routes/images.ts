import fs from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { Router } from 'express';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { env, UPLOAD_TMP_DIR } from '../config/env';
import { getDb, runInTransaction } from '../db';
import { requireDeviceAuth, requirePairingMembership } from '../middleware/authGuard';
import { checkUploadQuota, QuotaError } from '../middleware/quota';
import { getIo } from '../realtime/socket';
import {
  commitBlobRow,
  originalPath,
  sha256Hex,
  storeBlobFiles,
  thumbPath,
} from '../storage/contentAddressedStore';
import { releaseImageAccounting } from '../storage/imageCleanup';
import { processImage } from '../storage/thumbnails';
import { buildPage, keysetClause, resolvePage } from '../util/pagination';
import { Semaphore } from '../util/semaphore';

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

// Decoding and re-encoding run inside this process, so a burst of uploads
// would otherwise all decode at once. Uploads beyond the limit wait in line.
const uploadSlots = new Semaphore(env.MAX_CONCURRENT_UPLOADS);

const uploadMetaSchema = z.object({
  pairingId: z.string().min(1),
  clientUploadId: z.string().min(1),
});

async function removeQuietly(filePath: string): Promise<void> {
  try {
    await fs.promises.unlink(filePath);
  } catch (err: any) {
    if (err.code !== 'ENOENT') {
      console.warn(`[images] could not remove temp file ${filePath}: ${err.message}`);
    }
  }
}

/**
 * Uploads an image into a pairing. The uploaded file is first buffered to a
 * temp file on disk by multer, then read once, re-encoded (EXIF/GPS stripped,
 * rotated, thumbnailed) and committed into the content-addressed blob store
 * via an atomic rename. client_upload_id gives idempotent retries.
 */
imagesRouter.post('/', upload.single('file'), async (req, res, next) => {
  const parsed = uploadMetaSchema.safeParse(req.body);
  if (!parsed.success || !req.file) {
    if (req.file) await removeQuietly(req.file.path);
    res.status(400).json({ error: 'invalid request: pairingId, clientUploadId and file are required' });
    return;
  }

  const { pairingId, clientUploadId } = parsed.data;
  const db = getDb();

  const membership = db
    .prepare('SELECT role FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, req.frameId!);
  if (!membership) {
    await removeQuietly(req.file.path);
    res.status(403).json({ error: 'not a member of this pairing' });
    return;
  }

  // Scoped to the uploading frame (see migrations/002_scope_client_upload_id.sql):
  // client_upload_id is only unique per-frame now, so the dedup lookup must
  // match on both columns - an unscoped lookup here would let one frame's
  // guessed/reused client_upload_id resolve to another frame's imageId.
  const existingByClientId = db
    .prepare('SELECT id FROM images WHERE uploaded_by_frame_id = ? AND client_upload_id = ?')
    .get(req.frameId!, clientUploadId) as { id: string } | undefined;
  if (existingByClientId) {
    await removeQuietly(req.file.path);
    res.status(200).json({ imageId: existingByClientId.id, deduped: true });
    return;
  }

  const frame = db
    .prepare('SELECT f.user_id FROM frames f WHERE f.id = ?')
    .get(req.frameId!) as { user_id: string } | undefined;

  const release = await uploadSlots.acquire();
  try {
    const inputBuffer = await fs.promises.readFile(req.file.path);
    const processed = await processImage(inputBuffer);
    // Quota is checked (and storage_used_bytes is later booked) against the
    // re-encoded byte count, not req.file.size (the raw upload) - those two
    // can differ noticeably (re-encode/strip can shrink or, for a very
    // compressible source, grow the file), and using two different numbers
    // for the accept-decision vs. the bookkeeping would let accounting drift
    // out of sync with what is actually ever stored on disk.
    if (frame) {
      checkUploadQuota(pairingId, frame.user_id, processed.originalBuffer.length);
    }

    // Hash the exact bytes that storeBlobFiles writes, straight from memory,
    // so the content hash needs no second read of the file.
    const hash = sha256Hex(processed.originalBuffer);
    // Blob files are written before the transaction below, as before. A
    // rolled-back transaction can leave them orphaned on disk, which is the
    // bounded, accepted cost documented on commitBlob (contentAddressedStore.ts).
    await storeBlobFiles(hash, processed.originalBuffer, processed.thumbnailBuffer);
    await removeQuietly(req.file.path);

    const imageId = uuidv4();
    // The blobs refcount row and the images INSERT run in the same transaction
    // as required by contentAddressedStore.ts's commitBlob doc comment: a crash
    // or error between the two previously left an incremented refcount with no
    // images row ever pointing at it (a permanent leak, since GC only reaps
    // refcount<=0 blobs). Wrapping both in one transaction means a failed
    // INSERT rolls the refcount back too.
    runInTransaction(db, () => {
      commitBlobRow(hash, processed.originalBuffer.length);

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

    getIo()?.to(`pairing:${pairingId}`).except(`frame:${req.frameId!}`).emit('album:updated', {
      imageId,
      pairingId,
      uploadedByFrameId: req.frameId,
      width: processed.width,
      height: processed.height,
    });

    res.status(201).json({ imageId, contentHash: hash, width: processed.width, height: processed.height });
  } catch (err) {
    await removeQuietly(req.file.path);
    if (err instanceof QuotaError) {
      res.status(413).json({ error: err.message });
      return;
    }
    // Express 4 does not catch rejections from async handlers itself - pass
    // to next() explicitly so the central error handler responds instead of
    // the process crashing on an unhandled rejection (e.g. a corrupt image
    // that fails sharp processing).
    next(err);
  } finally {
    release();
  }
});

/**
 * Lists the images of a pairing, newest first. Without `limit`/`cursor` the
 * response is the full list (bounded by MAX_IMAGES_PER_PAIRING, the same cap
 * the upload quota enforces), so existing clients keep working. Clients that
 * want pages pass `limit` and follow `nextCursor` until it is null.
 */
imagesRouter.get('/pairing/:pairingId', requirePairingMembership, (req, res) => {
  const page = resolvePage(req.query, env.MAX_IMAGES_PER_PAIRING, env.MAX_IMAGES_PER_PAIRING);
  if (!page) {
    res.status(400).json({ error: 'invalid pagination parameters' });
    return;
  }

  const db = getDb();
  const keyset = keysetClause('i.uploaded_at', 'i.id', page.cursor);
  const rows = db
    .prepare(
      `SELECT i.id, i.uploaded_by_frame_id, i.uploaded_at, i.width, i.height, i.content_hash
       FROM images i
       WHERE i.pairing_id = ?
         AND NOT EXISTS (SELECT 1 FROM image_hidden h WHERE h.image_id = i.id AND h.frame_id = ?)
         ${keyset.sql}
       ORDER BY i.uploaded_at DESC, i.id DESC
       LIMIT ?`,
    )
    .all(req.params.pairingId, req.frameId!, ...keyset.params, page.limit + 1) as {
    id: string;
    uploaded_at: string;
  }[];

  const { items, nextCursor } = buildPage(rows, page.limit, (r) => r.uploaded_at);
  res.json({ images: items, nextCursor });
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

  runInTransaction(db, () => {
    db.prepare('DELETE FROM images WHERE id = ?').run(image.id);
    releaseImageAccounting([{ content_hash: image.content_hash, uploaded_by_frame_id: image.uploaded_by_frame_id }]);
  });

  getIo()?.to(`pairing:${image.pairing_id}`).emit('album:imageDeleted', {
    imageId: image.id,
    pairingId: image.pairing_id,
  });

  res.json({ ok: true });
});

/**
 * Serves the re-encoded image bytes directly (never via express.static, so
 * we control headers precisely and never serve raw filesystem paths).
 */
imagesRouter.get('/:imageId/file', async (req, res) => {
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

  // Blobs are content-addressed, so the ETag is a pure function of the DB row
  // and can be checked before touching the filesystem at all.
  const etag = `"${image.content_hash}${wantsThumb ? '-thumb' : ''}"`;
  res.set({
    'Content-Type': 'image/jpeg',
    // Private: the bytes are only for an authenticated pairing member, so
    // shared caches (proxies) must not store them.
    'Cache-Control': 'private, max-age=31536000, immutable',
    ETag: etag,
    'X-Content-Type-Options': 'nosniff',
  });

  if (req.headers['if-none-match'] === etag) {
    res.status(304).end();
    return;
  }

  if (!fs.existsSync(filePath)) {
    res.status(404).json({ error: 'blob missing' });
    return;
  }

  try {
    await pipeline(fs.createReadStream(filePath), res);
  } catch (err: any) {
    // A client that hangs up mid-download is normal; anything else is logged.
    if (err?.code !== 'ERR_STREAM_PREMATURE_CLOSE') {
      console.error('[images] failed to stream blob file', err);
    }
    if (!res.headersSent) {
      res.status(500).json({ error: 'internal server error' });
    }
  }
});
