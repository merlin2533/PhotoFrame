import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('recovery');

let getDb: typeof import('../src/db').getDb;
let recoverFrame: typeof import('../src/auth/recovery').recoverFrame;
let RecoveryError: typeof import('../src/auth/recovery').RecoveryError;
let issueDeviceToken: typeof import('../src/auth/deviceTokens').issueDeviceToken;
let verifyDeviceToken: typeof import('../src/auth/deviceTokens').verifyDeviceToken;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ recoverFrame, RecoveryError } = await import('../src/auth/recovery'));
  ({ issueDeviceToken, verifyDeviceToken } = await import('../src/auth/deviceTokens'));
});

function makeUserAndFrame(publicKey = 'original-public-key-0000000000') {
  const db = getDb();
  const userId = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    userId,
    `user-${userId}`,
    'hash',
  );
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name, public_key) VALUES (?, ?, ?, ?)').run(
    frameId,
    userId,
    'Living Room Frame',
    publicKey,
  );
  return { userId, frameId };
}

test('recoverFrame keeps the same frame_id and rotates the public key', () => {
  const { userId, frameId } = makeUserAndFrame();
  const db = getDb();

  const result = recoverFrame(frameId, userId, 'brand-new-public-key-11111111111');
  assert.equal(result.frameId, frameId);

  const frame = db.prepare('SELECT id, public_key FROM frames WHERE id = ?').get(frameId) as {
    id: string;
    public_key: string;
  };
  assert.equal(frame.id, frameId, 'frame_id must be preserved, not replaced with a new row');
  assert.equal(frame.public_key, 'brand-new-public-key-11111111111');

  const frameCount = db.prepare('SELECT COUNT(*) as count FROM frames').get() as { count: number };
  assert.equal(frameCount.count, 1, 'recovery must not create a second frame row');
});

test('recoverFrame rejects all pending config_pushes targeting the recovered frame', () => {
  const { userId, frameId } = makeUserAndFrame();
  const db = getDb();

  const senderFrameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(
    senderFrameId,
    userId,
    'Other Frame',
  );

  const pendingPushId = uuidv4();
  db.prepare(
    'INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext) VALUES (?, ?, ?, ?)',
  ).run(pendingPushId, frameId, senderFrameId, 'opaque-ciphertext');

  const alreadyAppliedPushId = uuidv4();
  db.prepare(
    `INSERT INTO config_pushes (id, target_frame_id, sender_frame_id, ciphertext, applied_at)
     VALUES (?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`,
  ).run(alreadyAppliedPushId, frameId, senderFrameId, 'already-applied');

  recoverFrame(frameId, userId, 'brand-new-public-key-22222222222');

  const pending = db.prepare('SELECT rejected_at FROM config_pushes WHERE id = ?').get(pendingPushId) as {
    rejected_at: string | null;
  };
  assert.ok(pending.rejected_at, 'pending config push must be rejected after recovery');

  const applied = db.prepare('SELECT rejected_at FROM config_pushes WHERE id = ?').get(alreadyAppliedPushId) as {
    rejected_at: string | null;
  };
  assert.equal(applied.rejected_at, null, 'already-applied pushes must not be touched');
});

test('recoverFrame revokes previously issued device tokens for the frame', () => {
  const { userId, frameId } = makeUserAndFrame();
  const oldToken = issueDeviceToken(frameId);
  assert.ok(verifyDeviceToken(oldToken.rawToken));

  const result = recoverFrame(frameId, userId, 'brand-new-public-key-33333333333');

  assert.equal(verifyDeviceToken(oldToken.rawToken), null, 'old device token must be revoked');
  assert.ok(verifyDeviceToken(result.deviceToken.rawToken), 'new device token must be valid');
});

test('recoverFrame rejects when the frame belongs to a different user', () => {
  const { frameId } = makeUserAndFrame();
  const otherUserId = uuidv4();
  const db = getDb();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    otherUserId,
    `other-${otherUserId}`,
    'hash',
  );

  assert.throws(() => recoverFrame(frameId, otherUserId, 'x'.repeat(20)), RecoveryError);
});

test('recoverFrame rejects an unknown frame id', () => {
  const { userId } = makeUserAndFrame();
  assert.throws(() => recoverFrame(uuidv4(), userId, 'x'.repeat(20)), RecoveryError);
});
