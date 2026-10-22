// D-149: callables act only for accounts with a verified email.
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
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

// D-150: Google is a second way to name the account, never a source of
// authority. The server sees a uid and email_verified, nothing else.
describe('the sign-in provider grants nothing (D-150)', () => {
  const google = (verified) => ({
    uid: 'alice',
    token: { email_verified: verified, firebase: { sign_in_provider: 'google.com' } },
  });

  test('a verified Google account is acted for exactly like an email-link one', () => {
    assert.equal(verifiedUid(google(true)), 'alice');
  });

  test('an unverified Google account is refused like any other', () => {
    assert.equal(verifiedUid(google(false)), undefined);
  });

  test('no Functions code reads the sign-in provider or a Google token', () => {
    const src = new URL('../src/', import.meta.url);
    const files = readdirSync(src, { recursive: true }).filter((f) => String(f).endsWith('.ts'));
    assert.ok(files.length > 10);
    for (const file of files) {
      const text = readFileSync(new URL(String(file).replaceAll('\\', '/'), src), 'utf8');
      assert.doesNotMatch(text, /sign_in_provider|google\.com|identities|idToken/, String(file));
    }
  });
});
