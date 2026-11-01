import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('reports-http');

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;

let app: import('express').Express;

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ issueDeviceToken } = await import('../../src/auth/deviceTokens'));
  app = createApp();
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

/** Creates a pairing with the given frame as owner and an image uploaded by it. */
function makePairingWithImage(ownerFrameId: string): { pairingId: string; imageId: string } {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Reports pairing');
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    ownerFrameId,
    'owner',
  );
  const hash = `hash-${uuidv4()}`;
  db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, 1)').run(hash, 10);
  const imageId = uuidv4();
  db.prepare(
    'INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, client_upload_id) VALUES (?, ?, ?, ?, ?)',
  ).run(imageId, pairingId, ownerFrameId, hash, uuidv4());
  return { pairingId, imageId };
}

test('a pairing member can report an image, and the report is stored with its reporter', async () => {
  const owner = makeFrame();
  const member = makeFrame();
  const { pairingId, imageId } = makePairingWithImage(owner.frameId);
  getDb().prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    member.frameId,
    'member',
  );

  const res = await request(app)
    .post('/api/v1/reports')
    .set('Authorization', `Bearer ${member.token}`)
    .send({ imageId, reason: 'offensive content' });
  assert.equal(res.status, 201);

  const row = getDb().prepare('SELECT reporter_frame_id, reason FROM reports WHERE id = ?').get(res.body.id) as {
    reporter_frame_id: string;
    reason: string;
  };
  assert.equal(row.reporter_frame_id, member.frameId);
  assert.equal(row.reason, 'offensive content');
});

test('a frame outside the image\'s pairing cannot report it (403)', async () => {
  const owner = makeFrame();
  const outsider = makeFrame();
  const { imageId } = makePairingWithImage(owner.frameId);

  const res = await request(app)
    .post('/api/v1/reports')
    .set('Authorization', `Bearer ${outsider.token}`)
    .send({ imageId, reason: 'nope' });
  assert.equal(res.status, 403);
});

test('reporting an unknown image returns 404, and invalid reasons return 400', async () => {
  const owner = makeFrame();
  const { imageId } = makePairingWithImage(owner.frameId);

  const unknown = await request(app)
    .post('/api/v1/reports')
    .set('Authorization', `Bearer ${owner.token}`)
    .send({ imageId: uuidv4(), reason: 'x' });
  assert.equal(unknown.status, 404);

  const empty = await request(app)
    .post('/api/v1/reports')
    .set('Authorization', `Bearer ${owner.token}`)
    .send({ imageId, reason: '' });
  assert.equal(empty.status, 400);

  const tooLong = await request(app)
    .post('/api/v1/reports')
    .set('Authorization', `Bearer ${owner.token}`)
    .send({ imageId, reason: 'r'.repeat(501) });
  assert.equal(tooLong.status, 400);
});

test('reports require a device token', async () => {
  const res = await request(app).post('/api/v1/reports').send({ imageId: uuidv4(), reason: 'x' });
  assert.equal(res.status, 401);
});
