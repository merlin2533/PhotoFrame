import { getDb } from '../db';

export interface BlobRefcountMismatch {
  hash: string;
  storedRefcount: number;
  actualRefcount: number;
}

export interface BlobConsistencyReport {
  checkedAt: string;
  totalBlobs: number;
  mismatches: BlobRefcountMismatch[];
}

/**
 * Consistency check for `blobs.refcount`, which is an explicit counter
 * maintained alongside `images` inserts/deletes (see contentAddressedStore.ts)
 * rather than derived with COUNT(*) on every read, for cheap reads and to
 * avoid a race on delete. That tradeoff means a bug anywhere along the
 * insert/delete/cascade paths can in principle let the counter drift from
 * reality without ever surfacing on its own.
 *
 * This job is the independent check on that invariant: for every blob it
 * recomputes the actual reference count directly from `images.content_hash`
 * and compares it to the stored `blobs.refcount`. It is read-only and never
 * auto-corrects a mismatch - fixing a drifted counter is a judgment call
 * (was a row deleted without releasing its ref? was a ref released twice?)
 * that deserves a human looking at the audit trail, not a silent rewrite by
 * a cron job. Meant to be run periodically (e.g. alongside backup.ts) or
 * on demand via the admin endpoint.
 */
export function runBlobConsistencyCheck(): BlobConsistencyReport {
  const db = getDb();

  // One LEFT JOIN + GROUP BY computes every blob's actual reference count in
  // a single pass, instead of one COUNT(*) query per blob.
  const blobs = db
    .prepare(
      `SELECT b.hash AS hash, b.refcount AS refcount, COUNT(i.id) AS actualRefcount
       FROM blobs b
       LEFT JOIN images i ON i.content_hash = b.hash
       GROUP BY b.hash, b.refcount`,
    )
    .all() as { hash: string; refcount: number; actualRefcount: number }[];

  const mismatches: BlobRefcountMismatch[] = [];

  for (const blob of blobs) {
    const actualRefcount = blob.actualRefcount;

    if (actualRefcount !== blob.refcount) {
      const mismatch: BlobRefcountMismatch = {
        hash: blob.hash,
        storedRefcount: blob.refcount,
        actualRefcount,
      };
      mismatches.push(mismatch);
      console.warn(
        `[blobConsistencyCheck] refcount mismatch for blob ${blob.hash}: stored=${blob.refcount} actual=${actualRefcount}`,
      );
    }
  }

  return {
    checkedAt: new Date().toISOString(),
    totalBlobs: blobs.length,
    mismatches,
  };
}
