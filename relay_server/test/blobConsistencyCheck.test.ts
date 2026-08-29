import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('blob-consistency-check');

let getDb: typeof import('../src/db').getDb;
let runBlobConsistencyCheck: typeof import('../src/storage/blobConsistencyCheck').runBlobConsistencyCheck;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ runBlobConsistencyCheck } = await import('../src/storage/blobConsistencyCheck'));
});

function makeUser(): string {
  const db = getDb();
  const id = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    id,
    `user-${id}`,
    'hash',
  );
  return id;
}

function makeFrame(userId: string): string {
  const db = getDb();
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(
    frameId,
    userId,
    'Test Frame',
  );
  return frameId;
}

function makePairing(): string {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Test Pairing');
  return pairingId;
}

function makeBlob(hash: string, refcount: number): void {
  const db = getDb();
  db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, ?)').run(hash, 100, refcount);
}

function makeImage(pairingId: string, frameId: string, contentHash: string): void {
  const db = getDb();
  db.prepare(
    'INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash) VALUES (?, ?, ?, ?)',
  ).run(uuidv4(), pairingId, frameId, contentHash);
}

test('runBlobConsistencyCheck reports zero mismatches when refcount matches actual image references', () => {
  const userId = makeUser();
  const frameId = makeFrame(userId);
  const pairingId = makePairing();

  const hash = `consistent-${uuidv4()}`;
  makeBlob(hash, 2);
  makeImage(pairingId, frameId, hash);
  makeImage(pairingId, frameId, hash);

  const report = runBlobConsistencyCheck();

  assert.ok(report.totalBlobs >= 1);
  assert.ok(typeof report.checkedAt === 'string');
  const mismatchForHash = report.mismatches.find((m) => m.hash === hash);
  assert.equal(mismatchForHash, undefined);
});

test('runBlobConsistencyCheck detects a stored refcount higher than the actual reference count', () => {
  const userId = makeUser();
  const frameId = makeFrame(userId);
  const pairingId = makePairing();

  const hash = `over-counted-${uuidv4()}`;
  makeBlob(hash, 2);
  makeImage(pairingId, frameId, hash); // only 1 image references it, refcount says 2

  const report = runBlobConsistencyCheck();

  const mismatch = report.mismatches.find((m) => m.hash === hash);
  assert.ok(mismatch, 'expected a mismatch to be reported for the over-counted blob');
  assert.equal(mismatch!.storedRefcount, 2);
  assert.equal(mismatch!.actualRefcount, 1);
});

test('runBlobConsistencyCheck detects a stored refcount of zero when images still reference the blob', () => {
  const userId = makeUser();
  const frameId = makeFrame(userId);
  const pairingId = makePairing();

  const hash = `under-counted-${uuidv4()}`;
  makeBlob(hash, 0);
  makeImage(pairingId, frameId, hash);

  const report = runBlobConsistencyCheck();

  const mismatch = report.mismatches.find((m) => m.hash === hash);
  assert.ok(mismatch, 'expected a mismatch to be reported for the under-counted blob');
  assert.equal(mismatch!.storedRefcount, 0);
  assert.equal(mismatch!.actualRefcount, 1);
});
