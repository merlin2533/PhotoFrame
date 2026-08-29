import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('pairingfp');

let getDb: typeof import('../src/db').getDb;
let createApp: typeof import('../src/index').createApp;
let issueDeviceToken: typeof import('../src/auth/deviceTokens').issueDeviceToken;
let recoverFrame: typeof import('../src/auth/recovery').recoverFrame;
let deriveKeyFingerprint: typeof import('../src/auth/keyFingerprint').deriveKeyFingerprint;

let server: http.Server;
let baseUrl: string;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ createApp } = await import('../src/index'));
  ({ issueDeviceToken } = await import('../src/auth/deviceTokens'));
  ({ recoverFrame } = await import('../src/auth/recovery'));
  ({ deriveKeyFingerprint } = await import('../src/auth/keyFingerprint'));

  const app = createApp();
  server = http.createServer(app);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
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

function makeFrame(userId: string, publicKey: string | null): { frameId: string; token: string } {
  const db = getDb();
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name, public_key) VALUES (?, ?, ?, ?)').run(
    frameId,
    userId,
    'Test Frame',
    publicKey,
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
  const db = getDb();
  db.prepare('INSERT INTO pairing_members (pairing_id, frame_id, role) VALUES (?, ?, ?)').run(
    pairingId,
    frameId,
    role,
  );
}

async function api(token: string, method: string, path: string, body?: unknown) {
  const res = await fetch(`${baseUrl}/api/v1${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  let json: any = null;
  try {
    json = await res.json();
  } catch {
    // no body
  }
  return { status: res.status, body: json };
}

test('POST /pairing/create-code returns fp:null with fpReason when the creating frame has no public_key', async () => {
  const userId = makeUser();
  const { token } = makeFrame(userId, null);

  const res = await api(token, 'POST', '/pairing/create-code', { pairingName: 'No Key Yet' });
  assert.equal(res.status, 201);
  assert.equal(res.body.fp, null);
  assert.equal(typeof res.body.fpReason, 'string');
});

test('POST /pairing/create-code returns a matching fp when the creating frame has a public_key', async () => {
  const userId = makeUser();
  const publicKey = 'creating-frame-public-key-material';
  const { token } = makeFrame(userId, publicKey);

  const res = await api(token, 'POST', '/pairing/create-code', { pairingName: 'Has Key' });
  assert.equal(res.status, 201);
  assert.equal(res.body.fp, deriveKeyFingerprint(publicKey));
  assert.equal(res.body.fpReason, undefined);
});

test('GET /pairing/:id exposes keyFingerprint per member, and recovery changes it (old != new)', async () => {
  const ownerUserId = makeUser();
  const oldPublicKey = 'owner-original-public-key-00000000';
  const owner = makeFrame(ownerUserId, oldPublicKey);
  const pairingId = makePairingWithOwner(owner.frameId);

  // A second, independent member queries the pairing so we can observe the
  // owner's fingerprint change from an unaffected vantage point - the
  // owner's OWN device token gets revoked by recovery (by design, see
  // recovery.ts), so it can't be reused to re-query afterwards.
  const observerUserId = makeUser();
  const observer = makeFrame(observerUserId, 'observer-public-key');
  addMember(pairingId, observer.frameId);

  const before1 = await api(observer.token, 'GET', `/pairing/${pairingId}`);
  assert.equal(before1.status, 200);
  const ownerMemberBefore = before1.body.members.find((m: any) => m.frameId === owner.frameId);
  const fpBefore = ownerMemberBefore.keyFingerprint;
  assert.equal(fpBefore, deriveKeyFingerprint(oldPublicKey));

  const newPublicKey = 'owner-recovered-public-key-1111111';
  const recoveryResult = recoverFrame(owner.frameId, ownerUserId, newPublicKey);
  assert.equal(recoveryResult.fp, deriveKeyFingerprint(newPublicKey));
  assert.notEqual(recoveryResult.fp, fpBefore, 'recovery must yield a different fingerprint than before');

  const after1 = await api(observer.token, 'GET', `/pairing/${pairingId}`);
  assert.equal(after1.status, 200);
  const ownerMemberAfter = after1.body.members.find((m: any) => m.frameId === owner.frameId);
  assert.equal(ownerMemberAfter.keyFingerprint, recoveryResult.fp);
  assert.notEqual(ownerMemberAfter.keyFingerprint, fpBefore, 'GET /pairing/:id must reflect the rotated fingerprint');
});

test('DELETE /pairing/:id/members/:frameId - owner can remove a member', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId, 'owner-key-a');
  const pairingId = makePairingWithOwner(owner.frameId);

  const memberUserId = makeUser();
  const member = makeFrame(memberUserId, 'member-key-a');
  addMember(pairingId, member.frameId);

  const res = await api(owner.token, 'DELETE', `/pairing/${pairingId}/members/${member.frameId}`);
  assert.equal(res.status, 200);

  const db = getDb();
  const stillMember = db
    .prepare('SELECT 1 FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, member.frameId);
  assert.equal(stillMember, undefined);
});

test('DELETE /pairing/:id/members/:frameId - a non-owner member is rejected with 403', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId, 'owner-key-b');
  const pairingId = makePairingWithOwner(owner.frameId);

  const memberAUserId = makeUser();
  const memberA = makeFrame(memberAUserId, 'member-key-b1');
  addMember(pairingId, memberA.frameId);

  const memberBUserId = makeUser();
  const memberB = makeFrame(memberBUserId, 'member-key-b2');
  addMember(pairingId, memberB.frameId);

  const res = await api(memberA.token, 'DELETE', `/pairing/${pairingId}/members/${memberB.frameId}`);
  assert.equal(res.status, 403);

  const db = getDb();
  const stillMember = db
    .prepare('SELECT 1 FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, memberB.frameId);
  assert.ok(stillMember, 'member B must not have been removed by a non-owner');
});

test('DELETE /pairing/:id/members/:frameId - owner removing themself is rejected, pointing to /leave', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId, 'owner-key-c');
  const pairingId = makePairingWithOwner(owner.frameId);

  const res = await api(owner.token, 'DELETE', `/pairing/${pairingId}/members/${owner.frameId}`);
  assert.equal(res.status, 400);
  assert.match(res.body.error, /leave/i);

  const db = getDb();
  const stillMember = db
    .prepare('SELECT 1 FROM pairing_members WHERE pairing_id = ? AND frame_id = ?')
    .get(pairingId, owner.frameId);
  assert.ok(stillMember, 'owner must not have been removed via the member-removal route');
});

test('DELETE /pairing/:id/members/:frameId - removing a frame that is not a member returns 404', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId, 'owner-key-d');
  const pairingId = makePairingWithOwner(owner.frameId);

  const res = await api(owner.token, 'DELETE', `/pairing/${pairingId}/members/${uuidv4()}`);
  assert.equal(res.status, 404);
});
