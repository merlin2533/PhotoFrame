import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { BLOBS_DIR, UPLOAD_TMP_DIR } from '../config/env';
import { getDb, runInTransaction } from '../db';

export function ensureStorageDirs(): void {
  fs.mkdirSync(BLOBS_DIR, { recursive: true });
  fs.mkdirSync(UPLOAD_TMP_DIR, { recursive: true });
}

export function hashFile(filePath: string): string {
  const buf = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(buf).digest('hex');
}

export function originalPath(hash: string): string {
  return path.join(BLOBS_DIR, `${hash}.orig`);
}

export function thumbPath(hash: string): string {
  return path.join(BLOBS_DIR, `${hash}.thumb`);
}

/**
 * Commits a temp upload file into the content-addressed store. If a blob
 * with this hash already exists (dedup), the temp file is discarded and the
 * refcount is incremented; otherwise the temp file is atomically renamed
 * into place (rename is atomic on the same filesystem/volume).
 *
 * Returns the content hash. Caller is responsible for inserting the
 * corresponding `images` row in the SAME transaction that calls this, so a
 * crash between the two never leaves an orphaned refcount.
 */
export function commitBlob(tmpFilePath: string, bytes: number): string {
  const hash = hashFile(tmpFilePath);
  const dest = originalPath(hash);

  if (!fs.existsSync(dest)) {
    fs.renameSync(tmpFilePath, dest);
  } else {
    fs.unlinkSync(tmpFilePath);
  }

  const db = getDb();
  const existing = db.prepare('SELECT hash FROM blobs WHERE hash = ?').get(hash);
  if (existing) {
    db.prepare('UPDATE blobs SET refcount = refcount + 1 WHERE hash = ?').run(hash);
  } else {
    db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, 1)').run(hash, bytes);
  }

  return hash;
}

/**
 * Decrements the refcount for a blob (e.g. when an `images` row referencing
 * it is deleted). Does NOT unlink files - that is handled exclusively by
 * runGarbageCollection() as a separate, explicit job, to avoid deleting a
 * file that a concurrent upload is about to dedup onto (a delete + a
 * simultaneous dedup-insert on the same hash is a classic TOCTOU race).
 */
export function releaseBlobRef(hash: string): void {
  const db = getDb();
  db.prepare('UPDATE blobs SET refcount = MAX(refcount - 1, 0) WHERE hash = ?').run(hash);
}

export interface GcResult {
  scanned: number;
  deleted: number;
  freedBytes: number;
}

/**
 * Garbage-collects blobs whose refcount has reached zero: removes the DB
 * row and unlinks both the .orig and .thumb files on disk. Meant to be run
 * periodically (e.g. cron/backup.ts) or manually via an admin action -
 * never inline with a delete request.
 */
export function runGarbageCollection(): GcResult {
  const db = getDb();
  const orphans = db.prepare('SELECT hash, bytes FROM blobs WHERE refcount <= 0').all() as {
    hash: string;
    bytes: number;
  }[];

  let deleted = 0;
  let freedBytes = 0;

  for (const blob of orphans) {
    const wasDeleted = runInTransaction(db, () => {
      const stillZero = db
        .prepare('SELECT refcount FROM blobs WHERE hash = ?')
        .get(blob.hash) as { refcount: number } | undefined;
      if (!stillZero || stillZero.refcount > 0) return false;

      db.prepare('DELETE FROM blobs WHERE hash = ?').run(blob.hash);
      return true;
    });

    if (!wasDeleted) continue;

    for (const filePath of [originalPath(blob.hash), thumbPath(blob.hash)]) {
      try {
        fs.unlinkSync(filePath);
      } catch (err: any) {
        if (err.code !== 'ENOENT') throw err;
      }
    }

    deleted += 1;
    freedBytes += blob.bytes;
  }

  return { scanned: orphans.length, deleted, freedBytes };
}
