import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('config-push-http');

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

function makeUser(): string {
  const id = uuidv4();
  getDb().prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    id,
    `user-${id}`,
    'hash',
  );
  return id;
}

function makeFrame(userId: string): { frameId: string; token: string } {
  const frameId = uuidv4();
  getDb().prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(
    frameId,
    userId,
    'Test Frame',
  );
  return { frameId, token: issueDeviceToken(frameId).rawToken };
}

function makePairing(memberFrameIds: string[]): string {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Shared pairing');
  memberFrameIds.forEach((frameId, index) => {
    db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
      pairingId,
      frameId,
      index === 0 ? 'owner' : 'member',
    );
  });
  return pairingId;
}

test('a frame can push ciphertext to a frame in a shared pairing, and the target sees it as pending', async () => {
  const sender = makeFrame(makeUser());
  const target = makeFrame(makeUser());
  makePairing([sender.frameId, target.frameId]);

  const push = await request(app)
    .post('/api/v1/config-push')
    .set('Authorization', `Bearer ${sender.token}`)
    .send({ targetFrameId: target.frameId, ciphertext: 'opaque-ciphertext' });
  assert.equal(push.status, 201);

  const pending = await request(app)
    .get('/api/v1/config-push/pending')
    .set('Authorization', `Bearer ${target.token}`);
  assert.equal(pending.status, 200);
  const found = pending.body.pushes.find((p: any) => p.id === push.body.id);
  assert.ok(found, 'the pending push must be visible to its target');
  assert.equal(found.ciphertext, 'opaque-ciphertext');
  assert.equal(found.sender_frame_id, sender.frameId);
});

test('pushing to a frame that shares no pairing with the sender is rejected (403)', async () => {
  const sender = makeFrame(makeUser());
  const stranger = makeFrame(makeUser());

  const res = await request(app)
    .post('/api/v1/config-push')
    .set('Authorization', `Bearer ${sender.token}`)
    .send({ targetFrameId: stranger.frameId, ciphertext: 'x' });
  assert.equal(res.status, 403);
});

test('a ciphertext longer than the 65536-character cap is rejected (400)', async () => {
  const sender = makeFrame(makeUser());
  const target = makeFrame(makeUser());
  makePairing([sender.frameId, target.frameId]);

  const res = await request(app)
    .post('/api/v1/config-push')
    .set('Authorization', `Bearer ${sender.token}`)
    .send({ targetFrameId: target.frameId, ciphertext: 'a'.repeat(65537) });
  assert.equal(res.status, 400);
});

test('only the target frame can ack or reject a push; ack hides it from pending', async () => {
  const sender = makeFrame(makeUser());
  const target = makeFrame(makeUser());
  makePairing([sender.frameId, target.frameId]);

  const push = await request(app)
    .post('/api/v1/config-push')
    .set('Authorization', `Bearer ${sender.token}`)
    .send({ targetFrameId: target.frameId, ciphertext: 'to-ack' });
  const pushId = push.body.id as string;

  const ackBySender = await request(app)
    .post(`/api/v1/config-push/${pushId}/ack`)
    .set('Authorization', `Bearer ${sender.token}`);
  assert.equal(ackBySender.status, 404, 'the sender must not be able to ack a push it did not receive');

  const ack = await request(app)
    .post(`/api/v1/config-push/${pushId}/ack`)
    .set('Authorization', `Bearer ${target.token}`);
  assert.equal(ack.status, 200);

  const pending = await request(app)
    .get('/api/v1/config-push/pending')
    .set('Authorization', `Bearer ${target.token}`);
  assert.ok(!pending.body.pushes.some((p: any) => p.id === pushId));

  const rejectApplied = await request(app)
    .post(`/api/v1/config-push/${pushId}/reject`)
    .set('Authorization', `Bearer ${target.token}`);
  assert.equal(rejectApplied.status, 409, 'an already applied push cannot be rejected afterwards');
});

test('the target can reject a pending push, which then leaves the pending list', async () => {
  const sender = makeFrame(makeUser());
  const target = makeFrame(makeUser());
  makePairing([sender.frameId, target.frameId]);

  const push = await request(app)
    .post('/api/v1/config-push')
    .set('Authorization', `Bearer ${sender.token}`)
    .send({ targetFrameId: target.frameId, ciphertext: 'to-reject' });
  const pushId = push.body.id as string;

  const reject = await request(app)
    .post(`/api/v1/config-push/${pushId}/reject`)
    .set('Authorization', `Bearer ${target.token}`);
  assert.equal(reject.status, 200);

  const pending = await request(app)
    .get('/api/v1/config-push/pending')
    .set('Authorization', `Bearer ${target.token}`);
  assert.ok(!pending.body.pushes.some((p: any) => p.id === pushId));
});
