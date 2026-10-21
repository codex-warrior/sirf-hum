// Secure unpairing (Prompt 17C, D-136) against the Firestore emulator.
// Either partner may leave unilaterally, but only from an ACTIVE device: a
// Firebase session or password alone can never end the couple.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { randomBytes } from 'node:crypto';
import process from 'node:process';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import commitModule from '../../lib/conversation/commit.js';
import recoveryModule from '../../lib/conversation/recovery.js';
import pairingModule from '../../lib/couple/pairing.js';
import unpairModule from '../../lib/couple/unpair.js';
import common from '../../lib/device/common.js';
import registration from '../../lib/device/registration.js';
import trust from '../../lib/device/trust.js';
import { keyFromSeed, makeApproval, makeCertificate, makeProof } from '../support.mjs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

const { DeviceError } = common;
const { PairingError } = await import('../../lib/couple/state.js').then((m) => m.default);
const { requestUnpairChallenge, unpairAuthorizationChallenge, unpairCouple } = unpairModule;
const { recoverConversation, recoveryAuthorizationChallenge, requestRecoveryChallenge } = recoveryModule;
const { requestCommitChallenge } = commitModule;
const { acceptPairingInvitation, confirmPairing, createPairingInvitation, getPairingState, requestPairingChallenge } = pairingModule;
const { registerDevice } = registration;
const { approveDevice, proveDeviceEnrollment, requestDeviceApproval } = trust;
const UNPAIR = 8;

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'unpair-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const b64 = (buf) => Buffer.from(buf).toString('base64');
const now = () => new Date();
const hex16 = () => randomBytes(16).toString('hex');

function newDevice() {
  const person = keyFromSeed(randomBytes(32));
  const device = keyFromSeed(randomBytes(32));
  const deviceId = randomBytes(16);
  return { person, device, deviceId, hex: deviceId.toString('hex'), certificate: makeCertificate({ person, device, deviceId }) };
}

async function seedDevice(account, d, status = 'active') {
  await db.doc(`users/${account}/devices/${d.hex}`).set({ schemaVersion: 1, status, certificate: d.certificate });
}

async function couple() {
  n += 1;
  const A = `upA${n}x${Date.now()}`;
  const B = `upB${n}x${Date.now()}`;
  const coupleId = hex16();
  const conversationId = hex16();
  const [A1, A2, B1] = [newDevice(), newDevice(), newDevice()];
  await seedDevice(A, A1);
  await seedDevice(A, A2, 'revoked');
  await seedDevice(B, B1);
  const members = [A, B].sort();
  await db.doc(`couples/${coupleId}`).set({ schemaVersion: 1, members, status: 'active', pairingId: 'p', createdAt: Timestamp.now() });
  await db.doc(`conversations/${conversationId}`).set({
    schemaVersion: 1, protocolVersion: 1, ciphersuite: 1, members, pairingId: 'p', coupleId, state: 'active', epoch: 2, createdAt: Timestamp.now(),
  });
  await db.doc(`accountPartners/${A}`).set({ schemaVersion: 1, partnerAccountId: B, conversationId, coupleId });
  await db.doc(`accountPartners/${B}`).set({ schemaVersion: 1, partnerAccountId: A, conversationId, coupleId });
  for (const acct of [A, B]) await db.doc(`accountTrust/${acct}`).set({ trustEpoch: 1 });
  return { A, B, A1, A2, B1, coupleId, conversationId };
}

async function authorize(account, d, coupleId, { signer = d.device, purpose = UNPAIR } = {}) {
  const c = await requestUnpairChallenge(db, account, { deviceId: d.hex, coupleId }, now());
  const signed = unpairAuthorizationChallenge({
    nonce: Buffer.from(c.challenge, 'base64'),
    accountId: account,
    deviceId: d.deviceId,
    coupleId: Buffer.from(coupleId, 'hex'),
  });
  const { signature } = makeProof({ device: signer, accountId: account, deviceId: d.deviceId, certificate: d.certificate, challenge: signed, purpose });
  return { deviceId: d.hex, coupleId, challengeId: c.challengeId, proof: b64(signature) };
}

const unpair = (account, request, at = now(), list = undefined) => unpairCouple(db, account, request, at, list);

/** Seeds a recovery successor of `from` (as recoverConversation writes it) and points both partners at it. */
async function seedSuccessor(c, from) {
  const next = hex16();
  await db.doc(`conversations/${next}`).set({
    members: [c.A, c.B].sort(), coupleId: c.coupleId, state: 'active', epoch: 0, predecessorId: from,
  });
  await db.doc(`conversations/${from}`).update({ state: 'retired', successorId: next });
  for (const acct of [c.A, c.B]) await db.doc(`accountPartners/${acct}`).update({ conversationId: next });
  return next;
}

async function recoveryRequest(c) {
  const rc = await requestRecoveryChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: 2, trustEpoch: 1 }, now());
  const signed = recoveryAuthorizationChallenge({ nonce: Buffer.from(rc.challenge, 'base64'), accountId: c.A, deviceId: c.A1.deviceId, conversationId: Buffer.from(c.conversationId, 'hex'), epoch: 2, trustEpoch: 1 });
  const { signature } = makeProof({ device: c.A1.device, accountId: c.A, deviceId: c.A1.deviceId, certificate: c.A1.certificate, challenge: signed, purpose: 7 });
  return { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: 2, trustEpoch: 1, challengeId: rc.challengeId, proof: b64(signature) };
}

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof DeviceError || e instanceof PairingError, `expected ${failure}, got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

const exists = async (path) => (await db.doc(path).get()).exists;
const coupleStatus = async (id) => (await db.doc(`couples/${id}`).get()).get('status');
const convState = async (id) => (await db.doc(`conversations/${id}`).get()).get('state');

async function stillPaired(c) {
  assert.equal(await coupleStatus(c.coupleId), 'active');
  assert.equal(await convState(c.conversationId), 'active');
  assert.ok(await exists(`accountPartners/${c.A}`));
  assert.ok(await exists(`accountPartners/${c.B}`));
}

async function dissolved(c) {
  assert.equal(await coupleStatus(c.coupleId), 'dissolved');
  assert.equal(await convState(c.conversationId), 'closed');
  assert.equal(await exists(`accountPartners/${c.A}`), false);
  assert.equal(await exists(`accountPartners/${c.B}`), false);
}

/** A signed pairing step (D-102), for re-pairing and races. */
async function signedStep(account, d, action, extra = {}) {
  const issued = await requestPairingChallenge(db, account, { deviceId: d.hex, action, ...extra }, now());
  const { signature } = makeProof({ device: d.device, accountId: account, deviceId: d.deviceId, certificate: d.certificate, challenge: Buffer.from(issued.challenge, 'base64'), purpose: 4 });
  return { deviceId: d.hex, challengeId: issued.challengeId, proof: b64(signature), ...extra };
}

describe('secure unpairing (D-136)', () => {
  test('either partner leaves from an active device: couple dissolved, conversations closed, partner access gone', async () => {
    const c = await couple();
    // A retired predecessor (an earlier recovery) is closed too.
    const retired = hex16();
    await db.doc(`conversations/${retired}`).set({ members: [c.A, c.B].sort(), coupleId: c.coupleId, state: 'retired', epoch: 9 });
    await unpair(c.B, await authorize(c.B, c.B1, c.coupleId));
    await dissolved(c);
    assert.equal(await convState(retired), 'closed');
    const record = (await db.doc(`couples/${c.coupleId}`).get()).data();
    assert.equal(record.dissolvedByDeviceId, c.B1.hex);
    for (const acct of [c.A, c.B]) assert.deepEqual(await getPairingState(db, acct, now()), { state: 'none' });
    // The devices stay trusted on their own accounts.
    assert.equal((await db.doc(`users/${c.A}/devices/${c.A1.hex}`).get()).get('status'), 'active');
  });

  test('a password-only session, a forged or modified proof, or another purpose cannot unpair', async () => {
    const c = await couple();
    await rejectsWith(unpair(c.A, await authorize(c.A, c.A1, c.coupleId, { signer: keyFromSeed(randomBytes(32)) })), 'proof_invalid');
    const good = await authorize(c.A, c.A1, c.coupleId);
    const flipped = Buffer.from(good.proof, 'base64');
    flipped[3] ^= 1;
    await rejectsWith(unpair(c.A, { ...good, proof: b64(flipped) }), 'proof_invalid');
    await rejectsWith(unpair(c.A, await authorize(c.A, c.A1, c.coupleId, { purpose: 7 })), 'proof_invalid');
    await rejectsWith(unpair(c.A, { deviceId: c.A1.hex, coupleId: c.coupleId }), 'invalid_argument');
    await stillPaired(c);
  });

  test('revoked, pending, unknown and the partner\'s devices cannot unpair for an account', async () => {
    const c = await couple();
    await rejectsWith(requestUnpairChallenge(db, c.A, { deviceId: c.A2.hex, coupleId: c.coupleId }, now()), 'device_not_active');
    const P = newDevice();
    await seedDevice(c.A, P, 'pending');
    await rejectsWith(requestUnpairChallenge(db, c.A, { deviceId: P.hex, coupleId: c.coupleId }, now()), 'device_not_active');
    await rejectsWith(requestUnpairChallenge(db, c.A, { deviceId: newDevice().hex, coupleId: c.coupleId }, now()), 'device_not_found');
    await rejectsWith(requestUnpairChallenge(db, c.A, { deviceId: c.B1.hex, coupleId: c.coupleId }, now()), 'device_not_found');
    const late = await authorize(c.A, c.A1, c.coupleId);
    await db.doc(`users/${c.A}/devices/${c.A1.hex}`).update({ status: 'revoked' });
    await rejectsWith(unpair(c.A, late), 'device_not_active');
    await stillPaired(c);
  });

  test('wrong account, wrong couple, account switch, replay and a stale request are refused', async () => {
    const c = await couple();
    const other = await couple();
    await rejectsWith(requestUnpairChallenge(db, other.A, { deviceId: other.A1.hex, coupleId: c.coupleId }, now()), 'couple_unavailable');
    await rejectsWith(unpair(c.A, { ...(await authorize(c.A, c.A1, c.coupleId)), coupleId: other.coupleId }), 'challenge_invalid');
    const forA = await authorize(c.A, c.A1, c.coupleId);
    await rejectsWith(unpair(c.B, { ...forA, deviceId: c.B1.hex }), 'challenge_invalid');
    await stillPaired(c);
    const request = await authorize(c.A, c.A1, c.coupleId);
    await unpair(c.A, request);
    await rejectsWith(unpair(c.A, request), 'challenge_invalid');
    await rejectsWith(requestUnpairChallenge(db, c.B, { deviceId: c.B1.hex, coupleId: c.coupleId }, now()), 'couple_unavailable');
    await stillPaired(other);
  });

  test('both partners leaving at once: one dissolves it, the other learns it is gone', async () => {
    const c = await couple();
    const [ra, rb] = await Promise.all([authorize(c.A, c.A1, c.coupleId), authorize(c.B, c.B1, c.coupleId)]);
    const results = await Promise.allSettled([unpair(c.A, ra), unpair(c.B, rb)]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    const lost = results.find((r) => r.status === 'rejected').reason;
    assert.equal(lost.failure, 'couple_unavailable', String(lost));
    await dissolved(c);
  });

  test('unpair racing recovery: whatever wins, every conversation of the couple ends closed', async () => {
    const c = await couple();
    const rc = await requestRecoveryChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: 2, trustEpoch: 1 }, now());
    const signed = recoveryAuthorizationChallenge({ nonce: Buffer.from(rc.challenge, 'base64'), accountId: c.A, deviceId: c.A1.deviceId, conversationId: Buffer.from(c.conversationId, 'hex'), epoch: 2, trustEpoch: 1 });
    const { signature } = makeProof({ device: c.A1.device, accountId: c.A, deviceId: c.A1.deviceId, certificate: c.A1.certificate, challenge: signed, purpose: 7 });
    const recovery = { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: 2, trustEpoch: 1, challengeId: rc.challengeId, proof: b64(signature) };
    const u = await authorize(c.B, c.B1, c.coupleId);
    await Promise.allSettled([recoverConversation(db, c.A, recovery, now()), unpair(c.B, u)]);
    // If recovery committed first, unpairing closed its successor as well;
    // if unpairing committed first, recovery found nothing to recover.
    const all = await db.collection('conversations').where('coupleId', '==', c.coupleId).get();
    assert.ok(all.size >= 1);
    for (const doc of all.docs) assert.equal(doc.get('state'), 'closed');
    await dissolved(c);
  });

  // E90 (D-136 concurrency): the ID listing runs outside the transaction,
  // so a conversation created after it (a recovery successor) must still be
  // found through the partner records and the predecessor chain.
  test('E90: a successor created after the listing is still closed', async () => {
    const c = await couple();
    const s1 = await seedSuccessor(c, c.conversationId);
    // A stale listing that only saw the original conversation.
    await unpair(c.A, await authorize(c.A, c.A1, c.coupleId), now(), async () => [c.conversationId]);
    assert.equal(await convState(c.conversationId), 'closed');
    assert.equal(await convState(s1), 'closed');
    await dissolved(c);
  });

  test('E90: conversations missing from the listing are found through the predecessor chain', async () => {
    const c = await couple();
    const s1 = await seedSuccessor(c, c.conversationId);
    const s2 = await seedSuccessor(c, s1);
    // The listing saw nothing at all (worst case): s2 via the partner
    // records, s1 and the original via predecessorId.
    await unpair(c.B, await authorize(c.B, c.B1, c.coupleId), now(), async () => []);
    for (const id of [c.conversationId, s1, s2]) assert.equal(await convState(id), 'closed', id);
    await dissolved(c);
  });

  test('E90: a lineage beyond the walk bound fails closed; nothing changes', async () => {
    const c = await couple();
    let last = c.conversationId;
    for (let i = 0; i < 70; i += 1) last = await seedSuccessor(c, last);
    const request = await authorize(c.A, c.A1, c.coupleId);
    await assert.rejects(unpair(c.A, request, now(), async () => []), /walk bound/);
    assert.equal(await coupleStatus(c.coupleId), 'active');
    assert.equal(await convState(last), 'active');
    assert.ok(await exists(`accountPartners/${c.A}`));
    // With the real listing every conversation is found and closed.
    await unpair(c.A, await authorize(c.A, c.A1, c.coupleId));
    const all = await db.collection('conversations').where('coupleId', '==', c.coupleId).get();
    assert.equal(all.size, 71);
    for (const doc of all.docs) assert.equal(doc.get('state'), 'closed');
  });

  // P3-15 (Prompt 18, D-144): the listing and the lineage walk run only
  // after the challenge, couple membership, device and proof all hold, so
  // an unauthorized caller causes no reads of the couple's conversations
  // and learns nothing about the lineage (no walk-bound signal).
  test('P3-15: no listing or lineage walk before the request is authorized', async () => {
    const c = await couple();
    const other = await couple();
    let listed = 0;
    const spy = async (database, id) => {
      listed += 1;
      return (await database.collection('conversations').where('coupleId', '==', id).select().get()).docs.map((d) => d.id);
    };
    const good = await authorize(c.A, c.A1, c.coupleId);
    const flipped = Buffer.from(good.proof, 'base64');
    flipped[0] ^= 1;
    await rejectsWith(unpair(c.A, { ...good, proof: b64(flipped) }, now(), spy), 'proof_invalid');
    await rejectsWith(unpair(c.A, { ...(await authorize(c.A, c.A1, c.coupleId)), challengeId: hex16() }, now(), spy), 'challenge_invalid');
    await rejectsWith(unpair(c.A, await authorize(c.A, c.A1, c.coupleId, { purpose: 7 }), now(), spy), 'proof_invalid');
    const stale = await authorize(c.A, c.A1, c.coupleId);
    await rejectsWith(unpair(c.A, stale, new Date(Date.now() + 10 * 60 * 1000), spy), 'challenge_expired');
    // Another account presenting this couple, and another couple's member.
    await rejectsWith(unpair(other.A, { ...(await authorize(other.A, other.A1, other.coupleId)), coupleId: c.coupleId }, now(), spy), 'challenge_invalid');
    const late = await authorize(c.A, c.A1, c.coupleId);
    await db.doc(`users/${c.A}/devices/${c.A1.hex}`).update({ status: 'revoked' });
    await rejectsWith(unpair(c.A, late, now(), spy), 'device_not_active');
    await db.doc(`users/${c.A}/devices/${c.A1.hex}`).update({ status: 'active' });
    assert.equal(listed, 0, 'an unauthorized request listed the couple\'s conversations');
    await stillPaired(c);
    // Authorized (B: A has used its 5 unpair challenges for today): the
    // listing runs, once per transaction attempt.
    await unpair(c.B, await authorize(c.B, c.B1, c.coupleId), now(), spy);
    assert.ok(listed >= 1);
    await dissolved(c);
    await stillPaired(other);
  });

  test('P3-15: an over-long lineage answers a forged proof with proof_invalid, not the walk bound', async () => {
    const c = await couple();
    let last = c.conversationId;
    for (let i = 0; i < 70; i += 1) last = await seedSuccessor(c, last);
    const forged = await authorize(c.A, c.A1, c.coupleId, { signer: keyFromSeed(randomBytes(32)) });
    await rejectsWith(unpair(c.A, forged, now(), async () => []), 'proof_invalid');
    // The forged challenge was consumed; a replay is refused the same way.
    await rejectsWith(unpair(c.A, forged, now(), async () => []), 'challenge_invalid');
    assert.equal(await coupleStatus(c.coupleId), 'active');
    assert.equal(await convState(last), 'active');
  });

  test('E90: repeated unpair/recovery races never leave an open conversation', async () => {
    for (let round = 0; round < 4; round += 1) {
      const c = await couple();
      const recovery = await recoveryRequest(c);
      const u = await authorize(c.B, c.B1, c.coupleId);
      const racers = [() => recoverConversation(db, c.A, recovery, now()), () => unpair(c.B, u)];
      if (round % 2 === 1) racers.reverse();
      const results = await Promise.allSettled(racers.map((run) => run()));
      // Unpairing always succeeds (a racing recovery only forces a retry);
      // a losing recovery fails with a category, never a partial state.
      const unpairResult = results[round % 2 === 1 ? 0 : 1];
      assert.equal(unpairResult.status, 'fulfilled', String(unpairResult.reason));
      const recoveryResult = results[round % 2 === 1 ? 1 : 0];
      if (recoveryResult.status === 'rejected') {
        assert.ok(['conversation_changed', 'conversation_unavailable'].includes(recoveryResult.reason.failure), String(recoveryResult.reason));
      }
      const all = await db.collection('conversations').where('coupleId', '==', c.coupleId).get();
      assert.ok(all.size === 1 || all.size === 2);
      for (const doc of all.docs) assert.equal(doc.get('state'), 'closed', `round ${round}`);
      await dissolved(c);
    }
  });

  test('unpair racing pairing: never a second couple while the first is active', async () => {
    const c = await couple();
    const u = await authorize(c.A, c.A1, c.coupleId);
    const invite = await signedStep(c.A, c.A1, 'create');
    const [, created] = await Promise.allSettled([unpair(c.A, u), createPairingInvitation(db, c.A, invite, now())]);
    if (created.status === 'fulfilled') {
      // Only possible once the couple was already dissolved.
      await dissolved(c);
    } else {
      assert.equal(created.reason.failure, 'already_paired');
    }
    await dissolved(c);
  });

  test('unpair racing device approval: both stand; the approval never reaches the dissolved couple', async () => {
    const c = await couple();
    const N = newDevice();
    await registerDevice(db, c.A, { deviceId: N.hex, platform: 'android', certificate: b64(N.certificate) }, now());
    const request = await requestDeviceApproval(db, c.A, { deviceId: N.hex }, now());
    const { signature: enroll } = makeProof({ device: N.device, accountId: c.A, deviceId: N.deviceId, certificate: N.certificate, challenge: Buffer.from(request.challenge, 'base64'), purpose: 2 });
    await proveDeviceEnrollment(db, c.A, { requestId: request.requestId, proof: b64(enroll) }, now());
    const { signature: approval } = makeApproval({ approver: c.A1, newDevice: N, accountId: c.A, challenge: Buffer.from(request.challenge, 'base64'), expiresAtUnix: request.expiresAtUnix });
    const u = await authorize(c.B, c.B1, c.coupleId);
    await Promise.all([
      approveDevice(db, c.A, { requestId: request.requestId, approverDeviceId: c.A1.hex, signature: b64(approval) }, now()),
      unpair(c.B, u),
    ]);
    assert.equal((await db.doc(`users/${c.A}/devices/${N.hex}`).get()).get('status'), 'active');
    await dissolved(c);
    // The new device gets no commit path into the closed conversation.
    await rejectsWith(requestCommitChallenge(db, c.A, { deviceId: N.hex, conversationId: c.conversationId, fromEpoch: 2 }, now()), 'conversation_unavailable');
  });

  test('the removed partner can neither send, approve for the other, nor re-pair without fresh consent', async () => {
    const c = await couple();
    await unpair(c.A, await authorize(c.A, c.A1, c.coupleId));
    // Send: the closed conversation takes no commit (messages: see the rules tests).
    await rejectsWith(requestCommitChallenge(db, c.B, { deviceId: c.B1.hex, conversationId: c.conversationId, fromEpoch: 2 }, now()), 'conversation_unavailable');
    // Approve a device of the other account: impossible, as before.
    const N = newDevice();
    await registerDevice(db, c.A, { deviceId: N.hex, platform: 'android', certificate: b64(N.certificate) }, now());
    const request = await requestDeviceApproval(db, c.A, { deviceId: N.hex }, now());
    const { signature } = makeApproval({ approver: c.B1, newDevice: N, accountId: c.A, challenge: Buffer.from(request.challenge, 'base64'), expiresAtUnix: request.expiresAtUnix });
    await rejectsWith(approveDevice(db, c.B, { requestId: request.requestId, approverDeviceId: c.B1.hex, signature: b64(signature) }, now()), 'request_invalid');
    // Re-pairing needs a NEW invitation, the other's acceptance and the code.
    const invite = await createPairingInvitation(db, c.B, await signedStep(c.B, c.B1, 'create'), now());
    assert.deepEqual(await getPairingState(db, c.A, now()), { state: 'none' }, 'nothing happens without A');
    const accepted = await acceptPairingInvitation(db, c.A, await signedStep(c.A, c.A1, 'accept', { token: invite.token }), now());
    const wrong = accepted.confirmationCode === '000000' ? '111111' : '000000';
    await rejectsWith(confirmPairing(db, c.B, await signedStep(c.B, c.B1, 'confirm', { pairingId: invite.pairingId, confirmationCode: wrong }), now()), 'confirmation_code_invalid');
    const again = await confirmPairing(db, c.B, await signedStep(c.B, c.B1, 'confirm', { pairingId: invite.pairingId, confirmationCode: accepted.confirmationCode }), now());
    // A new couple and a new conversation; the old ones stay ended.
    assert.notEqual(again.coupleId, c.coupleId);
    assert.notEqual(again.conversationId, c.conversationId);
    assert.equal(await coupleStatus(c.coupleId), 'dissolved');
    assert.equal(await convState(c.conversationId), 'closed');
    assert.equal(await convState(again.conversationId), 'active');
  });
});
