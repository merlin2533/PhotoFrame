import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('schema-concurrency');

let getDb: typeof import('../src/db').getDb;
let Semaphore: typeof import('../src/util/semaphore').Semaphore;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ Semaphore } = await import('../src/util/semaphore'));
});

test('migration 004 leaves device_tokens.token_hash unique and creates refresh_tokens', () => {
  const db = getDb();

  const version = (db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version;
  assert.equal(version, 4);

  const indexes = db.prepare('PRAGMA index_list(device_tokens)').all() as { name: string; unique: number }[];
  const tokenIndex = indexes.find((i) => i.name === 'idx_device_tokens_token_hash');
  assert.ok(tokenIndex, 'token_hash index must exist');
  assert.equal(tokenIndex.unique, 1, 'token_hash index must be UNIQUE');

  const table = db
    .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'refresh_tokens'")
    .get();
  assert.ok(table, 'refresh_tokens table must exist after migrations');
});

test('a duplicate device token hash is rejected by the database', () => {
  const db = getDb();
  const userId = `dup-user-${Date.now()}`;
  db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(userId, userId, 'hash');
  const frameId = `dup-frame-${Date.now()}`;
  db.prepare('INSERT INTO frames (id, user_id, display_name) VALUES (?, ?, ?)').run(frameId, userId, 'Dup');
  db.prepare('INSERT INTO device_tokens (id, frame_id, token_hash) VALUES (?, ?, ?)').run(
    `a-${frameId}`,
    frameId,
    'same-hash',
  );
  assert.throws(() =>
    db.prepare('INSERT INTO device_tokens (id, frame_id, token_hash) VALUES (?, ?, ?)').run(
      `b-${frameId}`,
      frameId,
      'same-hash',
    ),
  );
});

test('Semaphore never runs more than its limit at once and serves waiters in order', async () => {
  const sem = new Semaphore(2);
  let active = 0;
  let peak = 0;
  const order: number[] = [];

  const task = async (n: number) => {
    const release = await sem.acquire();
    try {
      active += 1;
      peak = Math.max(peak, active);
      order.push(n);
      await new Promise((r) => setTimeout(r, 5));
      active -= 1;
    } finally {
      release();
    }
  };

  await Promise.all([1, 2, 3, 4, 5].map((n) => task(n)));
  assert.equal(peak, 2);
  assert.deepEqual(order, [1, 2, 3, 4, 5]);
});

test('Semaphore ignores a second release call', async () => {
  const sem = new Semaphore(1);
  const first = await sem.acquire();
  first();
  first();

  const second = await sem.acquire();
  let thirdGranted = false;
  const third = sem.acquire().then((release) => {
    thirdGranted = true;
    release();
  });
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(thirdGranted, false, 'a double release must not free more than one slot');
  second();
  await third;
});
