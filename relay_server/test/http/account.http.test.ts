import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('account-http');

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

const PASSWORD = 'correct-horse-battery';

test('refresh rotates the token pair and a used refresh token cannot be replayed', async () => {
  const username = `rotate_${uuidv4().slice(0, 8)}`;
  const register = await request(app)
    .post('/api/v1/auth/register')
    .send({ username, password: PASSWORD });
  assert.equal(register.status, 201);

  const first = register.body.refreshToken as string;
  const rotated = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: first });
  assert.equal(rotated.status, 200);
  assert.ok(rotated.body.accessToken);
  assert.notEqual(rotated.body.refreshToken, first, 'refresh must issue a new refresh token');

  const replay = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: first });
  assert.equal(replay.status, 401, 'the rotated-out refresh token must be revoked');

  const second = await request(app)
    .post('/api/v1/auth/refresh')
    .send({ refreshToken: rotated.body.refreshToken });
  assert.equal(second.status, 200, 'the newest refresh token keeps working');

  const garbage = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: 'not-a-jwt' });
  assert.equal(garbage.status, 401);
});

test('DELETE /account removes the user, their frames and refresh tokens, and releases blob refcounts', async () => {
  const db = getDb();
  const username = `delete_${uuidv4().slice(0, 8)}`;
  const register = await request(app)
    .post('/api/v1/auth/register')
    .send({ username, password: PASSWORD });
  assert.equal(register.status, 201);
  const userId = register.body.userId as string;
  const accessToken = register.body.accessToken as string;

  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Doomed');
  const deviceToken = issueDeviceToken(frameId).rawToken;

  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Doomed pairing');
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    frameId,
    'owner',
  );

  const hash = `hash-${uuidv4()}`;
  db.prepare('INSERT INTO blobs (hash, bytes, refcount) VALUES (?, ?, 1)').run(hash, 1234);
  db.prepare(
    'INSERT INTO images (id, pairing_id, uploaded_by_frame_id, content_hash, client_upload_id) VALUES (?, ?, ?, ?, ?)',
  ).run(uuidv4(), pairingId, frameId, hash, uuidv4());

  const exported = await request(app).get('/api/v1/account/export').set('Authorization', `Bearer ${accessToken}`);
  assert.equal(exported.status, 200);
  assert.equal(exported.body.frames.length, 1);
  assert.equal(exported.body.images.length, 1);

  const res = await request(app).delete('/api/v1/account').set('Authorization', `Bearer ${accessToken}`);
  assert.equal(res.status, 200);

  assert.equal(db.prepare('SELECT id FROM users WHERE id = ?').get(userId), undefined);
  assert.equal(db.prepare('SELECT id FROM frames WHERE id = ?').get(frameId), undefined);
  const remainingTokens = db.prepare('SELECT COUNT(*) AS n FROM refresh_tokens WHERE user_id = ?').get(userId) as {
    n: number;
  };
  assert.equal(remainingTokens.n, 0, 'refresh tokens must cascade with the user');

  const blob = db.prepare('SELECT refcount FROM blobs WHERE hash = ?').get(hash) as { refcount: number };
  assert.equal(blob.refcount, 0, 'the deleted account\'s image reference must be released');

  const probe = await request(app)
    .get(`/api/v1/images/pairing/${pairingId}`)
    .set('Authorization', `Bearer ${deviceToken}`);
  assert.equal(probe.status, 401, 'the deleted frame\'s device token must stop working');
});
