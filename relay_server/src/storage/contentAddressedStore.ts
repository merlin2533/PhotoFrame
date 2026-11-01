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
  return sha256Hex(buf);
}

export function sha256Hex(buf: Buffer): string {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.promises.access(filePath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Writes the re-encoded original and thumbnail for a blob to the store, using
 * async fs and the bytes already in memory (no re-read to hash them). The
 * original is written to a temp file and renamed into place, so readers never
 * see a partial file. An existing original is left untouched (dedup).
 *
 * This runs OUTSIDE the SQL transaction on purpose; the blob row is recorded
 * afterwards by commitBlobRow() inside the transaction. See commitBlob's doc
 * comment for the orphaned-file trade-off, which applies here too.
 */
export async function storeBlobFiles(
  hash: string,
  originalBuffer: Buffer,
  thumbnailBuffer: Buffer,
): Promise<void> {
  const dest = originalPath(hash);
  if (!(await fileExists(dest))) {
    const tmp = path.join(UPLOAD_TMP_DIR, `${crypto.randomUUID()}.orig.tmp`);
    await fs.promises.writeFile(tmp, originalBuffer);
    await fs.promises.rename(tmp, dest);
  }
  await fs.promises.writeFile(thumbPath(hash), thumbnailBuffer);
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
 * crash between the two never leaves an orphaned refcount (see
 * routes/images.ts, which calls this from inside runInTransaction together
 * with the images INSERT). Note this only protects the `blobs` row/refcount
 * (a ROLLBACK correctly undoes that): the physical rename onto disk that
 * happens just above is NOT covered by the SQL transaction, so a crash
 * between the rename and a rolled-back COMMIT can in the worst case leave an
 * orphaned file on disk with no blobs row pointing at it. That is a rare,
 * bounded (one stray file, not a counter that drifts forever) cost accepted
 * in exchange for never leaving `blobs.refcount` out of sync with `images`,
 * which was the actual leak this fixes - see docs/DECISIONS.md.
 */
export function commitBlob(tmpFilePath: string, bytes: number): string {
  const hash = hashFile(tmpFilePath);
  const dest = originalPath(hash);

  if (!fs.existsSync(dest)) {
    fs.renameSync(tmpFilePath, dest);
  } else {
    fs.unlinkSync(tmpFilePath);
  }

  return commitBlobRow(hash, bytes);
}

/**
 * Records one more reference to a blob in the `blobs` table: increments the
 * refcount if the row exists, otherwise inserts it with refcount 1. Must run
 * inside the caller's transaction, next to the `images` INSERT.
 */
export function commitBlobRow(hash: string, bytes: number): string {
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
