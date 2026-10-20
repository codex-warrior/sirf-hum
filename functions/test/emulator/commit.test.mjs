// Device-bound MLS commit authorization (Prompt 17B, D-127; finding P17-05)
// against the Firestore emulator. Before D-127 any Firebase session of a
// member could write commits/{epoch} with filler bytes and stall every
// device; the rules now refuse those writes (firebase/tests) and this
// module is the only writer.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { randomBytes } from 'node:crypto';
import process from 'node:process';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import commitModule from '../../lib/conversation/commit.js';
import common from '../../lib/device/common.js';
import { keyFromSeed, makeCertificate, makeProof } from '../support.mjs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

const { DeviceError } = common;
const { commitAuthorizationChallenge, requestCommitChallenge, submitConversationCommit } = commitModule;
const COMMIT = 5;

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'commit-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const b64 = (buf) => Buffer.from(buf).toString('base64');
const now = () => new Date();

function newDevice() {
  const person = keyFromSeed(randomBytes(32));
  const device = keyFromSeed(randomBytes(32));
  const deviceId = randomBytes(16);
  return { person, device, deviceId, hex: deviceId.toString('hex'), certificate: makeCertificate({ person, device, deviceId }) };
}

async function seedDevice(account, d, status = 'active') {
  await db.doc(`users/${account}/devices/${d.hex}`).set({ schemaVersion: 1, status, certificate: d.certificate });
}

/** A couple with one active device each (A1, B1), a revoked A2, at `epoch`. */
async function couple({ epoch = 1, state = 'active' } = {}) {
  n += 1;
  const A = `cmA${n}x${Date.now()}`;
  const B = `cmB${n}x${Date.now()}`;
  const conversationId = randomBytes(16).toString('hex');
  const [A1, A2, B1] = [newDevice(), newDevice(), newDevice()];
  await seedDevice(A, A1);
  await seedDevice(A, A2, 'revoked');
  await seedDevice(B, B1);
  await db.doc(`conversations/${conversationId}`).set({
    schemaVersion: 1, protocolVersion: 1, ciphersuite: 1, members: [A, B].sort(), pairingId: 'p', state, epoch, createdAt: Timestamp.now(),
  });
  return { A, B, A1, A2, B1, conversationId };
}

const commitBytes = (fill = 7) => Buffer.alloc(600, fill);

/**
 * What a device does: get a challenge, derive the binding, sign it with the
 * device key (purpose 5). `tamper` changes what is submitted after signing.
 */
async function authorize(account, d, conversationId, fromEpoch, { commit = commitBytes(), welcomes = [], signer = d.device, purpose = COMMIT } = {}) {
  const c = await requestCommitChallenge(db, account, { deviceId: d.hex, conversationId, fromEpoch }, now());
  const signed = commitAuthorizationChallenge({
    nonce: Buffer.from(c.challenge, 'base64'),
    accountId: account,
    deviceId: d.deviceId,
    conversationId: Buffer.from(conversationId, 'hex'),
    fromEpoch,
    protocolVersion: 1,
    commit,
    welcomes,
  });
  const { signature } = makeProof({ device: signer, accountId: account, deviceId: d.deviceId, certificate: d.certificate, challenge: signed, purpose });
  return {
    deviceId: d.hex,
    conversationId,
    fromEpoch,
    challengeId: c.challengeId,
    proof: b64(signature),
    commit: b64(commit),
    welcomes: welcomes.map((w) => ({ targetDeviceId: w.targetDeviceId.toString('hex'), welcome: b64(w.welcome) })),
  };
}

const submit = (account, request, at = now()) => submitConversationCommit(db, account, request, at);

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof DeviceError, `expected DeviceError(${failure}), got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

const epochOf = async (cid) => (await db.doc(`conversations/${cid}`).get()).get('epoch');
const commitOf = async (cid, e) => db.doc(`conversations/${cid}/commits/${e}`).get();

describe('device-bound commit authorization (D-127)', () => {
  test('an active member device commits: commit, epoch move and Welcomes land together', async () => {
    const { A, A1, B1, conversationId } = await couple();
    const welcome = { targetDeviceId: B1.deviceId, welcome: Buffer.alloc(900, 3) };
    const result = await submit(A, await authorize(A, A1, conversationId, 1, { welcomes: [welcome] }));
    assert.deepEqual(result, { epoch: 2 });
    assert.equal(await epochOf(conversationId), 2);
    const c = await commitOf(conversationId, 1);
    assert.equal(c.get('senderAccountId'), A);
    assert.equal(c.get('senderDeviceId'), A1.hex);
    assert.deepEqual(Buffer.from(c.get('commit')), commitBytes());
    const w = await db.doc(`conversations/${conversationId}/welcomes/${B1.hex}_1`).get();
    assert.deepEqual(Buffer.from(w.get('welcome')), Buffer.alloc(900, 3));
    assert.equal(w.get('senderDeviceId'), A1.hex);
  });

  test('a password-only session (no device key) cannot commit', async () => {
    const { A, A1, conversationId } = await couple();
    // A real challenge, but no device key: a forged or empty proof.
    const request = await authorize(A, A1, conversationId, 1, { signer: keyFromSeed(randomBytes(32)) });
    await rejectsWith(submit(A, request), 'proof_invalid');
    await rejectsWith(submit(A, { ...request, proof: b64(Buffer.alloc(64)) }), 'challenge_invalid');
    await rejectsWith(submit(A, { ...request, proof: undefined }), 'invalid_argument');
    assert.equal(await epochOf(conversationId), 1);
    assert.equal((await commitOf(conversationId, 1)).exists, false);
  });

  test('wrong device: another device of the account cannot use or sign for the challenge', async () => {
    const { A, A1, conversationId } = await couple();
    const A3 = newDevice();
    await seedDevice(A, A3);
    // A3 presents A1's authorization as its own.
    const forA1 = await authorize(A, A1, conversationId, 1);
    await rejectsWith(submit(A, { ...forA1, deviceId: A3.hex }), 'challenge_invalid');
    // A3's key signing for A1's identity.
    const signedByA3 = await authorize(A, A1, conversationId, 1, { signer: A3.device });
    await rejectsWith(submit(A, signedByA3), 'proof_invalid');
    // The partner's device for A's account.
    const { B, B1 } = await couple();
    await rejectsWith(requestCommitChallenge(db, A, { deviceId: B1.hex, conversationId, fromEpoch: 1 }, now()), 'device_not_found');
    void B;
    assert.equal(await epochOf(conversationId), 1);
  });

  test('revoked, pending and unknown devices cannot commit, including one revoked after its challenge', async () => {
    const { A, A1, A2, conversationId } = await couple();
    await rejectsWith(requestCommitChallenge(db, A, { deviceId: A2.hex, conversationId, fromEpoch: 1 }, now()), 'device_not_active');
    const P = newDevice();
    await seedDevice(A, P, 'pending');
    await rejectsWith(requestCommitChallenge(db, A, { deviceId: P.hex, conversationId, fromEpoch: 1 }, now()), 'device_not_active');
    await rejectsWith(requestCommitChallenge(db, A, { deviceId: newDevice().hex, conversationId, fromEpoch: 1 }, now()), 'device_not_found');
    const request = await authorize(A, A1, conversationId, 1);
    await db.doc(`users/${A}/devices/${A1.hex}`).update({ status: 'revoked' });
    await rejectsWith(submit(A, request), 'device_not_active');
    assert.equal(await epochOf(conversationId), 1);
  });

  test('a modified signature, conversation, epoch, commit or Welcome fails', async () => {
    const { A, A1, B1, conversationId } = await couple();
    const welcomes = [{ targetDeviceId: B1.deviceId, welcome: Buffer.alloc(500, 4) }];
    const flip = (s) => {
      const b = Buffer.from(s, 'base64');
      b[0] ^= 1;
      return b64(b);
    };
    await rejectsWith(submit(A, { ...(await authorize(A, A1, conversationId, 1)), proof: flip((await authorize(A, A1, conversationId, 1)).proof) }), 'proof_invalid');
    const other = (await couple()).conversationId;
    await rejectsWith(submit(A, { ...(await authorize(A, A1, conversationId, 1)), conversationId: other }), 'challenge_invalid');
    await rejectsWith(submit(A, { ...(await authorize(A, A1, conversationId, 1)), fromEpoch: 2 }), 'challenge_invalid');
    await rejectsWith(submit(A, { ...(await authorize(A, A1, conversationId, 1)), commit: b64(commitBytes(8)) }), 'proof_invalid');
    const withWelcome = await authorize(A, A1, conversationId, 1, { welcomes });
    await rejectsWith(submit(A, { ...withWelcome, welcomes: [] }), 'proof_invalid');
    const swapped = await authorize(A, A1, conversationId, 1, { welcomes });
    await rejectsWith(submit(A, { ...swapped, welcomes: [{ targetDeviceId: A1.hex, welcome: swapped.welcomes[0].welcome }] }), 'proof_invalid');
    // A proof for another purpose (e.g. pairing = 4) over the same bytes.
    await rejectsWith(submit(A, await authorize(A, A1, conversationId, 1, { purpose: 4 })), 'proof_invalid');
    assert.equal(await epochOf(conversationId), 1);
  });

  test('replay: an authorization is used once, and a stale epoch is refused', async () => {
    const { A, A1, conversationId } = await couple();
    const request = await authorize(A, A1, conversationId, 1);
    await submit(A, request);
    await rejectsWith(submit(A, request), 'challenge_invalid');
    // Re-authorizing the old epoch after it moved.
    await rejectsWith(requestCommitChallenge(db, A, { deviceId: A1.hex, conversationId, fromEpoch: 1 }, now()), 'commit_conflict');
    // An expired challenge.
    const late = await authorize(A, A1, conversationId, 2);
    await rejectsWith(submit(A, late, new Date(Date.now() + 6 * 60 * 1000)), 'challenge_expired');
    assert.equal(await epochOf(conversationId), 2);
  });

  test('concurrent valid commits: exactly one wins the epoch, the other is a conflict', async () => {
    const { A, B, A1, B1, conversationId } = await couple();
    const [ra, rb] = await Promise.all([
      authorize(A, A1, conversationId, 1, { commit: commitBytes(1) }),
      authorize(B, B1, conversationId, 1, { commit: commitBytes(2) }),
    ]);
    const results = await Promise.allSettled([submit(A, ra), submit(B, rb)]);
    const ok = results.filter((r) => r.status === 'fulfilled');
    assert.equal(ok.length, 1);
    const lost = results.find((r) => r.status === 'rejected');
    assert.equal(lost.reason.failure, 'commit_conflict');
    assert.equal(await epochOf(conversationId), 2);
    const winner = (await commitOf(conversationId, 1)).get('senderDeviceId');
    assert.ok([A1.hex, B1.hex].includes(winner));
  });

  test('wrong account or couple: outsiders, other accounts and closed conversations get one uniform failure', async () => {
    const { A, A1, conversationId } = await couple();
    const outsider = `out${Date.now()}`;
    const X1 = newDevice();
    await seedDevice(outsider, X1);
    await rejectsWith(requestCommitChallenge(db, outsider, { deviceId: X1.hex, conversationId, fromEpoch: 1 }, now()), 'conversation_unavailable');
    await rejectsWith(requestCommitChallenge(db, A, { deviceId: A1.hex, conversationId: randomBytes(16).toString('hex'), fromEpoch: 1 }, now()), 'conversation_unavailable');
    // A challenge issued to account A presented by another session (account switch).
    const request = await authorize(A, A1, conversationId, 1);
    await rejectsWith(submit(outsider, { ...request, deviceId: X1.hex }), 'challenge_invalid');
    await rejectsWith(submit(outsider, request), 'challenge_invalid');
    const closed = await couple({ state: 'closed' });
    await rejectsWith(requestCommitChallenge(db, closed.A, { deviceId: closed.A1.hex, conversationId: closed.conversationId, fromEpoch: 1 }, now()), 'conversation_unavailable');
    assert.equal(await epochOf(conversationId), 1);
  });

  test('malformed and oversized inputs are refused before any write', async () => {
    const { A, A1, B1, conversationId } = await couple();
    const request = await authorize(A, A1, conversationId, 1);
    await rejectsWith(submit(A, { ...request, commit: b64(Buffer.alloc(131073)) }), 'invalid_argument');
    await rejectsWith(submit(A, { ...request, fromEpoch: -1 }), 'invalid_argument');
    await rejectsWith(submit(A, { ...request, conversationId: 'not-hex' }), 'invalid_argument');
    const twice = { targetDeviceId: B1.hex, welcome: b64(Buffer.alloc(10)) };
    await rejectsWith(submit(A, { ...request, welcomes: [twice, twice] }), 'invalid_argument');
    await rejectsWith(submit(A, { ...request, welcomes: Array.from({ length: 16 }, () => ({ targetDeviceId: randomBytes(16).toString('hex'), welcome: b64(Buffer.alloc(10)) })) }), 'invalid_argument');
    // The request was never consumed by those refusals: it still works.
    await submit(A, request);
    assert.equal(await epochOf(conversationId), 2);
  });
});
