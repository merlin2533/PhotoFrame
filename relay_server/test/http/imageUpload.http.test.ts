import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import sharp from 'sharp';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('image-upload-http');

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;
let originalPath: typeof import('../../src/storage/contentAddressedStore').originalPath;
let ensureStorageDirs: typeof import('../../src/storage/contentAddressedStore').ensureStorageDirs;

let app: import('express').Express;
let tinyJpeg: Buffer;

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ issueDeviceToken } = await import('../../src/auth/deviceTokens'));
  ({ originalPath, ensureStorageDirs } = await import('../../src/storage/contentAddressedStore'));
  ensureStorageDirs();
  app = createApp();
  tinyJpeg = await sharp({
    create: { width: 6, height: 4, channels: 3, background: { r: 200, g: 30, b: 90 } },
  })
    .jpeg()
    .toBuffer();
});

function makeFrame(): { frameId: string; token: string } {
  const db = getDb();
  const userId = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    userId,
    `user-${userId}`,
    'hash',
  );
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Frame');
  return { frameId, token: issueDeviceToken(frameId).rawToken };
}

function makePairing(ownerFrameId: string): string {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Upload pairing');
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    ownerFrameId,
    'owner',
  );
  return pairingId;
}

function post(token: string, pairingId: string, clientUploadId: string, body: Buffer, contentType: string) {
  return request(app)
    .post('/api/v1/images')
    .set('Authorization', `Bearer ${token}`)
    .field('pairingId', pairingId)
    .field('clientUploadId', clientUploadId)
    .attach('file', body, { filename: 'upload.bin', contentType });
}

test('a valid upload returns 201, and the content hash is the SHA-256 of the stored original', async () => {
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);

  const res = await post(frame.token, pairingId, uuidv4(), tinyJpeg, 'image/jpeg');
  assert.equal(res.status, 201);
  assert.equal(res.body.width, 6);
  assert.equal(res.body.height, 4);

  const stored = fs.readFileSync(originalPath(res.body.contentHash));
  const sha256 = crypto.createHash('sha256').update(stored).digest('hex');
  assert.equal(sha256, res.body.contentHash, 'the in-memory hash must match the bytes written to disk');
});

test('an unsupported MIME type is rejected with 415 and no image row is created', async () => {
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);
  const clientUploadId = uuidv4();

  const res = await post(frame.token, pairingId, clientUploadId, Buffer.from('plain text'), 'text/plain');
  assert.equal(res.status, 415);
  assert.equal(res.body.error, 'unsupported file type');

  const row = getDb()
    .prepare('SELECT id FROM images WHERE uploaded_by_frame_id = ? AND client_upload_id = ?')
    .get(frame.frameId, clientUploadId);
  assert.equal(row, undefined);
});

test('a declared Content-Length above MAX_UPLOAD_BYTES is rejected with 413 before any upload work', async () => {
  const frame = makeFrame();
  const tooLarge = 10 * 1024 * 1024 + 1;

  // Only the declared size is checked by enforceMaxUploadSize, so a small body
  // with an oversized Content-Length header is enough to exercise the guard.
  const res = await request(app)
    .post('/api/v1/images')
    .set('Authorization', `Bearer ${frame.token}`)
    .set('Content-Length', String(tooLarge))
    .set('Content-Type', 'multipart/form-data; boundary=----x')
    .send(Buffer.from('----x--'));
  assert.equal(res.status, 413);
});

test('a file that claims to be a JPEG but is not decodable is refused and creates no image row', async () => {
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);
  const clientUploadId = uuidv4();

  const res = await post(frame.token, pairingId, clientUploadId, Buffer.from('definitely not a jpeg'), 'image/jpeg');
  // Not 201. The 422 mapping for undecodable images is still open (plan item 9,
  // not implemented), so this currently surfaces as the generic 500 handler.
  assert.ok(res.status >= 400, `expected an error status, got ${res.status}`);
  assert.notEqual(res.status, 201);

  const row = getDb()
    .prepare('SELECT id FROM images WHERE uploaded_by_frame_id = ? AND client_upload_id = ?')
    .get(frame.frameId, clientUploadId);
  assert.equal(row, undefined);
});

test('a repeated client_upload_id from the same frame is deduplicated (200, same imageId)', async () => {
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);
  const clientUploadId = uuidv4();

  const first = await post(frame.token, pairingId, clientUploadId, tinyJpeg, 'image/jpeg');
  assert.equal(first.status, 201);

  const again = await post(frame.token, pairingId, clientUploadId, tinyJpeg, 'image/jpeg');
  assert.equal(again.status, 200);
  assert.equal(again.body.deduped, true);
  assert.equal(again.body.imageId, first.body.imageId);
});

test('a non-member cannot upload into a pairing (403)', async () => {
  const owner = makeFrame();
  const pairingId = makePairing(owner.frameId);
  const outsider = makeFrame();

  const res = await post(outsider.token, pairingId, uuidv4(), tinyJpeg, 'image/jpeg');
  assert.equal(res.status, 403);
});
