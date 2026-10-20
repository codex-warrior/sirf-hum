// Pairing state machine and signed domains (Prompt 12, D-101, D-102).
// Pure tests; the flows run against the emulator in emulator/pairing.test.mjs.
import { Buffer } from 'node:buffer';
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import pairingModule from '../lib/couple/pairing.js';
import proofModule from '../lib/device/proof.js';
import stateModule from '../lib/couple/state.js';
import { makeDevice, makeProof } from './support.mjs';

const { invitationTokenHash, stepBinding, TOKEN_PATTERN } = pairingModule;
const { ProofPurpose, verifyDeviceProof, InvalidProofError } = proofModule;
const { assertTransition, IllegalTransitionError, PAIRING_STATUSES, TRANSITIONS, OPEN_STATUSES } = stateModule;

describe('pairing state machine (D-101)', () => {
  // The documented matrix (COUPLE-AND-PAIRING.md §4), written out in full so
  // any change to the code's table must also change this test.
  const allowed = new Set([
    'pending>claimed',
    'pending>cancelled',
    'pending>expired',
    'pending>invalidated',
    'claimed>accepted',
    'claimed>rejected',
    'claimed>cancelled',
    'claimed>expired',
    'claimed>invalidated',
  ]);

  test('exactly the documented transitions are allowed', () => {
    for (const from of PAIRING_STATUSES) {
      for (const to of PAIRING_STATUSES) {
        const ok = allowed.has(`${from}>${to}`);
        assert.equal(TRANSITIONS[from].includes(to), ok, `${from} → ${to}`);
        if (ok) assertTransition(from, to);
        else assert.throws(() => assertTransition(from, to), IllegalTransitionError);
      }
    }
  });

  test('terminal states never move; unknown states never move', () => {
    for (const s of ['accepted', 'rejected', 'cancelled', 'expired', 'invalidated']) assert.deepEqual(TRANSITIONS[s], []);
    for (const bad of [undefined, null, '', 'paired', 'ACCEPTED', 1, {}]) {
      for (const to of PAIRING_STATUSES) assert.throws(() => assertTransition(bad, to), IllegalTransitionError);
    }
    assert.deepEqual([...OPEN_STATUSES], ['pending', 'claimed']);
  });

  test('nothing re-enters an open state or skips the invitee', () => {
    for (const from of PAIRING_STATUSES) assert.ok(!TRANSITIONS[from].includes('pending'));
    assert.ok(!TRANSITIONS.pending.includes('accepted'), 'no couple without the invitee accepting first');
  });
});

describe('pairing secrets and bindings', () => {
  test('tokens are hashed with their own domain; step bindings separate steps and subjects', () => {
    const token = Buffer.alloc(16, 1).toString('base64url');
    assert.match(token, TOKEN_PATTERN);
    assert.match(invitationTokenHash(token), /^[0-9a-f]{64}$/);
    assert.notEqual(invitationTokenHash(token), invitationTokenHash(Buffer.alloc(16, 2).toString('base64url')));
    const id = 'ab'.repeat(16);
    const bindings = new Set([
      stepBinding('create', ''),
      stepBinding('accept', invitationTokenHash(token)),
      stepBinding('confirm', id),
      stepBinding('reject', id),
      stepBinding('cancel', id),
      stepBinding('cancel', 'cd'.repeat(16)),
    ]);
    assert.equal(bindings.size, 6);
    assert.ok(!TOKEN_PATTERN.test('a'.repeat(21)) && !TOKEN_PATTERN.test(`${'a'.repeat(21)}=`));
  });

  test('purpose 4 (pairing) is its own signed domain (D-070, D-102)', () => {
    assert.equal(ProofPurpose.pairing, 4);
    // Every purpose, including commit = 5, approvalRejection = 6 (D-127,
    // D-129), conversationRecovery = 7 and unpair = 8 (D-135, D-136).
    assert.deepEqual(Object.values(ProofPurpose), [1, 2, 3, 4, 5, 6, 7, 8]);
    const d = makeDevice(0x21, 0x22, 'e1e2e3e4e5e6e7e8e9eaebecedeeeff0');
    const challenge = Buffer.alloc(32, 9);
    for (const made of Object.values(ProofPurpose)) {
      const { signature } = makeProof({ device: d.device, accountId: 'acct', deviceId: d.deviceId, certificate: d.certificate, challenge, purpose: made });
      for (const checked of Object.values(ProofPurpose)) {
        if (made === checked) assert.ok(verifyDeviceProof(checked, 'acct', d.certificate, challenge, signature));
        else assert.throws(() => verifyDeviceProof(checked, 'acct', d.certificate, challenge, signature), InvalidProofError);
      }
    }
  });
});
