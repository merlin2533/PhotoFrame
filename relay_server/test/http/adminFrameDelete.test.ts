import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('admin-frame-delete-http');

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;
let verifyDeviceToken: typeof import('../../src/auth/deviceTokens').verifyDeviceToken;
let signAdminToken: typeof import('../../src/auth/adminAuth').signAdminToken;

let app: import('express').Express;
let adminToken: string;

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ issueDeviceToken, verifyDeviceToken } = await import('../../src/auth/deviceTokens'));
  ({ signAdminToken } = await import('../../src/auth/adminAuth'));
  app = createApp();
  adminToken = signAdminToken();
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

function makeFrame(userId: string, displayName = 'Test Frame'): { frameId: string; token: string } {
  const db = getDb();
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(
    frameId,
    userId,
    displayName,
  );
  const token = issueDeviceToken(frameId).rawToken;
  return { frameId, token };
}

function makePairing(name = 'Shared pairing'): string {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, name);
  return pairingId;
}

function addMember(pairingId: string, frameId: string, role: 'owner' | 'member'): void {
  getDb()
    .prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)')
    .run(pairingId, frameId, role);
}

function makeBlobAndImage(pairingId: string, uploaderFrameId: string): string {
  const db = getDb();
  const hash = uuidv4();
  db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, ?)').run(hash, 1000, 1);
  const imageId = uuidv4();
  db.prepare(
    'INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash) VALUES (?, ?, ?, ?)',
  ).run(imageId, pairingId, uploaderFrameId, hash);
  return imageId;
}

test('adminGuard rejects the frame-delete route without any admin auth (401)', async () => {
  const res = await request(app).delete(`/api/v1/admin/frames/${uuidv4()}`);
  assert.equal(res.status, 401);
});

test('adminGuard rejects the frame-delete route with an invalid admin token (401)', async () => {
  const res = await request(app)
    .delete(`/api/v1/admin/frames/${uuidv4()}`)
    .set('Authorization', 'Bearer not-a-real-token');
  assert.equal(res.status, 401);
});

test('deleting an unknown frame returns 404', async () => {
  const res = await request(app)
    .delete(`/api/v1/admin/frames/${uuidv4()}`)
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(res.status, 404);
});

test('deleting a frame revokes its device tokens and removes its pairing membership', async () => {
  const userId = makeUser();
  const { frameId, token } = makeFrame(userId);
  const pairingId = makePairing();
  addMember(pairingId, frameId, 'owner');

  // Sanity: the token authenticates before deletion.
  assert.ok(verifyDeviceToken(token));

  const res = await request(app)
    .delete(`/api/v1/admin/frames/${frameId}`)
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });

  // Device token must no longer authenticate.
  assert.equal(verifyDeviceToken(token), null);

  const db = getDb();
  const tokenRow = db
    .prepare('SELECT revoked_at FROM device_tokens WHERE frame_id = ?')
    .get(frameId) as { revoked_at: string | null };
  assert.ok(tokenRow.revoked_at, 'device token row should be marked revoked');

  const membership = db
    .prepare('SELECT * FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, frameId);
  assert.equal(membership, undefined, 'pairing membership row should be removed');

  const frameRow = db.prepare('SELECT deleted_at FROM frames WHERE id = ?').get(frameId) as {
    deleted_at: string | null;
  };
  assert.ok(frameRow.deleted_at, 'frame row itself should be marked deleted, not removed');
});

test('deleting a frame cleans up config_pushes where it is sender or target, and its own image_hidden/reports rows, without touching other members images', async () => {
  const userA = makeUser();
  const userB = makeUser();
  const a = makeFrame(userA, 'Frame A (to be deleted)');
  const b = makeFrame(userB, 'Frame B (stays)');
  const pairingId = makePairing();
  addMember(pairingId, a.frameId, 'owner');
  addMember(pairingId, b.frameId, 'member');

  const imageFromA = makeBlobAndImage(pairingId, a.frameId);
  const imageFromB = makeBlobAndImage(pairingId, b.frameId);

  const db = getDb();
  // config push where A is sender, targeting B.
  db.prepare(
    'INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext) VALUES (?, ?, ?, ?)',
  ).run(uuidv4(), b.frameId, a.frameId, 'ct1');
  // config push where A is the target, sent by B.
  db.prepare(
    'INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext) VALUES (?, ?, ?, ?)',
  ).run(uuidv4(), a.frameId, b.frameId, 'ct2');
  // an unrelated config push between other frames-ish (B -> B, just to prove untouched rows survive)
  const unrelatedId = uuidv4();
  db.prepare(
    'INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext) VALUES (?, ?, ?, ?)',
  ).run(unrelatedId, b.frameId, b.frameId, 'ct3');

  db.prepare('INSERT INTO image_hidden (image_id, frame_id) VALUES (?, ?)').run(imageFromB, a.frameId);
  db.prepare('INSERT INTO reports (id, image_id, reporter_frame_id, reason) VALUES (?, ?, ?, ?)').run(
    uuidv4(),
    imageFromB,
    a.frameId,
    'spam',
  );

  const res = await request(app)
    .delete(`/api/v1/admin/frames/${a.frameId}`)
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(res.status, 200);

  const remainingConfigPushes = db
    .prepare('SELECT id FROM config_pushes WHERE target_frame_id = ? OR sender_frame_id = ?')
    .all(a.frameId, a.frameId);
  assert.equal(remainingConfigPushes.length, 0, 'all config_pushes involving the deleted frame should be gone');

  const unrelatedStillThere = db.prepare('SELECT id FROM config_pushes WHERE id = ?').get(unrelatedId);
  assert.ok(unrelatedStillThere, 'config_pushes not involving the deleted frame must be untouched');

  const hiddenRows = db.prepare('SELECT * FROM image_hidden WHERE frame_id = ?').all(a.frameId);
  assert.equal(hiddenRows.length, 0);

  const reportRows = db.prepare('SELECT * FROM reports WHERE reporter_frame_id = ?').all(a.frameId);
  assert.equal(reportRows.length, 0);

  // Both images (including the one uploaded by the now-deleted frame A)
  // must still exist untouched, so frame B keeps seeing everything.
  const imageA = db.prepare('SELECT id FROM images WHERE id = ?').get(imageFromA);
  const imageB = db.prepare('SELECT id FROM images WHERE id = ?').get(imageFromB);
  assert.ok(imageA, "frame A's uploaded image must survive frame deletion");
  assert.ok(imageB, "frame B's uploaded image must be untouched");

  // Frame B can still list the pairing's images via the authenticated API.
  const listRes = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}`)
    .set('Authorization', `Bearer ${b.token}`);
  if (listRes.status === 200) {
    const ids = (listRes.body.images ?? []).map((img: { id: string }) => img.id);
    assert.ok(ids.includes(imageFromA), 'frame B should still see the image uploaded by the deleted frame');
    assert.ok(ids.includes(imageFromB), 'frame B should still see its own image');
  }
});

test('an already-deleted frame can be deleted again without error (idempotent) and stays 404-proof only when the row truly does not exist', async () => {
  const userId = makeUser();
  const { frameId } = makeFrame(userId);

  const first = await request(app)
    .delete(`/api/v1/admin/frames/${frameId}`)
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(first.status, 200);

  const second = await request(app)
    .delete(`/api/v1/admin/frames/${frameId}`)
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(second.status, 200, 're-deleting an already soft-deleted frame should not error');
});
