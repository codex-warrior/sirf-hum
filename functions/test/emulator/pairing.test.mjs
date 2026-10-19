// Couple pairing against the Firestore emulator (Prompt 12, D-100–D-105).
// Devices carry real Ed25519 keys and server records; every step is signed
// with the device key (proof purpose `pairing` = 4).
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import { Buffer } from 'node:buffer';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import process from 'node:process';
import { URL } from 'node:url';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import common from '../../lib/device/common.js';
import proofModule from '../../lib/device/proof.js';
import pairingModule from '../../lib/couple/pairing.js';
import stateModule from '../../lib/couple/state.js';
import { makeDevice, makeProof } from '../support.mjs';

const { DeviceError } = common;
const { ProofPurpose } = proofModule;
const {
  acceptPairingInvitation,
  cancelPairing,
  confirmPairing,
  createPairingInvitation,
  getPairingState,
  rejectPairing,
  requestPairingChallenge,
} = pairingModule;
const { PairingError, PairingTTL } = stateModule;

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'pairing-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const account = () => `pr${++n}x${Date.now()}`;
const later = (ms) => new Date(Date.now() + ms);

/** A device with real keys and its server record. */
async function device(accountId = account(), status = 'active') {
  n += 1;
  const id = Buffer.alloc(16);
  id.writeUInt32BE(n, 0);
  id.writeUInt32BE(Date.now() % 0xffffffff, 4);
  id.writeUInt32BE((n * 2654435761) >>> 0, 8);
  id.writeUInt32BE(0x5a17, 12);
  const d = makeDevice((n % 200) + 1, ((n * 7) % 200) + 3, id.toString('hex'));
  const hex = d.deviceId.toString('hex');
  await db.doc(`users/${accountId}/devices/${hex}`).set({ schemaVersion: 1, status, certificate: d.certificate });
  return { ...d, hex, accountId };
}

const setStatus = (d, status) => db.doc(`users/${d.accountId}/devices/${d.hex}`).update({ status });

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof PairingError || e instanceof DeviceError, `expected ${failure}, got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

/** Challenge for one step, signed by `signer`'s device key. */
async function signed(d, action, extra = {}, { signer = d, purpose = ProofPurpose.pairing, at = new Date() } = {}) {
  const issued = await requestPairingChallenge(db, d.accountId, { deviceId: d.hex, action, ...extra }, at);
  const { signature } = makeProof({
    device: signer.device,
    accountId: d.accountId,
    deviceId: d.deviceId,
    certificate: d.certificate,
    challenge: Buffer.from(issued.challenge, 'base64'),
    purpose,
  });
  return { deviceId: d.hex, challengeId: issued.challengeId, proof: signature.toString('base64'), ...extra };
}

const create = async (d, opts = {}) => createPairingInvitation(db, d.accountId, await signed(d, 'create', {}, opts), opts.at ?? new Date());
const accept = async (d, token, opts = {}) =>
  acceptPairingInvitation(db, d.accountId, await signed(d, 'accept', { token }, opts), opts.at ?? new Date());
const confirm = async (d, pairingId, opts = {}) =>
  confirmPairing(db, d.accountId, await signed(d, 'confirm', { pairingId }, opts), opts.at ?? new Date());
const reject = async (d, pairingId, opts = {}) =>
  rejectPairing(db, d.accountId, await signed(d, 'reject', { pairingId }, opts), opts.at ?? new Date());
const cancel = async (d, pairingId, opts = {}) =>
  cancelPairing(db, d.accountId, await signed(d, 'cancel', { pairingId }, opts), opts.at ?? new Date());

const pairingDoc = async (id) => (await db.doc(`pairings/${id}`).get()).data();
const exists = async (path) => (await db.doc(path).get()).exists;

/** Inviter + invitee devices with an invitation the invitee has accepted. */
async function claimed() {
  const a = await device();
  const b = await device();
  const invite = await create(a);
  const accepted = await accept(b, invite.token);
  return { a, b, invite, accepted };
}

describe('pairing happy path (D-101, D-104)', () => {
  test('create → accept → confirm yields one couple, its conversation and both partner records', async () => {
    const a = await device();
    const b = await device();
    await db.doc(`users/${a.accountId}`).set({ schemaVersion: 1, displayName: 'Asha' });
    await db.doc(`users/${b.accountId}`).set({ schemaVersion: 1, displayName: 'Bilal' });

    const invite = await create(a);
    assert.match(invite.pairingId, /^[0-9a-f]{32}$/);
    assert.match(invite.token, /^[A-Za-z0-9_-]{22}$/);
    assert.ok(invite.expiresAtMillis > Date.now() + PairingTTL.invitationMs - 60_000);
    let p = await pairingDoc(invite.pairingId);
    assert.equal(p.status, 'pending');
    assert.equal(p.inviterAccountId, a.accountId);
    assert.equal(p.inviterDeviceId, a.hex);
    assert.ok(!JSON.stringify(p).includes(invite.token), 'only the token hash is stored');
    assert.deepEqual(await getPairingState(db, a.accountId, new Date()), {
      state: 'invited',
      pairingId: invite.pairingId,
      expiresAtMillis: invite.expiresAtMillis,
    });

    const accepted = await accept(b, invite.token);
    assert.equal(accepted.pairingId, invite.pairingId);
    assert.match(accepted.confirmationCode, /^\d{6}$/);
    assert.equal(accepted.partnerDisplayName, 'Asha');
    p = await pairingDoc(invite.pairingId);
    assert.equal(p.status, 'claimed');
    assert.equal(p.inviteeAccountId, b.accountId);
    assert.equal(p.tokenHash, undefined, 'the token can never match again');
    const forA = await getPairingState(db, a.accountId, new Date());
    const forB = await getPairingState(db, b.accountId, new Date());
    assert.equal(forA.state, 'awaiting_confirmation');
    assert.equal(forA.role, 'inviter');
    assert.equal(forA.partnerDisplayName, 'Bilal');
    assert.equal(forB.role, 'invitee');
    assert.equal(forA.confirmationCode, accepted.confirmationCode, 'both screens show the same code');
    assert.equal(forB.confirmationCode, accepted.confirmationCode);

    const done = await confirm(a, invite.pairingId);
    assert.match(done.coupleId, /^[0-9a-f]{32}$/);
    assert.match(done.conversationId, /^[0-9a-f]{32}$/);
    const members = [a.accountId, b.accountId].sort();

    const couple = (await db.doc(`couples/${done.coupleId}`).get()).data();
    assert.deepEqual(Object.keys(couple).sort(), ['createdAt', 'members', 'pairingId', 'schemaVersion', 'status']);
    assert.deepEqual(couple.members, members);
    assert.equal(couple.status, 'active');
    assert.equal(couple.pairingId, invite.pairingId);

    const conv = (await db.doc(`conversations/${done.conversationId}`).get()).data();
    assert.deepEqual(conv.members, members);
    assert.equal(conv.coupleId, done.coupleId);
    assert.equal(conv.state, 'active');
    assert.equal(conv.epoch, 0);
    for (const [self, other] of [
      [a, b],
      [b, a],
    ]) {
      const partner = (await db.doc(`accountPartners/${self.accountId}`).get()).data();
      assert.deepEqual(partner, {
        schemaVersion: 1,
        partnerAccountId: other.accountId,
        conversationId: done.conversationId,
        coupleId: done.coupleId,
      });
      assert.equal(await exists(`pairingLocks/${self.accountId}`), false);
      assert.deepEqual(await getPairingState(db, self.accountId, new Date()), {
        state: 'paired',
        coupleId: done.coupleId,
        conversationId: done.conversationId,
      });
    }
    p = await pairingDoc(invite.pairingId);
    assert.equal(p.status, 'accepted');
    assert.deepEqual(p.accounts, [a.accountId, b.accountId]);
    assert.equal(p.coupleId, done.coupleId);
    assert.equal(p.confirmationCode, undefined);
    assert.equal(p.confirmedByDeviceId, a.hex);
  });

  test('any active device of the inviter may confirm; a retried confirm returns the same couple', async () => {
    const { a, invite } = await claimed();
    const a2 = await device(a.accountId);
    const first = await confirm(a2, invite.pairingId);
    const again = await confirm(a, invite.pairingId);
    assert.deepEqual(again, first);
    const couples = await db.collection('couples').where('pairingId', '==', invite.pairingId).get();
    assert.equal(couples.size, 1);
  });

  test('an account without a profile pairs too (display name is optional)', async () => {
    const { accepted } = await claimed();
    assert.equal(accepted.partnerDisplayName, null);
  });
});

describe('single use, replay, expiry, cancellation, rejection', () => {
  test('a token redeems once; replays and consumed challenges fail', async () => {
    const { b, invite } = await claimed();
    const c = await device();
    await rejectsWith(accept(c, invite.token), 'invitation_invalid');
    // The claimant itself is in an open pairing: refused before the token is looked at.
    await rejectsWith(accept(b, invite.token), 'pairing_in_progress');
    // A consumed challenge cannot be replayed.
    const args = await signed(c, 'accept', { token: invite.token });
    await rejectsWith(acceptPairingInvitation(db, c.accountId, args, new Date()), 'invitation_invalid');
    await rejectsWith(acceptPairingInvitation(db, c.accountId, args, new Date()), 'challenge_invalid');
  });

  test('an invitation expires on the server clock, whatever the client believes', async () => {
    const a = await device();
    const b = await device();
    const invite = await create(a);
    const at = later(PairingTTL.invitationMs + 1000);
    await rejectsWith(accept(b, invite.token, { at }), 'invitation_invalid');
    assert.equal((await pairingDoc(invite.pairingId)).status, 'expired');
    // The expired invitation no longer blocks a new one.
    const fresh = await create(a);
    assert.notEqual(fresh.pairingId, invite.pairingId);
    // Just before the deadline it still works.
    const accepted = await accept(b, fresh.token, { at: later(PairingTTL.invitationMs - 60_000) });
    assert.equal(accepted.pairingId, fresh.pairingId);
  });

  test('the confirmation window expires; both accounts are free again', async () => {
    const { a, b, invite } = await claimed();
    const at = later(PairingTTL.confirmationMs + 1000);
    await rejectsWith(confirm(a, invite.pairingId, { at }), 'pairing_expired');
    assert.equal((await pairingDoc(invite.pairingId)).status, 'expired');
    assert.equal(await exists(`pairingLocks/${a.accountId}`), false);
    assert.equal(await exists(`pairingLocks/${b.accountId}`), false);
    assert.deepEqual(await getPairingState(db, b.accountId, at), { state: 'none' });
  });

  test('the inviter cancels a pending invitation; the token dies with it', async () => {
    const a = await device();
    const b = await device();
    const invite = await create(a);
    await cancel(a, invite.pairingId);
    await cancel(a, invite.pairingId); // idempotent retry
    const p = await pairingDoc(invite.pairingId);
    assert.equal(p.status, 'cancelled');
    assert.equal(p.endReason, 'cancelled_by_inviter');
    assert.equal(p.tokenHash, undefined);
    await rejectsWith(accept(b, invite.token), 'invitation_invalid');
    await rejectsWith(confirm(a, invite.pairingId), 'pairing_not_open');
  });

  test('the invitee withdraws after accepting; the inviter can no longer confirm', async () => {
    const { a, b, invite } = await claimed();
    await cancel(b, invite.pairingId);
    assert.equal((await pairingDoc(invite.pairingId)).endReason, 'cancelled_by_invitee');
    await rejectsWith(confirm(a, invite.pairingId), 'pairing_not_open');
    assert.equal(await exists(`accountPartners/${a.accountId}`), false);
  });

  test('the inviter rejects the account that accepted (e.g. an intercepted link)', async () => {
    const { a, b, invite } = await claimed();
    await rejectsWith(reject(b, invite.pairingId), 'pairing_not_open'); // only the inviter rejects
    await reject(a, invite.pairingId);
    assert.equal((await pairingDoc(invite.pairingId)).status, 'rejected');
    await rejectsWith(confirm(a, invite.pairingId), 'pairing_not_open');
    await rejectsWith(cancel(b, invite.pairingId), 'pairing_not_open');
    assert.equal(await exists(`pairingLocks/${b.accountId}`), false);
    // Pending invitations cannot be "rejected" (cancel them instead).
    const other = await create(a);
    await rejectsWith(reject(a, other.pairingId), 'pairing_not_open');
  });
});

describe('wrong account, wrong device, revoked device', () => {
  test('only the inviter confirms; strangers see "not found" for any pairing', async () => {
    const { b, invite } = await claimed();
    const stranger = await device();
    await rejectsWith(confirm(b, invite.pairingId), 'pairing_not_found');
    await rejectsWith(confirm(stranger, invite.pairingId), 'pairing_not_found');
    await rejectsWith(cancel(stranger, invite.pairingId), 'pairing_not_found');
    await rejectsWith(reject(stranger, invite.pairingId), 'pairing_not_found');
    // An unknown ID looks exactly the same.
    await rejectsWith(confirm(stranger, 'ab'.repeat(16)), 'pairing_not_found');
  });

  test('an account cannot accept its own invitation', async () => {
    const a = await device();
    const a2 = await device(a.accountId);
    const invite = await create(a);
    await rejectsWith(accept(a2, invite.token), 'invitation_invalid');
  });

  test('a password alone cannot pair: every step needs the device key', async () => {
    const a = await device();
    const attackerKey = await device();
    // Signed by another key, or for another purpose.
    await rejectsWith(create(a, { signer: attackerKey }), 'proof_invalid');
    await rejectsWith(create(a, { purpose: ProofPurpose.pushToken }), 'proof_invalid');
    await rejectsWith(create(a, { purpose: ProofPurpose.activation }), 'proof_invalid');
    assert.equal(await exists(`pairingLocks/${a.accountId}`), false);
    // And no device ID of the account works without its key.
    const { b, invite } = await claimed();
    const victim = await device(b.accountId);
    await rejectsWith(cancel(victim, invite.pairingId, { signer: attackerKey }), 'proof_invalid');
    assert.equal((await pairingDoc(invite.pairingId)).status, 'claimed');
  });

  test('a challenge is bound to one step, one subject, one account', async () => {
    const a = await device();
    const b = await device();
    const invite = await create(a);
    const other = await create(await device());
    // A `create` challenge presented to `accept`.
    const forCreate = await signed(b, 'create');
    await rejectsWith(acceptPairingInvitation(db, b.accountId, { ...forCreate, token: invite.token }, new Date()), 'challenge_invalid');
    // Signed for token A, presented with token B.
    const forA = await signed(b, 'accept', { token: invite.token });
    await rejectsWith(acceptPairingInvitation(db, b.accountId, { ...forA, token: other.token }, new Date()), 'challenge_invalid');
    // Another account presenting someone else's challenge.
    const c = await device();
    const forB = await signed(b, 'accept', { token: invite.token });
    await rejectsWith(acceptPairingInvitation(db, c.accountId, { ...forB, deviceId: b.hex }, new Date()), 'challenge_invalid');
    // A challenge outlives neither its own expiry.
    const stale = await signed(b, 'accept', { token: invite.token });
    await rejectsWith(acceptPairingInvitation(db, b.accountId, stale, later(10 * 60 * 1000)), 'challenge_expired');
  });

  test('pending, revoked, rejected, expired and unknown devices get no challenge', async () => {
    const accountId = account();
    for (const status of ['pending', 'revoked', 'rejected', 'expired']) {
      const d = await device(accountId, status);
      await rejectsWith(requestPairingChallenge(db, accountId, { deviceId: d.hex, action: 'create' }, new Date()), 'device_not_active');
    }
    await rejectsWith(
      requestPairingChallenge(db, accountId, { deviceId: 'cd'.repeat(16), action: 'create' }, new Date()),
      'device_not_found',
    );
    await rejectsWith(requestPairingChallenge(db, undefined, { deviceId: 'cd'.repeat(16), action: 'create' }, new Date()), 'unauthenticated');
  });

  test('a device revoked between its challenge and its step is refused', async () => {
    const a = await device();
    const args = await signed(a, 'create');
    await setStatus(a, 'revoked');
    await rejectsWith(createPairingInvitation(db, a.accountId, args, new Date()), 'device_not_active');
    assert.equal(await exists(`pairingLocks/${a.accountId}`), false);
  });

  test("revoking the inviter's creating device invalidates its invitation", async () => {
    const a = await device();
    const b = await device();
    const invite = await create(a);
    await setStatus(a, 'revoked');
    await rejectsWith(accept(b, invite.token), 'invitation_invalid');
    const p = await pairingDoc(invite.pairingId);
    assert.equal(p.status, 'invalidated');
    assert.equal(p.endReason, 'inviter_device_inactive');
  });

  test("revoking the invitee's accepting device invalidates the claim at confirmation", async () => {
    const { a, b, invite } = await claimed();
    await setStatus(b, 'revoked');
    await rejectsWith(confirm(a, invite.pairingId), 'pairing_invalidated');
    assert.equal((await pairingDoc(invite.pairingId)).endReason, 'invitee_device_inactive');
    assert.equal(await exists(`accountPartners/${a.accountId}`), false);
    assert.equal(await exists(`pairingLocks/${a.accountId}`), false);
    assert.equal(await exists(`pairingLocks/${b.accountId}`), false);
  });
});

describe('identity reset and trust changes (D-082)', () => {
  test('an account with a pending identity reset cannot create or accept', async () => {
    const a = await device();
    await db.doc(`accountTrust/${a.accountId}`).set({ trustEpoch: 3, reset: { status: 'pending', effectiveAtMillis: Date.now() + 1e9 } });
    await rejectsWith(create(a), 'identity_reset_pending');
    const inviter = await device();
    const invite = await create(inviter);
    await rejectsWith(accept(a, invite.token), 'identity_reset_pending');
    assert.equal((await pairingDoc(invite.pairingId)).status, 'pending', 'the invitation is not consumed');
  });

  test('a reset requested by either side between accept and confirm invalidates the pairing', async () => {
    for (const side of ['a', 'b']) {
      const pair = await claimed();
      await db.doc(`accountTrust/${pair[side].accountId}`).set(
        { reset: { status: 'pending', effectiveAtMillis: Date.now() + 1e9 } },
        { merge: true },
      );
      await rejectsWith(confirm(pair.a, pair.invite.pairingId), 'pairing_invalidated');
      const p = await pairingDoc(pair.invite.pairingId);
      assert.equal(p.status, 'invalidated');
      assert.equal(p.endReason, side === 'a' ? 'inviter_identity_changed' : 'invitee_identity_changed');
    }
  });

  test('a completed reset (new identity epoch) on the inviter invalidates its invitation', async () => {
    const a = await device();
    const b = await device();
    const invite = await create(a);
    await db.doc(`accountTrust/${a.accountId}`).set({ identityEpoch: 1 }, { merge: true });
    await rejectsWith(accept(b, invite.token), 'invitation_invalid');
    assert.equal((await pairingDoc(invite.pairingId)).endReason, 'inviter_identity_changed');
  });

  test('a reset committed concurrently with confirmation never yields a couple with a reset account', async () => {
    const { a, b, invite } = await claimed();
    const args = await signed(a, 'confirm', { pairingId: invite.pairingId });
    const [result] = await Promise.allSettled([
      confirmPairing(db, a.accountId, args, new Date()),
      db.doc(`accountTrust/${b.accountId}`).set({ reset: { status: 'pending', effectiveAtMillis: Date.now() + 1e9 } }, { merge: true }),
    ]);
    const p = await pairingDoc(invite.pairingId);
    if (result.status === 'fulfilled') {
      // The confirmation serialized first: the reset came after the couple.
      assert.equal(p.status, 'accepted');
    } else {
      assert.equal(result.reason.failure, 'pairing_invalidated');
      assert.equal(p.status, 'invalidated');
      assert.equal(await exists(`accountPartners/${a.accountId}`), false);
    }
  });
});

describe('already paired, concurrency and stale state', () => {
  test('a paired account cannot create, accept or be confirmed into a second couple', async () => {
    const { a, b, invite } = await claimed();
    await confirm(a, invite.pairingId);
    await rejectsWith(create(a), 'already_paired');
    const c = await device();
    const other = await create(c);
    await rejectsWith(accept(b, other.token), 'already_paired');
    assert.equal((await pairingDoc(other.pairingId)).status, 'pending');
  });

  test("accepting someone else's invitation supersedes one's own unredeemed invitation", async () => {
    const a = await device();
    const b = await device();
    const own = await create(b);
    const invite = await create(a);
    await accept(b, invite.token);
    const ownDoc = await pairingDoc(own.pairingId);
    assert.equal(ownDoc.status, 'cancelled');
    assert.equal(ownDoc.endReason, 'superseded');
    await rejectsWith(accept(await device(), own.token), 'invitation_invalid');
  });

  test('an account in an open pairing with someone cannot start another', async () => {
    const { a, b } = await claimed();
    await rejectsWith(create(a), 'pairing_in_progress');
    await rejectsWith(create(b), 'pairing_in_progress');
    const c = await device();
    const third = await create(c);
    await rejectsWith(accept(a, third.token), 'pairing_in_progress');
  });

  test('concurrent acceptance of one token: exactly one account wins', async () => {
    const a = await device();
    const invite = await create(a);
    const claimants = await Promise.all([1, 2, 3, 4].map(() => device()));
    const signedArgs = await Promise.all(claimants.map((c) => signed(c, 'accept', { token: invite.token })));
    const results = await Promise.allSettled(
      claimants.map((c, i) => acceptPairingInvitation(db, c.accountId, signedArgs[i], new Date())),
    );
    const won = results.filter((r) => r.status === 'fulfilled');
    assert.equal(won.length, 1);
    for (const r of results.filter((x) => x.status === 'rejected')) assert.equal(r.reason.failure, 'invitation_invalid');
    const winner = claimants[results.indexOf(won[0])];
    assert.equal((await pairingDoc(invite.pairingId)).inviteeAccountId, winner.accountId);
  });

  test('concurrent invitations from one account: exactly one is created', async () => {
    const a = await device();
    const a2 = await device(a.accountId);
    const args = await Promise.all([a, a2, a].map((d) => signed(d, 'create')));
    const results = await Promise.allSettled(args.map((x) => createPairingInvitation(db, a.accountId, x, new Date())));
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    for (const r of results.filter((x) => x.status === 'rejected')) assert.equal(r.reason.failure, 'pairing_in_progress');
    const open = await db.collection('pairings').where('inviterAccountId', '==', a.accountId).where('status', '==', 'pending').get();
    assert.equal(open.size, 1);
  });

  test('two people accepting each other at once: one pairing, never two', async () => {
    const a = await device();
    const b = await device();
    const fromA = await create(a);
    const fromB = await create(b);
    const [argsB, argsA] = await Promise.all([signed(b, 'accept', { token: fromA.token }), signed(a, 'accept', { token: fromB.token })]);
    const results = await Promise.allSettled([
      acceptPairingInvitation(db, b.accountId, argsB, new Date()),
      acceptPairingInvitation(db, a.accountId, argsA, new Date()),
    ]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    const claimedDocs = await Promise.all([pairingDoc(fromA.pairingId), pairingDoc(fromB.pairingId)]);
    assert.equal(claimedDocs.filter((p) => p.status === 'claimed').length, 1);
  });

  test('concurrent confirmations produce one couple; confirm racing a withdrawal stays consistent', async () => {
    const { a, invite } = await claimed();
    const a2 = await device(a.accountId);
    const args = await Promise.all([signed(a, 'confirm', { pairingId: invite.pairingId }), signed(a2, 'confirm', { pairingId: invite.pairingId })]);
    const results = await Promise.all([a, a2].map((d, i) => confirmPairing(db, d.accountId, args[i], new Date())));
    assert.deepEqual(results[0], results[1]);
    assert.equal((await db.collection('couples').where('pairingId', '==', invite.pairingId).get()).size, 1);

    const race = await claimed();
    const [confirmArgs, cancelArgs] = await Promise.all([
      signed(race.a, 'confirm', { pairingId: race.invite.pairingId }),
      signed(race.b, 'cancel', { pairingId: race.invite.pairingId }),
    ]);
    const [c1, c2] = await Promise.allSettled([
      confirmPairing(db, race.a.accountId, confirmArgs, new Date()),
      cancelPairing(db, race.b.accountId, cancelArgs, new Date()),
    ]);
    const p = await pairingDoc(race.invite.pairingId);
    const paired = await exists(`accountPartners/${race.a.accountId}`);
    if (c1.status === 'fulfilled') {
      assert.equal(p.status, 'accepted');
      assert.equal(paired, true);
      assert.equal(c2.status, 'rejected');
    } else {
      assert.equal(p.status, 'cancelled');
      assert.equal(paired, false);
    }
  });

  test('a stale claim (never confirmed) does not block either person later', async () => {
    const { b } = await claimed();
    const c = await device();
    const at = later(PairingTTL.confirmationMs + 1000);
    const fresh = await create(c, { at });
    const accepted = await accept(b, fresh.token, { at });
    assert.equal(accepted.pairingId, fresh.pairingId);
  });
});

describe('server authority and enumeration resistance', () => {
  test('client-supplied accounts, statuses, IDs and timestamps are ignored', async () => {
    const a = await device();
    const victim = account();
    const forged = {
      inviterAccountId: victim,
      inviteeAccountId: victim,
      status: 'accepted',
      coupleId: 'ff'.repeat(16),
      accounts: [victim, a.accountId],
      createdAt: 0,
      expiresAt: 9e15,
    };
    const invite = await createPairingInvitation(db, a.accountId, { ...(await signed(a, 'create')), ...forged }, new Date());
    const p = await pairingDoc(invite.pairingId);
    assert.equal(p.inviterAccountId, a.accountId);
    assert.equal(p.status, 'pending');
    assert.equal(p.inviteeAccountId, undefined);
    assert.equal(p.coupleId, undefined);
    assert.ok(p.expiresAt.toMillis() <= Date.now() + PairingTTL.invitationMs + 1000);
    assert.equal(await exists(`couples/${'ff'.repeat(16)}`), false);
  });

  test('malformed inputs are rejected before any read', async () => {
    const a = await device();
    for (const bad of [{}, { deviceId: 'x', action: 'create' }, { deviceId: a.hex, action: 'pair' }, { deviceId: a.hex, action: 'accept', token: 'short' }]) {
      await rejectsWith(requestPairingChallenge(db, a.accountId, bad, new Date()), 'invalid_argument');
    }
    await rejectsWith(requestPairingChallenge(db, a.accountId, { deviceId: a.hex, action: 'confirm', pairingId: '../x' }, new Date()), 'invalid_argument');
    await rejectsWith(createPairingInvitation(db, a.accountId, { deviceId: a.hex, challengeId: 'ab'.repeat(16), proof: 'AA==' }, new Date()), 'invalid_argument');
    await rejectsWith(getPairingState(db, 'bad/uid', new Date()), 'invalid_argument');
  });

  test('an account in an open pairing learns nothing about tokens it presents (no non-consuming probe)', async () => {
    const { b, invite } = await claimed();
    const c = await device();
    const live = await create(c);
    const deadInviter = await device();
    const dead = await create(deadInviter);
    await cancel(deadInviter, dead.pairingId);
    const random = Buffer.alloc(16, 0x3c).toString('base64url');
    // A second device of the claimant's own account cannot re-bind the claim either.
    const b2 = await device(b.accountId);
    for (const [who, token] of [
      [b, live.token],
      [b, dead.token],
      [b, random],
      [b2, live.token],
      [b2, invite.token],
    ]) {
      await rejectsWith(accept(who, token), 'pairing_in_progress');
    }
    // Nothing was consumed or rebound.
    const liveDoc = await pairingDoc(live.pairingId);
    assert.equal(liveDoc.status, 'pending');
    assert.equal(typeof liveDoc.tokenHash, 'string');
    const claimedDoc = await pairingDoc(invite.pairingId);
    assert.equal(claimedDoc.inviteeAccountId, b.accountId);
    assert.equal(claimedDoc.inviteeDeviceId, b.hex);
  });

  test('every unusable token looks the same, and failures are rate limited', async () => {
    const a = await device();
    const b = await device();
    const used = await create(a);
    await cancel(a, used.pairingId);
    const random = Buffer.alloc(16, 7).toString('base64url');
    await rejectsWith(accept(b, random), 'invitation_invalid');
    await rejectsWith(accept(b, used.token), 'invitation_invalid');
    // Ten failures per hour, then even the challenge is refused.
    for (let i = 0; i < 8; i++) await rejectsWith(accept(b, Buffer.alloc(16, i + 20).toString('base64url')), 'invitation_invalid');
    await rejectsWith(
      requestPairingChallenge(db, b.accountId, { deviceId: b.hex, action: 'accept', token: random }, new Date()),
      'rate_limited',
    );
  });

  test('invitation creation is rate limited per account', async () => {
    const a = await device();
    for (let i = 0; i < 10; i++) {
      const invite = await create(a);
      await cancel(a, invite.pairingId);
    }
    await rejectsWith(create(a), 'rate_limited');
  });

  test('state reads reveal only the caller\'s own pairing and never tokens or account IDs', async () => {
    const { a, b, invite } = await claimed();
    const stranger = account();
    assert.deepEqual(await getPairingState(db, stranger, new Date()), { state: 'none' });
    await rejectsWith(getPairingState(db, undefined, new Date()), 'unauthenticated');
    for (const d of [a, b]) {
      const text = JSON.stringify(await getPairingState(db, d.accountId, new Date()));
      assert.ok(!text.includes(a.accountId) && !text.includes(b.accountId), 'no account IDs');
      assert.ok(!text.includes(a.hex) && !text.includes(b.hex), 'no device IDs');
      assert.ok(!text.includes(invite.token), 'no token');
    }
  });

  test('the callable surface: pairing steps only, no account lookup, no provisioning callable', () => {
    // Read the compiled entrypoint instead of importing it (importing would
    // initialize the Admin SDK and Functions params as a side effect).
    const source = readFileSync(new URL('../../lib/index.js', import.meta.url), 'utf8');
    const exported = [...source.matchAll(/exports\.(\w+)\s*=/g)].map((m) => m[1]);
    const pairing = [...new Set(exported.filter((name) => /pair|couple/i.test(name)))].sort();
    assert.deepEqual(pairing, [
      'acceptPairingInvitation',
      'cancelPairing',
      'confirmPairing',
      'createPairingInvitation',
      'getPairingState',
      'rejectPairing',
      'requestPairingChallenge',
    ]);
    for (const name of exported) assert.ok(!/lookup|search|find|user|account|provision/i.test(name), `unexpected export ${name}`);
  });

  test('pairing code never logs and never imports the logger', () => {
    const source = readFileSync(new URL('../../src/couple/pairing.ts', import.meta.url), 'utf8');
    assert.ok(!/firebase-functions\/logger|console\./.test(source));
  });
});
