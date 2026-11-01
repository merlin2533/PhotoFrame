import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('frames-http');

let getDb: typeof import('../../src/db').getDb;
let createApp: typeof import('../../src/index').createApp;
let issueDeviceToken: typeof import('../../src/auth/deviceTokens').issueDeviceToken;
let signAccessToken: typeof import('../../src/auth/jwt').signAccessToken;

let app: import('express').Express;

const PUBLIC_KEY = 'public-key-material-0123456789';
const NEW_PUBLIC_KEY = 'rotated-public-key-material-9876';

before(async () => {
  ({ getDb } = await import('../../src/db'));
  ({ createApp } = await import('../../src/index'));
  ({ issueDeviceToken } = await import('../../src/auth/deviceTokens'));
  ({ signAccessToken } = await import('../../src/auth/jwt'));
  app = createApp();
});

function makeUser(): { userId: string; accessToken: string } {
  const userId = uuidv4();
  getDb().prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    userId,
    `user-${userId}`,
    'hash',
  );
  return { userId, accessToken: signAccessToken(userId) };
}

function makeFrame(userId: string): { frameId: string; token: string } {
  const frameId = uuidv4();
  getDb().prepare('INSERT INTO frames (id, user_id, display_name, public_key) VALUES (?, ?, ?, ?)').run(
    frameId,
    userId,
    'Test Frame',
    PUBLIC_KEY,
  );
  return { frameId, token: issueDeviceToken(frameId).rawToken };
}

test('frame endpoints require a user access token, not a device token', async () => {
  const res = await request(app).get('/api/v1/frames');
  assert.equal(res.status, 401);

  const owner = makeUser();
  const frame = makeFrame(owner.userId);
  const withDeviceToken = await request(app)
    .get('/api/v1/frames')
    .set('Authorization', `Bearer ${frame.token}`);
  assert.equal(withDeviceToken.status, 401, 'a device token must not authorize account-level frame calls');
});

test('registering a frame returns a frame id and a working device token', async () => {
  const owner = makeUser();

  const res = await request(app)
    .post('/api/v1/frames')
    .set('Authorization', `Bearer ${owner.accessToken}`)
    .send({ displayName: 'Living room', publicKey: PUBLIC_KEY });
  assert.equal(res.status, 201);
  assert.ok(res.body.frameId);
  assert.ok(res.body.deviceToken);

  // The device token must pass device auth: an unknown pairing yields 403
  // from the membership check, not 401 from authentication.
  const probe = await request(app)
    .get(`/api/v1/images/pairing/${uuidv4()}`)
    .set('Authorization', `Bearer ${res.body.deviceToken}`);
  assert.equal(probe.status, 403);
});

test('GET /frames lists only the caller\'s own frames', async () => {
  const mine = makeUser();
  const other = makeUser();
  const myFrame = makeFrame(mine.userId);
  const otherFrame = makeFrame(other.userId);

  const res = await request(app).get('/api/v1/frames').set('Authorization', `Bearer ${mine.accessToken}`);
  assert.equal(res.status, 200);
  const ids = res.body.frames.map((f: any) => f.id);
  assert.ok(ids.includes(myFrame.frameId));
  assert.ok(!ids.includes(otherFrame.frameId));
});

test('recovery is refused for a frame owned by another account (403)', async () => {
  const owner = makeUser();
  const intruder = makeUser();
  const frame = makeFrame(owner.userId);

  const res = await request(app)
    .post(`/api/v1/frames/${frame.frameId}/recover`)
    .set('Authorization', `Bearer ${intruder.accessToken}`)
    .send({ newPublicKey: NEW_PUBLIC_KEY });
  assert.equal(res.status, 403);
});

test('recovery rotates the key, revokes old device tokens and rejects pending config pushes', async () => {
  const owner = makeUser();
  const frame = makeFrame(owner.userId);
  const sender = makeFrame(owner.userId);

  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Recovery pairing');
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    frame.frameId,
    'owner',
  );
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    sender.frameId,
    'member',
  );
  const pendingPushId = uuidv4();
  db.prepare('INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext) VALUES (?, ?, ?, ?)').run(
    pendingPushId,
    frame.frameId,
    sender.frameId,
    'encrypted-under-old-key',
  );

  const res = await request(app)
    .post(`/api/v1/frames/${frame.frameId}/recover`)
    .set('Authorization', `Bearer ${owner.accessToken}`)
    .send({ newPublicKey: NEW_PUBLIC_KEY });
  assert.equal(res.status, 200);
  assert.equal(res.body.frameId, frame.frameId);
  assert.ok(res.body.deviceToken);
  assert.equal(typeof res.body.fp, 'string');

  const stored = db.prepare('SELECT public_key FROM frames WHERE id = ?').get(frame.frameId) as {
    public_key: string;
  };
  assert.equal(stored.public_key, NEW_PUBLIC_KEY);

  const pushRow = db.prepare('SELECT rejected_at FROM config_pushes WHERE id = ?').get(pendingPushId) as {
    rejected_at: string | null;
  };
  assert.ok(pushRow.rejected_at, 'a push encrypted under the old key must be rejected by recovery');

  const oldTokenProbe = await request(app)
    .get(`/api/v1/images/pairing/${uuidv4()}`)
    .set('Authorization', `Bearer ${frame.token}`);
  assert.equal(oldTokenProbe.status, 401, 'the pre-recovery device token must be revoked');

  const newTokenProbe = await request(app)
    .get(`/api/v1/images/pairing/${uuidv4()}`)
    .set('Authorization', `Bearer ${res.body.deviceToken}`);
  assert.equal(newTokenProbe.status, 403, 'the recovered device token must authenticate');
});

test('a soft-deleted frame cannot be recovered (410) and no key change is applied', async () => {
  const owner = makeUser();
  const frame = makeFrame(owner.userId);
  getDb()
    .prepare("UPDATE frames SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?")
    .run(frame.frameId);

  const res = await request(app)
    .post(`/api/v1/frames/${frame.frameId}/recover`)
    .set('Authorization', `Bearer ${owner.accessToken}`)
    .send({ newPublicKey: NEW_PUBLIC_KEY });
  assert.equal(res.status, 410);

  const stored = getDb().prepare('SELECT public_key FROM frames WHERE id = ?').get(frame.frameId) as {
    public_key: string;
  };
  assert.equal(stored.public_key, PUBLIC_KEY);
});
