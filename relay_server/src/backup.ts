import fs from 'node:fs';
import path from 'node:path';
import { backup } from 'node:sqlite';
import { BACKUPS_DIR, DB_PATH, env } from './config/env';
import { getDb } from './db';

/**
 * Backs up the SQLite database using node:sqlite's online backup API
 * (sqlite.backup()), which is safe to run against a live WAL-mode database
 * without blocking writers for the whole duration.
 *
 * NOTE: this only covers the database file. The /data/blobs directory
 * (the actual image bytes) must be backed up separately - e.g. an
 * incremental `rsync -a --delete /data/blobs/ backup-host:/backups/blobs/`
 * or a nightly `tar -cf blobs-$(date +%F).tar -C /data blobs` job run
 * alongside this script from the host/cron, since blob content is
 * immutable and content-addressed (safe to rsync incrementally).
 */
export async function backupDatabase(): Promise<string> {
  fs.mkdirSync(BACKUPS_DIR, { recursive: true });

  const db = getDb();
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const destPath = path.join(BACKUPS_DIR, `relay-${timestamp}.db`);

  await backup(db, destPath);
  pruneOldBackups();

  return destPath;
}

function pruneOldBackups(): void {
  if (!fs.existsSync(BACKUPS_DIR)) return;

  const cutoff = Date.now() - env.BACKUP_RETENTION_DAYS * 24 * 60 * 60 * 1000;
  for (const file of fs.readdirSync(BACKUPS_DIR)) {
    const filePath = path.join(BACKUPS_DIR, file);
    const stat = fs.statSync(filePath);
    if (stat.mtimeMs < cutoff) {
      fs.unlinkSync(filePath);
    }
  }
}

// Allow running standalone: `node dist/backup.js`
if (require.main === module) {
  backupDatabase()
    .then((dest) => {
      console.log(`Backup written to ${dest} (source: ${DB_PATH})`);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Backup failed:', err);
      process.exit(1);
    });
}
