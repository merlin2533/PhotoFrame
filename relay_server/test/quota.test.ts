import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('quota');
process.env.MAX_IMAGES_PER_PAIRING = '5';

let getDb: typeof import('../src/db').getDb;
let checkUploadQuota: typeof import('../src/middleware/quota').checkUploadQuota;
let QuotaError: typeof import('../src/middleware/quota').QuotaError;
let env: typeof import('../src/config/env').env;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ checkUploadQuota, QuotaError } = await import('../src/middleware/quota'));
  ({ env } = await import('../src/config/env'));
});

function makeUser(storageUsedBytes = 0): string {
  const db = getDb();
  const id = uuidv4();
  db.prepare(
    'INSERT INTO users (id, username, password_hash, storage_used_bytes) VALUES (?, ?, ?, ?)',
  ).run(id, `user-${id}`, 'hash', storageUsedBytes);
  return id;
}

function makePairing(): string {
  const db = getDb();
  const id = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(id, 'Test pairing');
  return id;
}

test('checkUploadQuota allows an upload comfortably within both limits', () => {
  const userId = makeUser(0);
  const pairingId = makePairing();
  assert.doesNotThrow(() => checkUploadQuota(pairingId, userId, 1024));
});

test('checkUploadQuota rejects an upload that would exceed per-user storage quota', () => {
  const userId = makeUser(env.MAX_STORAGE_BYTES_PER_USER - 100);
  const pairingId = makePairing();
  assert.throws(() => checkUploadQuota(pairingId, userId, 1000), QuotaError);
});

test('checkUploadQuota rejects an upload once the pairing has reached its image-count limit', () => {
  const db = getDb();
  const userId = makeUser(0);
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Frame');
  const pairingId = makePairing();

  // Simulate the pairing already being at the limit by inserting dummy blob + images rows.
  const blobHash = 'a'.repeat(64);
  db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, ?)').run(blobHash, 10, env.MAX_IMAGES_PER_PAIRING);
  const insertImage = db.prepare(
    'INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, client_upload_id) VALUES (?, ?, ?, ?, ?)',
  );
  for (let i = 0; i < env.MAX_IMAGES_PER_PAIRING; i++) {
    insertImage.run(uuidv4(), pairingId, frameId, blobHash, `client-${i}`);
  }

  assert.throws(() => checkUploadQuota(pairingId, userId, 100), QuotaError);
});
