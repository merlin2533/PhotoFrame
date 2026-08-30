import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import sharp from 'sharp';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('upload-id-scope');

/**
 * Covers the 002_scope_client_upload_id migration:
 *  - the migration applies cleanly to a brand new database
 *  - the migration applies cleanly to a database already populated under the
 *    v1 schema (global UNIQUE(client_upload_id)), preserving every row
 *  - after migrating, client_upload_id is unique per uploaded_by_frame_id
 *    instead of globally
 *  - the HTTP upload route's dedup check (routes/images.ts) is scoped to the
 *    calling frame, so two frames may reuse the same clientUploadId without
 *    colliding, while the same frame reusing its own id still gets the
 *    idempotent `deduped: true` response instead of a second row.
 */

const MIGRATIONS_DIR = path.join(__dirname, '../src/db/migrations');

function readMigration(version: number): string {
  const file = fs.readdirSync(MIGRATIONS_DIR).find((f) => f.startsWith(`${version.toString().padStart(3, '0')}_`));
  assert.ok(file, `migration ${version} not found`);
  return fs.readFileSync(path.join(MIGRATIONS_DIR, file!), 'utf8');
}

function openTempDb(): { db: DatabaseSync; dir: string } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'photoframe-migration-test-'));
  const db = new DatabaseSync(path.join(dir, 'test.db'));
  db.exec('PRAGMA foreign_keys = ON');
  return { db, dir };
}

let runMigrations: typeof import('../src/db/migrations/index').runMigrations;

before(async () => {
  ({ runMigrations } = await import('../src/db/migrations/index'));
});

function getUserVersion(db: DatabaseSync): number {
  return (db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version;
}

function indexNamesOn(db: DatabaseSync, table: string): string[] {
  return (db.prepare(`PRAGMA index_list(${table})`).all() as { name: string }[]).map((r) => r.name);
}

test('migration 002 applies cleanly to a fresh database and creates the scoped unique index', () => {
  const { db } = openTempDb();

  runMigrations(db);

  assert.equal(getUserVersion(db), 2);

  const indexes = indexNamesOn(db, 'images');
  assert.ok(indexes.includes('idx_images_upload_scope'), 'expected the new composite unique index to exist');
  assert.ok(indexes.includes('idx_images_pairing_id'), 'idx_images_pairing_id must survive the table rebuild');
  assert.ok(indexes.includes('idx_images_content_hash'), 'idx_images_content_hash must survive the table rebuild');

  // Sanity: the composite index is actually unique and covers the right columns.
  const scopeIndex = db
    .prepare(`PRAGMA index_list(images)`)
    .all()
    .find((r: any) => r.name === 'idx_images_upload_scope') as { unique: number };
  assert.equal(scopeIndex.unique, 1);

  const scopeCols = (db.prepare(`PRAGMA index_info(idx_images_upload_scope)`).all() as { name: string }[]).map(
    (r) => r.name,
  );
  assert.deepEqual(scopeCols, ['uploaded_by_frame_id', 'client_upload_id']);
});

test('migration 002 applies cleanly to a database already populated under the v1 schema, preserving rows', () => {
  const { db } = openTempDb();

  // Bring the DB to v1 exactly as the real runner would, then seed rows
  // under the old (global-unique) constraint before migrating further.
  db.exec('BEGIN');
  db.exec(readMigration(1));
  db.exec('PRAGMA user_version = 1');
  db.exec('COMMIT');

  db.exec(`INSERT INTO users (id, username, password_hash) VALUES ('u1', 'alice', 'hash')`);
  db.exec(`INSERT INTO frames (id, user_id, display_name) VALUES ('f1', 'u1', 'Frame One')`);
  db.exec(`INSERT INTO frames (id, user_id, display_name) VALUES ('f2', 'u1', 'Frame Two')`);
  db.exec(`INSERT INTO pairings (id, name) VALUES ('p1', 'Pairing')`);
  db.exec(`INSERT INTO blobs (hash, bytes, refcount) VALUES ('h1', 100, 1)`);
  db.exec(
    `INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, width, height, client_upload_id)
     VALUES ('img1', 'p1', 'f1', 'h1', 10, 10, 'upload-abc')`,
  );

  runMigrations(db);

  assert.equal(getUserVersion(db), 2);

  const row = db.prepare('SELECT * FROM images WHERE id = ?').get('img1') as any;
  assert.ok(row, 'pre-existing row must survive the migration');
  assert.equal(row.uploaded_by_frame_id, 'f1');
  assert.equal(row.client_upload_id, 'upload-abc');
  assert.equal(row.content_hash, 'h1');
  assert.equal(row.width, 10);

  // Post-migration, a different frame may now reuse the same
  // client_upload_id (would have violated the old global UNIQUE).
  assert.doesNotThrow(() => {
    db.exec(
      `INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, width, height, client_upload_id)
       VALUES ('img2', 'p1', 'f2', 'h1', 10, 10, 'upload-abc')`,
    );
  });

  // But the same frame reusing its own client_upload_id still violates the
  // (now composite) unique constraint.
  assert.throws(() => {
    db.exec(
      `INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, width, height, client_upload_id)
       VALUES ('img3', 'p1', 'f1', 'h1', 10, 10, 'upload-abc')`,
    );
  });
});

// --- HTTP-level: the upload route's dedup check is scoped per frame ---

let getDb: typeof import('../src/db').getDb;
let createApp: typeof import('../src/index').createApp;
let issueDeviceToken: typeof import('../src/auth/deviceTokens').issueDeviceToken;
let app: import('express').Express;
let tinyJpeg: Buffer;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ createApp } = await import('../src/index'));
  ({ issueDeviceToken } = await import('../src/auth/deviceTokens'));
  const { ensureStorageDirs } = await import('../src/storage/contentAddressedStore');
  ensureStorageDirs();
  app = createApp();
  tinyJpeg = await sharp({
    create: { width: 4, height: 4, channels: 3, background: { r: 5, g: 6, b: 7 } },
  })
    .jpeg()
    .toBuffer();
});

function makeUser(): string {
  const db = getDb();
  const id = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(id, `user-${id}`, 'hash');
  return id;
}

function makeFrame(userId: string): { frameId: string; token: string } {
  const db = getDb();
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Test Frame');
  const token = issueDeviceToken(frameId).rawToken;
  return { frameId, token };
}

function makePairingWithOwner(ownerFrameId: string): string {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Test pairing');
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    ownerFrameId,
    'owner',
  );
  return pairingId;
}

function addMember(pairingId: string, frameId: string, role: 'owner' | 'member' = 'member') {
  getDb()
    .prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)')
    .run(pairingId, frameId, role);
}

function uploadImage(token: string, pairingId: string, clientUploadId: string) {
  return request(app)
    .post('/api/v1/images')
    .set('Authorization', `Bearer ${token}`)
    .field('pairingId', pairingId)
    .field('clientUploadId', clientUploadId)
    .attach('file', tinyJpeg, { filename: 'test.jpg', contentType: 'image/jpeg' });
}

test('HTTP: two different frames may upload with the same clientUploadId without colliding', async () => {
  const userId = makeUser();
  const frameA = makeFrame(userId);
  const frameB = makeFrame(userId);
  const pairingId = makePairingWithOwner(frameA.frameId);
  addMember(pairingId, frameB.frameId, 'member');

  const sharedClientUploadId = `shared-${uuidv4()}`;

  const resA = await uploadImage(frameA.token, pairingId, sharedClientUploadId);
  assert.equal(resA.status, 201);
  assert.equal(resA.body.deduped, undefined);

  const resB = await uploadImage(frameB.token, pairingId, sharedClientUploadId);
  assert.equal(resB.status, 201, 'a second frame reusing the same clientUploadId must not be blocked or deduped');
  assert.notEqual(
    resB.body.imageId,
    resA.body.imageId,
    'each frame must get its own image row, not the other frame\'s deduped id',
  );
});

test('HTTP: the same frame re-uploading with the same clientUploadId is deduped (idempotent retry)', async () => {
  const userId = makeUser();
  const frame = makeFrame(userId);
  const pairingId = makePairingWithOwner(frame.frameId);

  const clientUploadId = `retry-${uuidv4()}`;

  const first = await uploadImage(frame.token, pairingId, clientUploadId);
  assert.equal(first.status, 201);

  const retry = await uploadImage(frame.token, pairingId, clientUploadId);
  assert.equal(retry.status, 200);
  assert.equal(retry.body.deduped, true);
  assert.equal(retry.body.imageId, first.body.imageId);
});
