import type { NextFunction, Request, Response } from 'express';
import { getDb } from '../db';
import { env } from '../config/env';

export class QuotaError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/**
 * Checks the two quota dimensions before accepting an upload:
 *  - per-user storage_used_bytes vs MAX_STORAGE_BYTES_PER_USER
 *  - per-pairing image count vs MAX_IMAGES_PER_PAIRING
 * Intended to run AFTER multer has buffered the file to disk but BEFORE it
 * is committed into the content-addressed store, so req.file.size is known.
 */
export function checkUploadQuota(pairingId: string, uploaderUserId: string, incomingBytes: number): void {
  const db = getDb();

  const user = db
    .prepare('SELECT storage_used_bytes FROM users WHERE id = ?')
    .get(uploaderUserId) as { storage_used_bytes: number } | undefined;

  if (user && user.storage_used_bytes + incomingBytes > env.MAX_STORAGE_BYTES_PER_USER) {
    throw new QuotaError('storage quota exceeded for this account');
  }

  const imageCount = db
    .prepare('SELECT COUNT(*) as count FROM images WHERE pairing_id = ?')
    .get(pairingId) as { count: number };

  if (imageCount.count >= env.MAX_IMAGES_PER_PAIRING) {
    throw new QuotaError('image limit reached for this pairing');
  }
}

/**
 * Express middleware: rejects requests that DECLARE an oversized body via
 * Content-Length, purely as an early-exit optimization (avoids letting
 * multer buffer a huge file to disk just to reject it afterwards). This is
 * NOT the reliable guard against oversized uploads - Content-Length is
 * client-supplied and can be omitted/spoofed (e.g. chunked transfer-encoding
 * has none at all). The actual, trustworthy limit is multer's
 * `limits.fileSize` (see routes/images.ts), which is enforced by counting
 * bytes as they are streamed in, regardless of what the client claims here.
 */
export function enforceMaxUploadSize(req: Request, res: Response, next: NextFunction): void {
  const contentLength = Number(req.headers['content-length'] ?? 0);
  if (contentLength > env.MAX_UPLOAD_BYTES) {
    res.status(413).json({ error: 'payload too large', maxBytes: env.MAX_UPLOAD_BYTES });
    return;
  }
  next();
}
