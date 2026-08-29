import fs from 'node:fs';
import path from 'node:path';
import type { DatabaseSync } from 'node:sqlite';

interface Migration {
  version: number;
  name: string;
  sql: string;
}

function loadMigrations(): Migration[] {
  const dir = __dirname;
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  return files.map((file) => {
    const match = file.match(/^(\d+)_(.+)\.sql$/);
    if (!match) {
      throw new Error(`Migration file "${file}" does not match pattern <version>_<name>.sql`);
    }
    return {
      version: Number(match[1]),
      name: match[2],
      sql: fs.readFileSync(path.join(dir, file), 'utf8'),
    };
  });
}

/**
 * Applies pending migrations, tracked via SQLite's built-in `user_version`
 * pragma. Migrations are applied in ascending version order inside a
 * transaction each, and are safe to re-run (schema.sql uses
 * CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS throughout).
 */
export function runMigrations(db: DatabaseSync): void {
  const migrations = loadMigrations();
  const currentVersion = (db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version;

  for (const migration of migrations) {
    if (migration.version <= currentVersion) continue;

    db.exec('BEGIN');
    try {
      db.exec(migration.sql);
      db.exec(`PRAGMA user_version = ${migration.version}`);
      db.exec('COMMIT');
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }

    console.log(`[migrations] applied ${migration.version}_${migration.name}`);
  }
}
