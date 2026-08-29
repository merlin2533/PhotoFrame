import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import sharp from 'sharp';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('images-http');

/**
 * HTTP-level tests against the real `createApp()` instance (Code-Review-
 * Backlog: "alle 18 Tests sind Unit-Tests auf Hilfsfunktionen, die komplette
 * Autorisierungsschicht ist ungetestet"). These exercise the actual Express
 * routing/middleware stack (authGuard's requireDeviceAuth + the per-route
 * membership/uploader-or-owner checks in routes/images.ts), not the
 * underlying SQL directly, so a regression in the route wiring itself (not
 * just in a helper function) would be caught here.
 */

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;

let app: import('express').Express;

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ issueDeviceToken } = await import('../../src/auth/deviceTokens'));
  const { ensureStorageDirs } = await import('../../src/storage/contentAddressedStore');
  // Normally done once at server boot (src/index.ts main()) - createApp()
  // alone does not create /data/tmp, and multer's diskStorage needs it to
  // exist before the first upload.
  ensureStorageDirs();
  app = createApp();
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

function makeFrame(userId: string): { frameId: string; token: string } {
  const db = getDb();
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(
    frameId,
    userId,
    'Test Frame',
  );
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

let tinyJpeg: Buffer;

async function uploadImage(
  token: string,
  pairingId: string,
): Promise<{ status: number; body: any }> {
  if (!tinyJpeg) {
    tinyJpeg = await sharp({
      create: { width: 4, height: 4, channels: 3, background: { r: 10, g: 20, b: 30 } },
    })
      .jpeg()
      .toBuffer();
  }

  const res = await request(app)
    .post('/api/v1/images')
    .set('Authorization', `Bearer ${token}`)
    .field('pairingId', pairingId)
    .field('clientUploadId', uuidv4())
    .attach('file', tinyJpeg, { filename: 'test.jpg', contentType: 'image/jpeg' });

  return { status: res.status, body: res.body };
}

test('a non-member frame cannot delete an image in a pairing it does not belong to (403)', async () => {
  const uploaderUserId = makeUser();
  const uploader = makeFrame(uploaderUserId);
  const pairingId = makePairingWithOwner(uploader.frameId);

  const upload = await uploadImage(uploader.token, pairingId);
  assert.equal(upload.status, 201);
  const imageId = upload.body.imageId;

  const outsiderUserId = makeUser();
  const outsider = makeFrame(outsiderUserId); // never joined this pairing

  const del = await request(app)
    .delete(`/api/v1/images/${imageId}`)
    .set('Authorization', `Bearer ${outsider.token}`);
  assert.equal(del.status, 403);

  // The image must still exist - a non-member's rejected delete must not
  // have any side effect.
  const stillThere = getDb().prepare('SELECT id FROM images WHERE id = ?').get(imageId);
  assert.ok(stillThere);
});

test('a non-member frame cannot hide an image in a pairing it does not belong to (403)', async () => {
  const uploaderUserId = makeUser();
  const uploader = makeFrame(uploaderUserId);
  const pairingId = makePairingWithOwner(uploader.frameId);

  const upload = await uploadImage(uploader.token, pairingId);
  const imageId = upload.body.imageId;

  const outsiderUserId = makeUser();
  const outsider = makeFrame(outsiderUserId);

  const hide = await request(app)
    .post(`/api/v1/images/${imageId}/hide`)
    .set('Authorization', `Bearer ${outsider.token}`);
  assert.equal(hide.status, 403);
});

test('only the uploader or a pairing owner may delete an image - a plain member cannot', async () => {
  const uploaderUserId = makeUser();
  const uploader = makeFrame(uploaderUserId);
  const pairingId = makePairingWithOwner(uploader.frameId);

  const memberUserId = makeUser();
  const member = makeFrame(memberUserId);
  addMember(pairingId, member.frameId, 'member');

  const upload = await uploadImage(uploader.token, pairingId);
  const imageId = upload.body.imageId;

  const del = await request(app)
    .delete(`/api/v1/images/${imageId}`)
    .set('Authorization', `Bearer ${member.token}`);
  assert.equal(del.status, 403);
  assert.match(del.body.error, /uploader|owner/i);
});

test('the uploader can delete their own image, which releases the blob refcount and storage_used_bytes', async () => {
  const uploaderUserId = makeUser();
  const uploader = makeFrame(uploaderUserId);
  const pairingId = makePairingWithOwner(uploader.frameId);

  const upload = await uploadImage(uploader.token, pairingId);
  assert.equal(upload.status, 201);
  const imageId = upload.body.imageId;
  const contentHash = upload.body.contentHash;

  const db = getDb();
  const userBefore = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(uploaderUserId) as {
    storage_used_bytes: number;
  };
  assert.ok(userBefore.storage_used_bytes > 0, 'upload must have booked bytes against the uploader');

  // Every test in this file uploads the exact same fixture JPEG, so they all
  // dedup onto one shared blob row (refcount grows across tests, by design -
  // that's the dedup feature being exercised implicitly) - compare against
  // the refcount right after this test's own upload, not an absolute 0.
  const refcountAfterUpload = (
    db.prepare('SELECT refcount FROM blobs WHERE hash = ?').get(contentHash) as { refcount: number }
  ).refcount;

  const del = await request(app)
    .delete(`/api/v1/images/${imageId}`)
    .set('Authorization', `Bearer ${uploader.token}`);
  assert.equal(del.status, 200);

  const blob = db.prepare('SELECT refcount FROM blobs WHERE hash = ?').get(contentHash) as {
    refcount: number;
  };
  assert.equal(
    blob.refcount,
    refcountAfterUpload - 1,
    'deleting this image must decrement the shared blob refcount by exactly 1',
  );

  const userAfter = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(uploaderUserId) as {
    storage_used_bytes: number;
  };
  assert.equal(userAfter.storage_used_bytes, 0, 'storage_used_bytes must be released on delete');
});

test('a pairing owner (not the uploader) may also delete an image', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId);
  const pairingId = makePairingWithOwner(owner.frameId);

  const uploaderUserId = makeUser();
  const uploader = makeFrame(uploaderUserId);
  addMember(pairingId, uploader.frameId, 'member');

  const upload = await uploadImage(uploader.token, pairingId);
  const imageId = upload.body.imageId;

  const del = await request(app)
    .delete(`/api/v1/images/${imageId}`)
    .set('Authorization', `Bearer ${owner.token}`);
  assert.equal(del.status, 200);
});

test('a normal member can hide and unhide an image for themselves', async () => {
  const uploaderUserId = makeUser();
  const uploader = makeFrame(uploaderUserId);
  const pairingId = makePairingWithOwner(uploader.frameId);

  const memberUserId = makeUser();
  const member = makeFrame(memberUserId);
  addMember(pairingId, member.frameId, 'member');

  const upload = await uploadImage(uploader.token, pairingId);
  const imageId = upload.body.imageId;

  const hide = await request(app)
    .post(`/api/v1/images/${imageId}/hide`)
    .set('Authorization', `Bearer ${member.token}`);
  assert.equal(hide.status, 200);

  const hiddenRow = getDb()
    .prepare('SELECT 1 FROM image_hidden WHERE image_id = ? AND frame_id = ?')
    .get(imageId, member.frameId);
  assert.ok(hiddenRow);

  // Hiding is per-viewer: the uploader must still see the image in their own listing.
  const listAsUploader = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}`)
    .set('Authorization', `Bearer ${uploader.token}`);
  assert.ok(listAsUploader.body.images.some((i: any) => i.id === imageId));

  const listAsMember = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}`)
    .set('Authorization', `Bearer ${member.token}`);
  assert.ok(!listAsMember.body.images.some((i: any) => i.id === imageId));

  const unhide = await request(app)
    .post(`/api/v1/images/${imageId}/unhide`)
    .set('Authorization', `Bearer ${member.token}`);
  assert.equal(unhide.status, 200);

  const unhiddenRow = getDb()
    .prepare('SELECT 1 FROM image_hidden WHERE image_id = ? AND frame_id = ?')
    .get(imageId, member.frameId);
  assert.equal(unhiddenRow, undefined);
});

test('a request without any bearer token is rejected with 401 before any membership check runs', async () => {
  const res = await request(app).get('/api/v1/images/pairing/does-not-matter');
  assert.equal(res.status, 401);
});
