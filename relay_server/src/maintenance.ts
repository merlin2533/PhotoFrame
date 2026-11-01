import fs from 'node:fs';
import path from 'node:path';
import { env, UPLOAD_TMP_DIR } from './config/env';
import { getDb } from './db';
import { runBlobConsistencyCheck } from './storage/blobConsistencyCheck';
import { runGarbageCollection } from './storage/contentAddressedStore';

// A live upload finishes within seconds, so a temp file this old is a leftover
// from an upload that crashed or was killed mid-way.
const TMP_FILE_MAX_AGE_MS = 60 * 60 * 1000;

// Revoked refresh tokens are only needed to answer "already used" for a short
// while; after that, a replay gets the same 401 as an unknown token.
const REVOKED_REFRESH_TOKEN_RETENTION_MS = 24 * 60 * 60 * 1000;

export interface MaintenanceResult {
  blobsDeleted: number;
  blobMismatches: number;
  tmpFilesRemoved: number;
  pairingCodesDeleted: number;
  refreshTokensDeleted: number;
}

/**
 * One maintenance pass. Each step is isolated, so a failure in one step is
 * logged and the remaining steps still run.
 *
 * - blob GC: unlinks files of blobs whose refcount reached zero.
 * - blob consistency check: read-only, reports refcount drift in the log.
 * - stale upload temp files in DATA_DIR/tmp.
 * - expired pairing codes (redeeming one now returns 404 instead of 410).
 * - revoked refresh tokens past the retention window.
 */
export async function runMaintenance(now = Date.now()): Promise<MaintenanceResult> {
  const result: MaintenanceResult = {
    blobsDeleted: 0,
    blobMismatches: 0,
    tmpFilesRemoved: 0,
    pairingCodesDeleted: 0,
    refreshTokensDeleted: 0,
  };

  try {
    result.blobsDeleted = runGarbageCollection().deleted;
  } catch (err) {
    console.error('[maintenance] blob GC failed', err);
  }

  try {
    result.blobMismatches = runBlobConsistencyCheck().mismatches.length;
  } catch (err) {
    console.error('[maintenance] blob consistency check failed', err);
  }

  try {
    result.tmpFilesRemoved = await removeStaleTmpFiles(now);
  } catch (err) {
    console.error('[maintenance] temp file cleanup failed', err);
  }

  const db = getDb();
  try {
    result.pairingCodesDeleted = db
      .prepare('DELETE FROM pairing_codes WHERE expires_at < ?')
      .run(new Date(now).toISOString()).changes as number;
  } catch (err) {
    console.error('[maintenance] pairing code cleanup failed', err);
  }

  try {
    const cutoff = new Date(now - REVOKED_REFRESH_TOKEN_RETENTION_MS).toISOString();
    result.refreshTokensDeleted = db
      .prepare('DELETE FROM refresh_tokens WHERE revoked_at IS NOT NULL AND revoked_at < ?')
      .run(cutoff).changes as number;
  } catch (err) {
    console.error('[maintenance] refresh token cleanup failed', err);
  }

  return result;
}

async function removeStaleTmpFiles(now: number): Promise<number> {
  let entries: string[];
  try {
    entries = await fs.promises.readdir(UPLOAD_TMP_DIR);
  } catch (err: any) {
    if (err.code === 'ENOENT') return 0;
    throw err;
  }

  let removed = 0;
  for (const entry of entries) {
    const filePath = path.join(UPLOAD_TMP_DIR, entry);
    try {
      const stat = await fs.promises.stat(filePath);
      if (!stat.isFile() || now - stat.mtimeMs < TMP_FILE_MAX_AGE_MS) continue;
      await fs.promises.unlink(filePath);
      removed += 1;
    } catch (err: any) {
      // Another process or a concurrent upload may have removed it already.
      if (err.code !== 'ENOENT') {
        console.warn(`[maintenance] could not clean temp file ${filePath}: ${err.message}`);
      }
    }
  }
  return removed;
}

/**
 * Starts the periodic maintenance job at MAINTENANCE_INTERVAL_MINUTES (0
 * disables it). Returns the timer so the caller can clear it on shutdown.
 * A run is skipped if the previous one is still in progress.
 */
export function startMaintenanceJobs(): NodeJS.Timeout | null {
  if (env.MAINTENANCE_INTERVAL_MINUTES === 0) return null;

  let running = false;
  const timer = setInterval(() => {
    if (running) return;
    running = true;
    runMaintenance()
      .then((result) => console.log('[maintenance] pass complete', JSON.stringify(result)))
      .catch((err) => console.error('[maintenance] pass failed', err))
      .finally(() => {
        running = false;
      });
  }, env.MAINTENANCE_INTERVAL_MINUTES * 60 * 1000);

  // Never keep the process alive on its own; the HTTP server does that.
  timer.unref();
  return timer;
}
