import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('refcountgc');

let getDb: typeof import('../src/db').getDb;
let commitBlob: typeof import('../src/storage/contentAddressedStore').commitBlob;
let ensureStorageDirs: typeof import('../src/storage/contentAddressedStore').ensureStorageDirs;
let originalPath: typeof import('../src/storage/contentAddressedStore').originalPath;
let releaseBlobRef: typeof import('../src/storage/contentAddressedStore').releaseBlobRef;
let runGarbageCollection: typeof import('../src/storage/contentAddressedStore').runGarbageCollection;
let thumbPath: typeof import('../src/storage/contentAddressedStore').thumbPath;
let UPLOAD_TMP_DIR: string;

before(async () => {
  ({ getDb } = await import('../src/db'));
  ({ commitBlob, ensureStorageDirs, originalPath, releaseBlobRef, runGarbageCollection, thumbPath } =
    await import('../src/storage/contentAddressedStore'));
  ({ UPLOAD_TMP_DIR } = await import('../src/config/env'));
});

function writeTmpFile(content: string): string {
  ensureStorageDirs();
  const tmpPath = `${UPLOAD_TMP_DIR}/${Math.random().toString(36).slice(2)}.tmp`;
  fs.writeFileSync(tmpPath, content);
  return tmpPath;
}

test('commitBlob creates a new blob row with refcount 1', () => {
  const db = getDb();
  const tmpPath = writeTmpFile('hello world 1');
  const hash = commitBlob(tmpPath, 13);

  const row = db.prepare('SELECT * FROM blobs WHERE hash = ?').get(hash) as { refcount: number };
  assert.equal(row.refcount, 1);
  assert.ok(fs.existsSync(originalPath(hash)));
});

test('commitBlob dedups identical content by incrementing refcount instead of duplicating the file', () => {
  const db = getDb();
  const content = 'duplicate content for dedup test';
  const tmpPath1 = writeTmpFile(content);
  const hash1 = commitBlob(tmpPath1, content.length);

  const tmpPath2 = writeTmpFile(content);
  const hash2 = commitBlob(tmpPath2, content.length);

  assert.equal(hash1, hash2);
  const row = db.prepare('SELECT * FROM blobs WHERE hash = ?').get(hash1) as { refcount: number };
  assert.equal(row.refcount, 2);
  // The second temp file must have been discarded, not renamed alongside the first.
  assert.ok(!fs.existsSync(tmpPath2));
});

test('releaseBlobRef decrements refcount but never below zero, and GC only removes zero-refcount blobs', () => {
  const db = getDb();
  const content = 'gc target content';
  const tmpPath = writeTmpFile(content);
  const hash = commitBlob(tmpPath, content.length);
  fs.writeFileSync(thumbPath(hash), 'thumb-bytes');

  // refcount 1 -> GC must not touch it.
  let gcResult = runGarbageCollection();
  assert.ok(fs.existsSync(originalPath(hash)));
  assert.equal(gcResult.deleted, 0);

  releaseBlobRef(hash);
  const row = db.prepare('SELECT refcount FROM blobs WHERE hash = ?').get(hash) as { refcount: number };
  assert.equal(row.refcount, 0);

  // Releasing again must clamp at zero, not go negative.
  releaseBlobRef(hash);
  const row2 = db.prepare('SELECT refcount FROM blobs WHERE hash = ?').get(hash) as { refcount: number };
  assert.equal(row2.refcount, 0);

  gcResult = runGarbageCollection();
  assert.equal(gcResult.deleted, 1);
  assert.ok(!fs.existsSync(originalPath(hash)));
  assert.ok(!fs.existsSync(thumbPath(hash)));
  const rowAfterGc = db.prepare('SELECT * FROM blobs WHERE hash = ?').get(hash);
  assert.equal(rowAfterGc, undefined);
});

test('GC is idempotent and safe to run with nothing to collect', () => {
  const result = runGarbageCollection();
  const result2 = runGarbageCollection();
  assert.equal(result2.deleted, 0);
  assert.ok(result.scanned >= 0);
});
