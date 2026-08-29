import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { setupTestEnv } from './helpers/testEnv';

setupTestEnv('pairingcode');

// Dynamic import inside before(): static ESM imports are hoisted and would
// evaluate src/config/env.ts (which fails fast on missing env vars) before
// setupTestEnv() above has a chance to run. tsx transpiles these .ts files
// as CJS, which disallows top-level await, so the import happens in a
// before() hook instead.
let generatePairingCode: typeof import('../src/auth/pairingCode').generatePairingCode;
let hashPairingCode: typeof import('../src/auth/pairingCode').hashPairingCode;

before(async () => {
  ({ generatePairingCode, hashPairingCode } = await import('../src/auth/pairingCode'));
});

test('generatePairingCode produces an 8-char alphanumeric code with a dash', () => {
  const code = generatePairingCode();
  assert.match(code, /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$/);
});

test('hashPairingCode is deterministic for the same code', () => {
  const code = generatePairingCode();
  const hash1 = hashPairingCode(code);
  const hash2 = hashPairingCode(code);
  assert.equal(hash1, hash2);
});

test('hashPairingCode is case- and whitespace-insensitive', () => {
  const hashUpper = hashPairingCode('ABCD-EFGH');
  const hashLower = hashPairingCode('abcd-efgh');
  const hashPadded = hashPairingCode('  ABCD-EFGH  ');
  assert.equal(hashUpper, hashLower);
  assert.equal(hashUpper, hashPadded);
});

test('hashPairingCode produces different hashes for different codes', () => {
  const hashA = hashPairingCode('AAAA-AAAA');
  const hashB = hashPairingCode('BBBB-BBBB');
  assert.notEqual(hashA, hashB);
});

test('hashPairingCode output looks like a hex-encoded HMAC-SHA256 digest', () => {
  const hash = hashPairingCode('AAAA-AAAA');
  assert.match(hash, /^[0-9a-f]{64}$/);
});

test('hashPairingCode matches a manual HMAC-SHA256 computation using the configured pepper', async () => {
  const crypto = await import('node:crypto');
  const { env } = await import('../src/config/env');
  const expected = crypto.createHmac('sha256', env.PAIRING_CODE_PEPPER).update('AAAA-AAAA').digest('hex');
  assert.equal(hashPairingCode('AAAA-AAAA'), expected);
});
