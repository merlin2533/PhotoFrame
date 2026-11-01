import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import sharp from 'sharp';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('image-files-paging-http');

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;
let ensureStorageDirs: typeof import('../../src/storage/contentAddressedStore').ensureStorageDirs;

let app: import('express').Express;
let tinyJpeg: Buffer;

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ issueDeviceToken } = await import('../../src/auth/deviceTokens'));
  ({ ensureStorageDirs } = await import('../../src/storage/contentAddressedStore'));
  ensureStorageDirs();
  app = createApp();
  tinyJpeg = await sharp({
    create: { width: 5, height: 5, channels: 3, background: { r: 1, g: 2, b: 3 } },
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
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Files pairing');
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    ownerFrameId,
    'owner',
  );
  return pairingId;
}

async function uploadImage(token: string, pairingId: string): Promise<{ imageId: string; contentHash: string }> {
  const res = await request(app)
    .post('/api/v1/images')
    .set('Authorization', `Bearer ${token}`)
    .field('pairingId', pairingId)
    .field('clientUploadId', uuidv4())
    .attach('file', tinyJpeg, { filename: 'a.jpg', contentType: 'image/jpeg' });
  assert.equal(res.status, 201);
  return { imageId: res.body.imageId, contentHash: res.body.contentHash };
}

test('the original and the thumbnail are served with private caching and content-addressed ETags', async () => {
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);
  const { imageId, contentHash } = await uploadImage(frame.token, pairingId);

  const original = await request(app)
    .get(`/api/v1/images/${imageId}/file`)
    .set('Authorization', `Bearer ${frame.token}`)
    .buffer(true)
    .parse((res, cb) => {
      const chunks: Buffer[] = [];
      res.on('data', (c: Buffer) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });
  assert.equal(original.status, 200);
  assert.equal(original.headers['content-type'], 'image/jpeg');
  assert.match(original.headers['cache-control'], /^private/);
  assert.equal(original.headers.etag, `"${contentHash}"`);
  assert.ok(Buffer.isBuffer(original.body) && original.body.length > 0);

  const thumb = await request(app)
    .get(`/api/v1/images/${imageId}/file?variant=thumb`)
    .set('Authorization', `Bearer ${frame.token}`);
  assert.equal(thumb.status, 200);
  assert.equal(thumb.headers.etag, `"${contentHash}-thumb"`);
});

test('a matching If-None-Match gets 304 without a body', async () => {
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);
  const { imageId, contentHash } = await uploadImage(frame.token, pairingId);

  const res = await request(app)
    .get(`/api/v1/images/${imageId}/file`)
    .set('Authorization', `Bearer ${frame.token}`)
    .set('If-None-Match', `"${contentHash}"`);
  assert.equal(res.status, 304);
  assert.equal(res.text ?? '', '');
});

test('a non-member gets 403 for the file, even with a matching If-None-Match', async () => {
  const owner = makeFrame();
  const pairingId = makePairing(owner.frameId);
  const { imageId, contentHash } = await uploadImage(owner.token, pairingId);
  const outsider = makeFrame();

  const res = await request(app)
    .get(`/api/v1/images/${imageId}/file`)
    .set('Authorization', `Bearer ${outsider.token}`)
    .set('If-None-Match', `"${contentHash}"`);
  assert.equal(res.status, 403, 'membership must be checked before the 304 shortcut');
});

test('the pairing listing returns everything by default and pages with limit and nextCursor', async () => {
  const db = getDb();
  const frame = makeFrame();
  const pairingId = makePairing(frame.frameId);
  const hash = `hash-${uuidv4()}`;
  db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, 5)').run(hash, 10);
  const inserted: string[] = [];
  for (let i = 0; i < 5; i++) {
    const id = uuidv4();
    inserted.push(id);
    db.prepare(
      'INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, uploaded_at, client_upload_id) VALUES (?, ?, ?, ?, ?, ?)',
    ).run(id, pairingId, frame.frameId, hash, `2026-01-01T00:00:0${i}.000Z`, uuidv4());
  }

  const all = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}`)
    .set('Authorization', `Bearer ${frame.token}`);
  assert.equal(all.status, 200);
  assert.equal(all.body.images.length, 5);
  assert.equal(all.body.nextCursor, null);
  assert.equal(all.body.images[0].id, inserted[4], 'newest first');

  const seen: string[] = [];
  let cursor: string | null = null;
  let pages = 0;
  do {
    const url = `/api/v1/images/pairing/${pairingId}?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`;
    const page = await request(app).get(url).set('Authorization', `Bearer ${frame.token}`);
    assert.equal(page.status, 200);
    assert.ok(page.body.images.length <= 2);
    seen.push(...page.body.images.map((i: any) => i.id));
    cursor = page.body.nextCursor;
    pages += 1;
  } while (cursor && pages < 10);

  assert.equal(pages, 3);
  assert.deepEqual(seen, [...inserted].reverse(), 'paging must neither skip nor repeat rows');

  const badCursor = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}?cursor=not-a-cursor`)
    .set('Authorization', `Bearer ${frame.token}`);
  assert.equal(badCursor.status, 400);

  const zeroLimit = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}?limit=0`)
    .set('Authorization', `Bearer ${frame.token}`);
  assert.equal(zeroLimit.status, 400);
});

test('admin list endpoints page with limit and nextCursor', async () => {
  const db = getDb();
  const ids: string[] = [];
  for (let i = 0; i < 3; i++) {
    const id = uuidv4();
    ids.push(id);
    db.prepare('INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)').run(
      id,
      `pager-${id}`,
      'hash',
      `2026-02-0${i + 1}T00:00:00.000Z`,
    );
  }

  const login = await request(app)
    .post('/api/v1/admin/login')
    .send({ username: 'admin', password: 'test-admin-password' });
  assert.equal(login.status, 200);
  const adminAuth = `Bearer ${login.body.token}`;

  const seen: string[] = [];
  let cursor: string | null = null;
  let pages = 0;
  do {
    const url = `/api/v1/admin/users?limit=1${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`;
    const page = await request(app).get(url).set('Authorization', adminAuth);
    assert.equal(page.status, 200);
    seen.push(...page.body.users.map((u: any) => u.id));
    cursor = page.body.nextCursor;
    pages += 1;
  } while (cursor && pages < 50);

  for (const id of ids) {
    assert.equal(seen.filter((s) => s === id).length, 1, 'every inserted user appears exactly once');
  }
  const unfiltered = await request(app).get('/api/v1/admin/users').set('Authorization', adminAuth);
  assert.equal(unfiltered.status, 200);
  assert.equal(unfiltered.body.nextCursor, null);
});
