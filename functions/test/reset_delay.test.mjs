// D-082 / D-159: the identity-reset delay can be shortened only explicitly,
// to a whole number of hours from 1 to 168; anything else keeps 7 days.
// Runs against the compiled output: `npm run build` first.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { URL } from 'node:url';
import commonModule from '../lib/device/common.js';

const { identityResetDelayMs, TTL } = commonModule;
const HOUR = 60 * 60 * 1000;

test('absent, malformed or out of range keeps 7 days', () => {
  for (const value of [undefined, '', '0', '169', '-1', '1.5', ' 1', '1h', 'abc', '0001']) {
    assert.equal(identityResetDelayMs(value), TTL.identityResetDelayMs, String(value));
  }
  assert.equal(TTL.identityResetDelayMs, 7 * 24 * HOUR);
});

test('a whole number of hours from 1 to 168 is used as set', () => {
  assert.equal(identityResetDelayMs('1'), HOUR);
  assert.equal(identityResetDelayMs('24'), 24 * HOUR);
  assert.equal(identityResetDelayMs('168'), 168 * HOUR);
});

test('only production sets it, and only to the documented beta value', () => {
  const env = (name) => readFileSync(new URL(`../.env.${name}`, import.meta.url), 'utf8');
  assert.match(env('production'), /^SH_IDENTITY_RESET_DELAY_HOURS=1$/m);
  for (const name of ['development', 'staging']) {
    assert.doesNotMatch(env(name), /SH_IDENTITY_RESET_DELAY_HOURS/);
  }
});
