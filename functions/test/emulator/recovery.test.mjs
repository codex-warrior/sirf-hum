// Conversation recovery (Prompt 17C, D-135) against the Firestore emulator:
// an active device retires a stalled conversation and re-provisions a new
// MLS group for the same couple. Adversarial cases first.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import process from 'node:process';
import { URL } from 'node:url';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import commitModule from '../../lib/conversation/commit.js';
import recoveryModule from '../../lib/conversation/recovery.js';
import common from '../../lib/device/common.js';
import unpairModule from '../../lib/couple/unpair.js';
import { keyFromSeed, makeCertificate, makeProof } from '../support.mjs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

const { DeviceError } = common;
const { recoverConversation, recoveryAuthorizationChallenge, requestRecoveryChallenge } = recoveryModule;
const { commitAuthorizationChallenge, requestCommitChallenge, submitConversationCommit } = commitModule;
const { requestUnpairChallenge, unpairAuthorizationChallenge, unpairCouple } = unpairModule;
const RECOVERY = 7;

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'recovery-test');
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

/** A paired couple as confirmPairing leaves it, with a stalled epoch. */
async function couple({ epoch = 4, trustEpoch = 3 } = {}) {
  n += 1;
  const A = `rcA${n}x${Date.now()}`;
  const B = `rcB${n}x${Date.now()}`;
  const coupleId = hex16();
  const conversationId = hex16();
  const [A1, A2, B1] = [newDevice(), newDevice(), newDevice()];
  await seedDevice(A, A1);
  await seedDevice(A, A2, 'revoked');
  await seedDevice(B, B1);
  const members = [A, B].sort();
  await db.doc(`couples/${coupleId}`).set({ schemaVersion: 1, members, status: 'active', pairingId: 'p', createdAt: Timestamp.now() });
  await db.doc(`conversations/${conversationId}`).set({
    schemaVersion: 1, protocolVersion: 1, ciphersuite: 1, members, pairingId: 'p', coupleId, state: 'active', epoch, createdAt: Timestamp.now(),
  });
  await db.doc(`accountPartners/${A}`).set({ schemaVersion: 1, partnerAccountId: B, conversationId, coupleId });
  await db.doc(`accountPartners/${B}`).set({ schemaVersion: 1, partnerAccountId: A, conversationId, coupleId });
  for (const acct of [A, B]) await db.doc(`accountTrust/${acct}`).set({ trustEpoch });
  return { A, B, A1, A2, B1, coupleId, conversationId, epoch, trustEpoch };
}

/** What a device does: challenge, binding, signature by its device key. */
async function authorize(account, d, conversationId, { epoch, trustEpoch, signer = d.device, purpose = RECOVERY } = {}) {
  const c = await requestRecoveryChallenge(db, account, { deviceId: d.hex, conversationId, epoch, trustEpoch }, now());
  const signed = recoveryAuthorizationChallenge({
    nonce: Buffer.from(c.challenge, 'base64'),
    accountId: account,
    deviceId: d.deviceId,
    conversationId: Buffer.from(conversationId, 'hex'),
    epoch,
    trustEpoch,
  });
  const { signature } = makeProof({ device: signer, accountId: account, deviceId: d.deviceId, certificate: d.certificate, challenge: signed, purpose });
  return { deviceId: d.hex, conversationId, epoch, trustEpoch, challengeId: c.challengeId, proof: b64(signature) };
}

const recover = (account, request, at = now()) => recoverConversation(db, account, request, at);

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof DeviceError, `expected DeviceError(${failure}), got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

const conv = async (id) => (await db.doc(`conversations/${id}`).get()).data();
const partnerConv = async (acct) => (await db.doc(`accountPartners/${acct}`).get()).get('conversationId');

/** Nothing changed: still the same, active, current conversation. */
async function unchanged(c) {
  assert.equal((await conv(c.conversationId)).state, 'active');
  assert.equal(await partnerConv(c.A), c.conversationId);
  assert.equal(await partnerConv(c.B), c.conversationId);
}

describe('conversation recovery (D-135)', () => {
  test('a trusted device recovers: old retired, a new group for the same couple, and it works', async () => {
    const c = await couple();
    const { conversationId: next } = await recover(c.A, await authorize(c.A, c.A1, c.conversationId, c));
    assert.notEqual(next, c.conversationId);
    const old = await conv(c.conversationId);
    assert.equal(old.state, 'retired');
    assert.equal(old.successorId, next);
    assert.equal(old.retiredByDeviceId, c.A1.hex);
    assert.equal(old.epoch, c.epoch, 'the old epoch is never touched');
    const fresh = await conv(next);
    assert.deepEqual(fresh.members, [c.A, c.B].sort());
    assert.equal(fresh.coupleId, c.coupleId);
    assert.equal(fresh.state, 'active');
    assert.equal(fresh.epoch, 0);
    assert.equal(fresh.generation, 1);
    assert.equal(fresh.predecessorId, c.conversationId);
    assert.equal(await partnerConv(c.A), next);
    assert.equal(await partnerConv(c.B), next);
    // The new conversation takes a normal, device-bound commit (group creation).
    const cc = await requestCommitChallenge(db, c.B, { deviceId: c.B1.hex, conversationId: next, fromEpoch: 0 }, now());
    const commit = Buffer.alloc(300, 9);
    const signed = commitAuthorizationChallenge({
      nonce: Buffer.from(cc.challenge, 'base64'), accountId: c.B, deviceId: c.B1.deviceId, conversationId: Buffer.from(next, 'hex'),
      fromEpoch: 0, protocolVersion: 1, commit, welcomes: [],
    });
    const { signature } = makeProof({ device: c.B1.device, accountId: c.B, deviceId: c.B1.deviceId, certificate: c.B1.certificate, challenge: signed, purpose: 5 });
    await submitConversationCommit(db, c.B, { deviceId: c.B1.hex, conversationId: next, fromEpoch: 0, challengeId: cc.challengeId, proof: b64(signature), commit: b64(commit), welcomes: [] }, now());
    assert.equal((await conv(next)).epoch, 1);
    // The retired conversation accepts nothing new: the old commit path is closed.
    await rejectsWith(requestCommitChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, fromEpoch: c.epoch }, now()), 'conversation_unavailable');
  });

  // Each account may ask for 3 recovery challenges a day (D-135), and a
  // refused request still counts, so these tests spread attempts over
  // accounts and couples.
  test('a password-only session, a forged or modified proof, or another purpose cannot recover', async () => {
    const c = await couple();
    await rejectsWith(recover(c.A, await authorize(c.A, c.A1, c.conversationId, { ...c, signer: keyFromSeed(randomBytes(32)) })), 'proof_invalid');
    const good = await authorize(c.A, c.A1, c.conversationId, c);
    const flipped = Buffer.from(good.proof, 'base64');
    flipped[10] ^= 1;
    await rejectsWith(recover(c.A, { ...good, proof: b64(flipped) }), 'proof_invalid');
    await rejectsWith(recover(c.A, await authorize(c.A, c.A1, c.conversationId, { ...c, purpose: 5 })), 'proof_invalid');
    await rejectsWith(recover(c.B, { ...(await authorize(c.B, c.B1, c.conversationId, c)), proof: undefined }), 'invalid_argument');
    await unchanged(c);
    // The fourth request of the day is refused outright.
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch }, now()), 'rate_limited');
  });

  test('wrong, revoked, pending and unknown devices cannot recover; nor one revoked after its challenge', async () => {
    const c = await couple();
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: c.A2.hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch }, now()), 'device_not_active');
    const P = newDevice();
    await seedDevice(c.A, P, 'pending');
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: P.hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch }, now()), 'device_not_active');
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: newDevice().hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch }, now()), 'device_not_found');
    await unchanged(c);
    // A1's challenge presented as another device, and the partner's key signing for A1.
    const d = await couple();
    const A3 = newDevice();
    await seedDevice(d.A, A3);
    await rejectsWith(recover(d.A, { ...(await authorize(d.A, d.A1, d.conversationId, d)), deviceId: A3.hex }), 'challenge_invalid');
    await rejectsWith(recover(d.A, await authorize(d.A, d.A1, d.conversationId, { ...d, signer: d.B1.device })), 'proof_invalid');
    // Revoked between challenge and recovery.
    const late = await authorize(d.A, d.A1, d.conversationId, d);
    await db.doc(`users/${d.A}/devices/${d.A1.hex}`).update({ status: 'revoked' });
    await rejectsWith(recover(d.A, late), 'device_not_active');
    await unchanged(d);
  });

  test('wrong conversation, wrong account and account switch are refused', async () => {
    const c = await couple();
    const other = await couple();
    // A challenge for one conversation cannot recover another.
    await rejectsWith(recover(c.A, { ...(await authorize(c.A, c.A1, c.conversationId, c)), conversationId: other.conversationId }), 'challenge_invalid');
    // An outsider (not a member), and another account presenting A's authorization.
    await rejectsWith(requestRecoveryChallenge(db, other.A, { deviceId: other.A1.hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch }, now()), 'conversation_unavailable');
    const forA = await authorize(c.A, c.A1, c.conversationId, c);
    await rejectsWith(recover(c.B, forA), 'challenge_invalid');
    await rejectsWith(recover(c.B, { ...forA, deviceId: c.B1.hex }), 'challenge_invalid');
    await unchanged(c);
    await unchanged(other);
  });

  test('a stale view (epoch or trust epoch) is refused, at request and when either moves before recovery', async () => {
    const c = await couple();
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: c.epoch - 1, trustEpoch: c.trustEpoch }, now()), 'conversation_changed');
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch - 1 }, now()), 'conversation_changed');
    // Racing a normal commit: the epoch moves after the challenge.
    const raced = await authorize(c.A, c.A1, c.conversationId, c);
    await db.doc(`conversations/${c.conversationId}`).update({ epoch: c.epoch + 1 });
    await rejectsWith(recover(c.A, raced), 'conversation_changed');
    // Racing a revocation: the account's trust epoch moves after the challenge.
    const c2 = await couple();
    const raced2 = await authorize(c2.A, c2.A1, c2.conversationId, c2);
    await db.doc(`accountTrust/${c2.A}`).update({ trustEpoch: c2.trustEpoch + 1 });
    await rejectsWith(recover(c2.A, raced2), 'conversation_changed');
    await unchanged(c2);
  });

  test('replay: an authorization works once; a retired conversation is never recovered again', async () => {
    const c = await couple();
    const request = await authorize(c.A, c.A1, c.conversationId, c);
    const { conversationId: next } = await recover(c.A, request);
    await rejectsWith(recover(c.A, request), 'challenge_invalid');
    await rejectsWith(requestRecoveryChallenge(db, c.A, { deviceId: c.A1.hex, conversationId: c.conversationId, epoch: c.epoch, trustEpoch: c.trustEpoch }, now()), 'conversation_changed');
    // An expired authorization.
    const late = await authorize(c.B, c.B1, next, { epoch: 0, trustEpoch: c.trustEpoch });
    await rejectsWith(recover(c.B, late, new Date(Date.now() + 6 * 60 * 1000)), 'challenge_expired');
    assert.equal(await partnerConv(c.A), next);
  });

  test('both partners recovering at once: exactly one successor, both records agree', async () => {
    const c = await couple();
    const [ra, rb] = await Promise.all([authorize(c.A, c.A1, c.conversationId, c), authorize(c.B, c.B1, c.conversationId, c)]);
    const results = await Promise.allSettled([recover(c.A, ra), recover(c.B, rb)]);
    const won = results.filter((r) => r.status === 'fulfilled');
    assert.equal(won.length, 1);
    assert.equal(results.find((r) => r.status === 'rejected').reason.failure, 'conversation_changed');
    const next = won[0].value.conversationId;
    assert.equal(await partnerConv(c.A), next);
    assert.equal(await partnerConv(c.B), next);
    assert.equal((await db.collection('conversations').where('coupleId', '==', c.coupleId).get()).size, 2);
  });

  test('a dissolved couple cannot be recovered', async () => {
    const c = await couple();
    const request = await authorize(c.A, c.A1, c.conversationId, c);
    const u = await requestUnpairChallenge(db, c.B, { deviceId: c.B1.hex, coupleId: c.coupleId }, now());
    const signed = unpairAuthorizationChallenge({ nonce: Buffer.from(u.challenge, 'base64'), accountId: c.B, deviceId: c.B1.deviceId, coupleId: Buffer.from(c.coupleId, 'hex') });
    const { signature } = makeProof({ device: c.B1.device, accountId: c.B, deviceId: c.B1.deviceId, certificate: c.B1.certificate, challenge: signed, purpose: 8 });
    await unpairCouple(db, c.B, { deviceId: c.B1.hex, coupleId: c.coupleId, challengeId: u.challengeId, proof: b64(signature) }, now());
    await rejectsWith(recover(c.A, request), 'conversation_changed');
    assert.equal((await conv(c.conversationId)).state, 'closed');
  });

  test('the recovery module never reads, rebuilds or decrypts messages', () => {
    const source = readFileSync(new URL('../../src/conversation/recovery.ts', import.meta.url), 'utf8');
    assert.doesNotMatch(source, /messages|ciphertext|\.data\(\)|logger|console\./);
  });
});
