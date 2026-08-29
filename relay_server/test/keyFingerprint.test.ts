import { test } from 'node:test';
import assert from 'node:assert/strict';

// keyFingerprint.ts only depends on node:crypto, not on src/config/env, so a
// plain static import is safe here (unlike most other test files in this
// directory, which must defer importing anything that transitively pulls in
// env.ts until after setupTestEnv() has run).
import { deriveKeyFingerprint } from '../src/auth/keyFingerprint';

test('deriveKeyFingerprint returns null for a missing public key', () => {
  assert.equal(deriveKeyFingerprint(null), null);
  assert.equal(deriveKeyFingerprint(undefined), null);
  assert.equal(deriveKeyFingerprint(''), null);
});

test('deriveKeyFingerprint is deterministic for the same public key', () => {
  const key = 'a-fake-public-key-material-000000000000';
  assert.equal(deriveKeyFingerprint(key), deriveKeyFingerprint(key));
});

test('deriveKeyFingerprint is exactly 8 Crockford-Base32 characters', () => {
  const fp = deriveKeyFingerprint('some-public-key');
  assert.equal(fp?.length, 8);
  assert.match(fp!, /^[0-9A-HJKMNP-TV-Z]{8}$/); // Crockford alphabet: no I, L, O, U
});

test('deriveKeyFingerprint differs for different public keys', () => {
  const fpA = deriveKeyFingerprint('public-key-A');
  const fpB = deriveKeyFingerprint('public-key-B');
  assert.notEqual(fpA, fpB);
});
