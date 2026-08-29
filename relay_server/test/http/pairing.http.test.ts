import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { v4 as uuidv4 } from 'uuid';
import { setupTestEnv } from '../helpers/testEnv';

setupTestEnv('pairing-http');

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

test('a non-member cannot read a pairing it does not belong to (403)', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId);
  const create = await request(app)
    .post('/api/v1/pairing/create-code')
    .set('Authorization', `Bearer ${owner.token}`)
    .send({ pairingName: 'Private pairing' });
  assert.equal(create.status, 201);

  const outsiderUserId = makeUser();
  const outsider = makeFrame(outsiderUserId);
  const res = await request(app)
    .get(`/api/v1/pairing/${create.body.pairingId}`)
    .set('Authorization', `Bearer ${outsider.token}`);
  assert.equal(res.status, 403);
});

test('redeeming a code that does not exist at all returns 404 and touches no pairing_codes row', async () => {
  const userId = makeUser();
  const { token } = makeFrame(userId);

  const before1 = (
    getDb().prepare('SELECT COUNT(*) as n FROM pairing_codes').get() as { n: number }
  ).n;

  const res = await request(app)
    .post('/api/v1/pairing/redeem')
    .set('Authorization', `Bearer ${token}`)
    .send({ code: 'ZZZZ-ZZZZ' });
  assert.equal(res.status, 404);

  const after1 = (
    getDb().prepare('SELECT COUNT(*) as n FROM pairing_codes').get() as { n: number }
  ).n;
  assert.equal(after1, before1, 'a redeem attempt against a non-existent code must not create/alter any row');
});

/**
 * Documents a known weakness flagged in the Code-Review-Backlog rather than
 * fixing it: `pairing_codes.attempt_count` is only ever incremented AFTER a
 * successful hash lookup finds a matching, still-valid row - and the very
 * same call that finds it also immediately consumes it. So in practice
 * attempt_count never rises above 1 for a real code, and an attacker
 * brute-forcing the code space leaves literally zero trace on the correct
 * code's row for every failed guess (each miss 404s before any row exists to
 * update) - `attempt_count` does not meaningfully throttle guessing, the
 * external `pairingRedeemRateLimiter` is the only real protection.
 * This test makes that behavior explicit rather than fixing it (optional
 * fix per the review; not implemented in this round).
 */
test('KNOWN WEAKNESS: re-redeeming an already-consumed code fails without ever incrementing attempt_count further', async () => {
  const ownerUserId = makeUser();
  const owner = makeFrame(ownerUserId);
  const create = await request(app)
    .post('/api/v1/pairing/create-code')
    .set('Authorization', `Bearer ${owner.token}`)
    .send({ pairingName: 'Attempt-count demo' });
  assert.equal(create.status, 201);
  const code = create.body.code as string;

  const redeemerUserId = makeUser();
  const redeemer = makeFrame(redeemerUserId);

  const first = await request(app)
    .post('/api/v1/pairing/redeem')
    .set('Authorization', `Bearer ${redeemer.token}`)
    .send({ code });
  assert.equal(first.status, 200);

  const db = getDb();
  const rowAfterFirst = db
    .prepare('SELECT attempt_count, consumed_at FROM pairing_codes WHERE pairing_id = ?')
    .get(create.body.pairingId) as { attempt_count: number; consumed_at: string | null };
  assert.equal(rowAfterFirst.attempt_count, 1);
  assert.ok(rowAfterFirst.consumed_at);

  // A second, different frame tries the SAME already-consumed code again.
  const secondUserId = makeUser();
  const second = makeFrame(secondUserId);
  const secondAttempt = await request(app)
    .post('/api/v1/pairing/redeem')
    .set('Authorization', `Bearer ${second.token}`)
    .send({ code });
  assert.equal(secondAttempt.status, 410, 'an already-consumed code must be rejected');

  const rowAfterSecond = db
    .prepare('SELECT attempt_count FROM pairing_codes WHERE pairing_id = ?')
    .get(create.body.pairingId) as { attempt_count: number };
  assert.equal(
    rowAfterSecond.attempt_count,
    1,
    'the failed re-redeem of a consumed code must NOT increment attempt_count any further - ' +
      'this is the documented weakness: attempt_count cannot reflect repeated/brute-force attempts ' +
      'against an already-resolved code',
  );
});

test('creating a pairing code uses the 15-minute TTL required by docs/PLAN.md', async () => {
  const userId = makeUser();
  const { token } = makeFrame(userId);

  const before1 = Date.now();
  const create = await request(app)
    .post('/api/v1/pairing/create-code')
    .set('Authorization', `Bearer ${token}`)
    .send({ pairingName: 'TTL check' });
  assert.equal(create.status, 201);

  const expiresAtMs = new Date(create.body.expiresAt).getTime();
  const deltaMinutes = (expiresAtMs - before1) / 60_000;
  assert.ok(deltaMinutes > 14.9 && deltaMinutes <= 15.1, `expected ~15 minute TTL, got ${deltaMinutes} minutes`);
});
