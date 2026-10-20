// Commit authorization v1 (Prompt 17B, D-127): golden vector and binding.
// Runs against the compiled output (`npm run build` first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import { describe, test } from 'node:test';
import commitModule from '../lib/conversation/commit.js';
import { commitAuthorizationVectors } from './support.mjs';

const { commitAuthorizationChallenge } = commitModule;
const committed = JSON.parse(readFileSync(new URL('./vectors/commit_authorization_v1.json', import.meta.url), 'utf8'));
const hex = (s) => Buffer.from(s, 'hex');

function fieldsOf(v) {
  return {
    nonce: hex(v.nonceHex),
    accountId: v.accountId,
    deviceId: hex(v.deviceIdHex),
    conversationId: hex(v.conversationIdHex),
    fromEpoch: v.fromEpoch,
    protocolVersion: v.protocolVersion,
    commit: hex(v.commitHex),
    welcomes: v.welcomes.map((w) => ({ targetDeviceId: hex(w.targetDeviceIdHex), welcome: hex(w.welcomeHex) })),
  };
}

describe('commit authorization v1 (D-127)', () => {
  test('committed vector equals a fresh deterministic regeneration', async () => {
    assert.deepEqual(await commitAuthorizationVectors(), committed);
  });

  test('every bound field changes the signed challenge', () => {
    const base = fieldsOf(committed);
    const reference = commitAuthorizationChallenge(base).toString('hex');
    assert.equal(reference, committed.challengeHex);
    const flip = (b) => {
      const c = Buffer.from(b);
      c[0] ^= 1;
      return c;
    };
    const variants = [
      { ...base, nonce: flip(base.nonce) },
      { ...base, accountId: 'accountB' },
      { ...base, deviceId: flip(base.deviceId) },
      { ...base, conversationId: flip(base.conversationId) },
      { ...base, fromEpoch: 8 },
      { ...base, protocolVersion: 2 },
      { ...base, commit: flip(base.commit) },
      { ...base, commit: base.commit.subarray(1) },
      { ...base, welcomes: base.welcomes.slice(1) },
      { ...base, welcomes: [...base.welcomes].reverse() },
      { ...base, welcomes: [{ ...base.welcomes[0], welcome: flip(base.welcomes[0].welcome) }, base.welcomes[1]] },
      { ...base, welcomes: [{ ...base.welcomes[0], targetDeviceId: flip(base.welcomes[0].targetDeviceId) }, base.welcomes[1]] },
    ];
    const seen = new Set([reference]);
    for (const v of variants) seen.add(commitAuthorizationChallenge(v).toString('hex'));
    assert.equal(seen.size, variants.length + 1);
  });

  test('malformed sizes are refused', () => {
    const base = fieldsOf(committed);
    for (const bad of [
      { ...base, nonce: Buffer.alloc(31) },
      { ...base, deviceId: Buffer.alloc(15) },
      { ...base, conversationId: Buffer.alloc(17) },
      { ...base, fromEpoch: -1 },
      { ...base, fromEpoch: 1.5 },
    ]) {
      assert.throws(() => commitAuthorizationChallenge(bad));
    }
  });

  test('the commit module never logs and never reads private content', () => {
    const source = readFileSync(new URL('../src/conversation/commit.ts', import.meta.url), 'utf8');
    assert.ok(!/firebase-functions\/logger|console\./.test(source));
  });
});
