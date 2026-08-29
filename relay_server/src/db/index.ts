import fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { DB_PATH, env } from '../config/env';
import { runMigrations } from './migrations/index';

let dbInstance: DatabaseSync | null = null;

export function getDb(): DatabaseSync {
  if (dbInstance) return dbInstance;

  fs.mkdirSync(env.DATA_DIR, { recursive: true });

  const db = new DatabaseSync(DB_PATH);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA synchronous = NORMAL');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('PRAGMA busy_timeout = 5000');

  runMigrations(db);

  dbInstance = db;
  return db;
}

export function closeDb(): void {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}

/**
 * node:sqlite's DatabaseSync has no built-in `.transaction()` helper (unlike
 * better-sqlite3), so we wrap BEGIN/COMMIT/ROLLBACK ourselves. All call
 * sites that need atomicity across multiple statements use this instead.
 */
export function runInTransaction<T>(db: DatabaseSync, fn: () => T): T {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    try {
      db.exec('ROLLBACK');
    } catch {
      // ignore rollback failures (e.g. no transaction in progress)
    }
    throw err;
  }
}
