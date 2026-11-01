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
  if (images.length === 0) return;

  const db = getDb();

  // Resolve blob sizes and frame owners up front with one IN (...) query per
  // table instead of two lookups per image (a pairing or account delete can
  // release thousands of rows at once). Chunked to stay well below SQLite's
  // bound-parameter limit.
  const blobBytes = new Map<string, number>();
  for (const chunk of chunked([...new Set(images.map((i) => i.content_hash))])) {
    const rows = db
      .prepare(`SELECT hash, bytes FROM blobs WHERE hash IN (${placeholders(chunk.length)})`)
      .all(...chunk) as { hash: string; bytes: number }[];
    for (const row of rows) blobBytes.set(row.hash, row.bytes);
  }

  const frameOwner = new Map<string, string>();
  for (const chunk of chunked([...new Set(images.map((i) => i.uploaded_by_frame_id))])) {
    const rows = db
      .prepare(`SELECT id, user_id FROM frames WHERE id IN (${placeholders(chunk.length)})`)
      .all(...chunk) as { id: string; user_id: string }[];
    for (const row of rows) frameOwner.set(row.id, row.user_id);
  }

  for (const image of images) {
    releaseBlobRef(image.content_hash);

    const bytes = blobBytes.get(image.content_hash);
    const userId = frameOwner.get(image.uploaded_by_frame_id);

    if (bytes !== undefined && userId !== undefined) {
      db.prepare('UPDATE users SET storage_used_bytes = MAX(storage_used_bytes - ?, 0) WHERE id = ?').run(
        bytes,
        userId,
      );
    }
  }
}

const LOOKUP_CHUNK_SIZE = 500;

function chunked(values: string[]): string[][] {
  const out: string[][] = [];
  for (let i = 0; i < values.length; i += LOOKUP_CHUNK_SIZE) {
    out.push(values.slice(i, i + LOOKUP_CHUNK_SIZE));
  }
  return out;
}

function placeholders(count: number): string {
  return Array.from({ length: count }, () => '?').join(',');
}
