import { getDb } from '../db';
import { releaseBlobRef } from './contentAddressedStore';

export interface DeletedImageRef {
  content_hash: string;
  uploaded_by_frame_id: string;
}

/**
 * Releases the accounting side effects of deleting one or more `images`
 * rows: decrements each blob's refcount (actual file unlink still happens
 * exclusively in the separate blobGc.ts run, never here) and decrements the
 * uploading user's `storage_used_bytes`.
 *
 * Callers are responsible for actually deleting/cascading the `images` rows
 * themselves (directly, or via `ON DELETE CASCADE` on `pairings`/`users`) -
 * this only undoes the bookkeeping that happened at upload time. Call this
 * BEFORE the row(s) disappear (so `uploaded_by_frame_id` -> `frames.user_id`
 * is still resolvable) and within the same transaction as the delete, so a
 * crash mid-way never leaves the counters out of sync with the rows.
 *
 * storage_used_bytes semantics (see docs/DECISIONS.md "Blob refcount vs.
 * per-user storage accounting"): every accepted image row charges its
 * uploader's storage_used_bytes with the blob's byte size, even when the
 * underlying blob content is deduped with another user's upload (blobs are
 * shared, but quota is charged per accepting row, symmetrically with this
 * release). This intentionally keeps the counter drift-free in both
 * directions at the cost of SUM(storage_used_bytes) across users being able
 * to exceed real bytes-on-disk when content is shared - the actual disk
 * usage is tracked separately (and correctly) via blobs.bytes/refcount.
 */
export function releaseImageAccounting(images: DeletedImageRef[]): void {
  const db = getDb();

  for (const image of images) {
    releaseBlobRef(image.content_hash);

    const blob = db.prepare('SELECT bytes FROM blobs WHERE hash = ?').get(image.content_hash) as
      | { bytes: number }
      | undefined;
    const frame = db
      .prepare('SELECT user_id FROM frames WHERE id = ?')
      .get(image.uploaded_by_frame_id) as { user_id: string } | undefined;

    if (blob && frame) {
      db.prepare('UPDATE users SET storage_used_bytes = MAX(storage_used_bytes - ?, 0) WHERE id = ?').run(
        blob.bytes,
        frame.user_id,
      );
    }
  }
}
