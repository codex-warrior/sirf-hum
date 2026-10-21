// Lifecycle authorizations v1 (Prompt 17C): the derived challenges for
// conversation recovery (D-135) and unpairing (D-136). The Dart client
// derives the same bytes from the committed vector.
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import { describe, test } from 'node:test';
import recoveryModule from '../lib/conversation/recovery.js';
import unpairModule from '../lib/couple/unpair.js';
import { lifecycleAuthorizationVectors } from './support.mjs';

const { recoveryAuthorizationChallenge } = recoveryModule;
const { unpairAuthorizationChallenge } = unpairModule;
const committed = JSON.parse(readFileSync(new URL('./vectors/lifecycle_authorization_v1.json', import.meta.url), 'utf8'));
const hex = (s) => Buffer.from(s, 'hex');
const flip = (b) => {
  const c = Buffer.from(b);
  c[0] ^= 1;
  return c;
};

const recoveryFields = () => ({
  nonce: hex(committed.nonceHex),
  accountId: committed.accountId,
  deviceId: hex(committed.deviceIdHex),
  conversationId: hex(committed.recovery.conversationIdHex),
  epoch: committed.recovery.epoch,
  trustEpoch: committed.recovery.trustEpoch,
});
const unpairFields = () => ({
  nonce: hex(committed.nonceHex),
  accountId: committed.accountId,
  deviceId: hex(committed.deviceIdHex),
  coupleId: hex(committed.unpair.coupleIdHex),
});

describe('lifecycle authorizations v1 (D-135, D-136)', () => {
  test('committed vector equals a fresh deterministic regeneration', async () => {
    assert.deepEqual(await lifecycleAuthorizationVectors(), committed);
  });

  test('every bound recovery field changes the signed challenge', () => {
    const base = recoveryFields();
    assert.equal(recoveryAuthorizationChallenge(base).toString('hex'), committed.recovery.challengeHex);
    const variants = [
      { ...base, nonce: flip(base.nonce) },
      { ...base, accountId: 'accountB' },
      { ...base, deviceId: flip(base.deviceId) },
      { ...base, conversationId: flip(base.conversationId) },
      { ...base, epoch: base.epoch + 1 },
      { ...base, trustEpoch: base.trustEpoch + 1 },
    ];
    const seen = new Set([committed.recovery.challengeHex]);
    for (const v of variants) seen.add(recoveryAuthorizationChallenge(v).toString('hex'));
    assert.equal(seen.size, variants.length + 1);
  });

  test('every bound unpair field changes the signed challenge; the two contexts never collide', () => {
    const base = unpairFields();
    assert.equal(unpairAuthorizationChallenge(base).toString('hex'), committed.unpair.challengeHex);
    const variants = [
      { ...base, nonce: flip(base.nonce) },
      { ...base, accountId: 'accountB' },
      { ...base, deviceId: flip(base.deviceId) },
      { ...base, coupleId: flip(base.coupleId) },
    ];
    const seen = new Set([committed.unpair.challengeHex, committed.recovery.challengeHex]);
    for (const v of variants) seen.add(unpairAuthorizationChallenge(v).toString('hex'));
    assert.equal(seen.size, variants.length + 2);
  });

  test('malformed fields are refused', () => {
    assert.throws(() => recoveryAuthorizationChallenge({ ...recoveryFields(), epoch: -1 }));
    assert.throws(() => recoveryAuthorizationChallenge({ ...recoveryFields(), trustEpoch: 1.5 }));
    assert.throws(() => recoveryAuthorizationChallenge({ ...recoveryFields(), conversationId: Buffer.alloc(15) }));
    assert.throws(() => unpairAuthorizationChallenge({ ...unpairFields(), coupleId: Buffer.alloc(17) }));
    assert.throws(() => unpairAuthorizationChallenge({ ...unpairFields(), nonce: Buffer.alloc(31) }));
  });
});
