import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('maintenance');

let getDb: typeof import('../src/db').getDb;
let runMaintenance: typeof import('../src/maintenance').runMaintenance;
let UPLOAD_TMP_DIR: string;
let ensureStorageDirs: typeof import('../src/storage/contentAddressedStore').ensureStorageDirs;
let issueDeviceToken: typeof import('../src/auth/deviceTokens').issueDeviceToken;
let verifyDeviceToken: typeof import('../src/auth/deviceTokens').verifyDeviceToken;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ runMaintenance } = await import('../src/maintenance'));
  ({ UPLOAD_TMP_DIR } = await import('../src/config/env'));
  ({ ensureStorageDirs } = await import('../src/storage/contentAddressedStore'));
  ({ issueDeviceToken, verifyDeviceToken } = await import('../src/auth/deviceTokens'));
  ensureStorageDirs();
});

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

test('the maintenance pass removes expired pairing codes and stale temp files, and keeps live rows', async () => {
  const db = getDb();
  const pairingId = uuidv4();
  db.prepare('INSERT INTO pairings (id, name) VALUES (?, ?)').run(pairingId, 'Maintenance');

  const expiredHash = `expired-${uuidv4()}`;
  const liveHash = `live-${uuidv4()}`;
  const insertCode = db.prepare(
    'INSERT INTO pairing_codes (code_hash, pairing_id, expires_at) VALUES (?, ?, ?)',
  );
  insertCode.run(expiredHash, pairingId, new Date(Date.now() - HOUR).toISOString());
  insertCode.run(liveHash, pairingId, new Date(Date.now() + HOUR).toISOString());

  const staleTmp = path.join(UPLOAD_TMP_DIR, `${uuidv4()}.tmp`);
  const freshTmp = path.join(UPLOAD_TMP_DIR, `${uuidv4()}.tmp`);
  fs.writeFileSync(staleTmp, 'stale');
  fs.writeFileSync(freshTmp, 'fresh');
  const twoHoursAgo = new Date(Date.now() - 2 * HOUR);
  fs.utimesSync(staleTmp, twoHoursAgo, twoHoursAgo);

  const result = await runMaintenance();

  assert.equal(db.prepare('SELECT 1 FROM pairing_codes WHERE code_hash = ?').get(expiredHash), undefined);
  assert.ok(db.prepare('SELECT 1 FROM pairing_codes WHERE code_hash = ?').get(liveHash));
  assert.equal(fs.existsSync(staleTmp), false, 'a two-hour-old temp file is a leftover and must go');
  assert.equal(fs.existsSync(freshTmp), true, 'a fresh temp file may belong to an upload in progress');
  assert.ok(result.pairingCodesDeleted >= 1);
  assert.ok(result.tmpFilesRemoved >= 1);

  fs.unlinkSync(freshTmp);
});

test('the maintenance pass deletes only revoked refresh tokens older than the retention window', async () => {
  const db = getDb();
  const userId = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    userId,
    `maint-${userId}`,
    'hash',
  );

  const oldRevoked = uuidv4();
  const recentRevoked = uuidv4();
  const active = uuidv4();
  const insert = db.prepare('INSERT INTO refresh_tokens (jti, user_id, revoked_at) VALUES (?, ?, ?)');
  insert.run(oldRevoked, userId, new Date(Date.now() - 2 * DAY).toISOString());
  insert.run(recentRevoked, userId, new Date(Date.now() - HOUR).toISOString());
  insert.run(active, userId, null);

  await runMaintenance();

  const exists = (jti: string) => db.prepare('SELECT 1 FROM refresh_tokens WHERE jti = ?').get(jti) !== undefined;
  assert.equal(exists(oldRevoked), false);
  assert.equal(exists(recentRevoked), true);
  assert.equal(exists(active), true, 'an unrevoked refresh token must never be removed by maintenance');
});

test('device token last_seen_at is written at most once per minute', () => {
  const db = getDb();
  const userId = uuidv4();
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(
    userId,
    `seen-${userId}`,
    'hash',
  );
  const frameId = uuidv4();
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Seen');
  const rawToken = issueDeviceToken(frameId).rawToken;

  verifyDeviceToken(rawToken);
  const first = db.prepare('SELECT last_seen_at FROM device_tokens WHERE frame_id = ?').get(frameId) as {
    last_seen_at: string;
  };
  assert.ok(first.last_seen_at, 'the first verification must record last_seen_at');

  const tenSecondsAgo = new Date(Date.now() - 10_000).toISOString();
  db.prepare('UPDATE device_tokens SET last_seen_at = ? WHERE frame_id = ?').run(tenSecondsAgo, frameId);
  db.prepare('UPDATE frames SET last_seen_at = ? WHERE id = ?').run(tenSecondsAgo, frameId);

  verifyDeviceToken(rawToken);
  const throttled = db.prepare('SELECT last_seen_at FROM device_tokens WHERE frame_id = ?').get(frameId) as {
    last_seen_at: string;
  };
  assert.equal(throttled.last_seen_at, tenSecondsAgo, 'a write within 60 seconds must be skipped');

  const twoMinutesAgo = new Date(Date.now() - 2 * 60_000).toISOString();
  db.prepare('UPDATE device_tokens SET last_seen_at = ? WHERE frame_id = ?').run(twoMinutesAgo, frameId);
  verifyDeviceToken(rawToken);
  const refreshed = db.prepare('SELECT last_seen_at FROM device_tokens WHERE frame_id = ?').get(frameId) as {
    last_seen_at: string;
  };
  assert.notEqual(refreshed.last_seen_at, twoMinutesAgo, 'a stale value must be refreshed');
  assert.ok(Date.now() - Date.parse(refreshed.last_seen_at) < 10_000);
});
