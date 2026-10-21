// D-149: callables act only for accounts with a verified email.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';
import { URL } from 'node:url';
import authModule from '../lib/config/auth.js';

const { verifiedUid } = authModule;
const index = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

describe('verified-email accounts only (D-149)', () => {
  test('an email-link (verified) account is acted for', () => {
    assert.equal(verifiedUid({ uid: 'alice', token: { email_verified: true } }), 'alice');
  });

  test('an unverified password account, a missing claim or no auth is not', () => {
    assert.equal(verifiedUid({ uid: 'mallory', token: { email_verified: false } }), undefined);
    assert.equal(verifiedUid({ uid: 'mallory', token: {} }), undefined);
    assert.equal(verifiedUid(undefined), undefined);
  });

  test('only the boolean true counts', () => {
    for (const value of ['true', 1, 'yes', null]) {
      assert.equal(verifiedUid({ uid: 'mallory', token: { email_verified: value } }), undefined);
    }
  });

  test('the one onCall wrapper passes only a verified uid to every callable', () => {
    assert.match(index, /onCall\(deviceCallOptions, \(request\) => guarded\(event, \(\) => run\(verifiedUid\(request\.auth\),/);
    assert.doesNotMatch(index, /request\.auth\?\.uid/);
  });
});
