import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * Must be called before any `src/*` module is imported (env.ts parses
 * process.env at import time and exits the process on invalid config).
 */
export function setupTestEnv(suiteName: string): string {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), `photoframe-test-${suiteName}-`));

  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = 'test-secret-value-thats-long-enough-1234567890';
  process.env.ADMIN_USERNAME = 'admin';
  process.env.ADMIN_PASSWORD = 'test-admin-password';
  process.env.PUBLIC_URL = 'http://localhost:8080';
  process.env.DATA_DIR = dataDir;
  process.env.REGISTRATION_ENABLED = 'true';
  process.env.MAX_UPLOAD_BYTES = String(10 * 1024 * 1024);
  process.env.MAX_IMAGES_PER_PAIRING = '5000';
  process.env.MAX_STORAGE_BYTES_PER_USER = String(5 * 1024 * 1024 * 1024);
  process.env.BACKUP_RETENTION_DAYS = '14';

  return dataDir;
}
