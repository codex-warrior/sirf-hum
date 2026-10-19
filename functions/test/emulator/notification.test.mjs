// Push token registration and notification fan-out against the Firestore
// emulator (Prompt 11, D-097, D-098). FCM is a recording fake: nothing is
// sent anywhere. Run: npm run test:emulator.
import { Buffer } from 'node:buffer';
import assert from 'node:assert/strict';
import process from 'node:process';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import common from '../../lib/device/common.js';
import proofModule from '../../lib/device/proof.js';
import tokensModule from '../../lib/notification/tokens.js';
import fanoutModule from '../../lib/notification/fanout.js';
import { makeDevice, makeProof } from '../support.mjs';

const { DeviceError } = common;
const { ProofPurpose } = proofModule;
const { requestPushTokenChallenge, registerPushToken } = tokensModule;
const { onMessageCreated, onCommitCreated, onDeviceStatusChanged, STALE_TOKEN_MS } = fanoutModule;

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'notification-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const unique = (p) => `${p}${++n}x${Date.now()}`;
const now = () => new Date();

/** A device with real keys and its server record. */
async function device(accountId, status = 'active') {
  n += 1;
  const id = Buffer.alloc(16);
  id.writeUInt32BE(n, 0);
  id.writeUInt32BE(Date.now() % 0xffffffff, 4);
  id.writeUInt32BE((n * 2654435761) >>> 0, 8);
  const d = makeDevice((n % 200) + 1, ((n * 7) % 200) + 3, id.toString('hex'));
  const hex = d.deviceId.toString('hex');
  await db.doc(`users/${accountId}/devices/${hex}`).set({ schemaVersion: 1, status, certificate: d.certificate });
  return { ...d, hex, accountId };
}

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof DeviceError, `expected ${failure}, got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

/** The full client flow: challenge for this token, sign, register. */
async function register(d, token, { signer = d, purpose = ProofPurpose.pushToken, tamper } = {}) {
  const issued = await requestPushTokenChallenge(db, d.accountId, { deviceId: d.hex, token }, now());
  const { signature } = makeProof({
    device: signer.device,
    accountId: d.accountId,
    deviceId: d.deviceId,
    certificate: d.certificate,
    challenge: Buffer.from(issued.challenge, 'base64'),
    purpose,
  });
  const args = { deviceId: d.hex, challengeId: issued.challengeId, token, proof: signature.toString('base64') };
  await registerPushToken(db, d.accountId, { ...args, ...(tamper ?? {}) }, now());
  return issued;
}

const tokenOf = async (d) => (await db.doc(`pushTokens/${d.hex}`).get()).get('token');

describe('push token registration (D-098)', () => {
  test('an active device registers, rotates and clears its own token', async () => {
    const d = await device(unique('acct'));
    await register(d, 'token-one');
    const doc = (await db.doc(`pushTokens/${d.hex}`).get()).data();
    assert.deepEqual(Object.keys(doc).sort(), ['accountId', 'deviceId', 'token', 'updatedAt']);
    assert.equal(doc.accountId, d.accountId);
    await register(d, 'token-two'); // rotation (onTokenRefresh)
    assert.equal(await tokenOf(d), 'token-two');
    await register(d, null); // logout
    assert.equal((await db.doc(`pushTokens/${d.hex}`).get()).exists, false);
  });

  test('a password alone cannot register a token for a device (proof required)', async () => {
    const account = unique('acct');
    const victim = await device(account);
    const attacker = await device(unique('acct'));
    // Signed by another key (the attacker's), or for another purpose.
    await rejectsWith(register(victim, 'attacker-token', { signer: attacker }), 'proof_invalid');
    await rejectsWith(register(victim, 'attacker-token', { purpose: ProofPurpose.activation }), 'proof_invalid');
    assert.equal(await tokenOf(victim), undefined);
  });

  test('a challenge is bound to one token, one device, one use', async () => {
    const d = await device(unique('acct'));
    // Proof for token A presented with token B.
    await rejectsWith(register(d, 'token-a', { tamper: { token: 'token-b' } }), 'challenge_invalid');
    const issued = await register(d, 'token-a');
    // Replaying the consumed challenge.
    const { signature } = makeProof({
      device: d.device,
      accountId: d.accountId,
      deviceId: d.deviceId,
      certificate: d.certificate,
      challenge: Buffer.from(issued.challenge, 'base64'),
      purpose: ProofPurpose.pushToken,
    });
    await rejectsWith(
      registerPushToken(
        db,
        d.accountId,
        { deviceId: d.hex, challengeId: issued.challengeId, token: 'token-a', proof: signature.toString('base64') },
        now(),
      ),
      'challenge_invalid',
    );
    // Another account cannot use it.
    const other = await device(unique('acct'));
    await rejectsWith(register(other, 'token-c', { tamper: { deviceId: d.hex } }), 'challenge_invalid');
  });

  test('pending, revoked and unknown devices cannot register', async () => {
    const account = unique('acct');
    for (const status of ['pending', 'revoked', 'expired', 'rejected']) {
      const d = await device(account, status);
      await rejectsWith(register(d, 'token'), 'device_not_active');
    }
    await rejectsWith(
      requestPushTokenChallenge(db, account, { deviceId: 'ab'.repeat(16), token: 't' }, now()),
      'device_not_found',
    );
    await rejectsWith(requestPushTokenChallenge(db, undefined, { deviceId: 'ab'.repeat(16), token: 't' }, now()), 'unauthenticated');
  });

  test('a device revoked between challenge and registration is refused', async () => {
    const d = await device(unique('acct'));
    const issued = await requestPushTokenChallenge(db, d.accountId, { deviceId: d.hex, token: 'late' }, now());
    await db.doc(`users/${d.accountId}/devices/${d.hex}`).update({ status: 'revoked' });
    const { signature } = makeProof({
      device: d.device,
      accountId: d.accountId,
      deviceId: d.deviceId,
      certificate: d.certificate,
      challenge: Buffer.from(issued.challenge, 'base64'),
      purpose: ProofPurpose.pushToken,
    });
    await rejectsWith(
      registerPushToken(
        db,
        d.accountId,
        { deviceId: d.hex, challengeId: issued.challengeId, token: 'late', proof: signature.toString('base64') },
        now(),
      ),
      'device_not_active',
    );
  });

  test('one token maps to one device: an account switch on one install moves it', async () => {
    const a = await device(unique('acctA'));
    const b = await device(unique('acctB'));
    await register(a, 'shared-install-token');
    await register(b, 'shared-install-token');
    assert.equal(await tokenOf(a), undefined, "A's wake-ups never reach B's session");
    assert.equal(await tokenOf(b), 'shared-install-token');
  });
});

// ----------------------------------------------------------- fan-out

/** Records what would go to FCM; answers per token. */
function fakeFcm(answers = {}) {
  const sent = [];
  const send = async (messages) => {
    sent.push(...messages);
    return messages.map((m) => answers[m.token] ?? 'ok');
  };
  return { sent, send };
}

async function couple() {
  const [A, B] = [unique('acctA'), unique('acctB')];
  const c = unique('c').padEnd(32, '0').slice(0, 32);
  await db.doc(`conversations/${c}`).set({ members: [A, B], state: 'active', epoch: 1 });
  await db.doc(`accountPartners/${A}`).set({ partnerAccountId: B, conversationId: c });
  await db.doc(`accountPartners/${B}`).set({ partnerAccountId: A, conversationId: c });
  const a1 = await device(A);
  const a2 = await device(A);
  const b1 = await device(B);
  const b2 = await device(B);
  for (const d of [a1, a2, b1, b2]) {
    await db.doc(`pushTokens/${d.hex}`).set({ accountId: d.accountId, deviceId: d.hex, token: `tok-${d.hex}`, updatedAt: Timestamp.now() });
  }
  return { A, B, c, a1, a2, b1, b2 };
}

const byToken = (sent) => Object.fromEntries(sent.map((m) => [m.token, m.data.k]));

describe('fan-out (D-097)', () => {
  test('a message: the partner sees a generic notification, own devices sync, the sender nothing', async () => {
    const { A, c, a1, a2, b1, b2 } = await couple();
    const fcm = fakeFcm();
    const r = await onMessageCreated(db, fcm.send, c, A, a1.hex, now());
    assert.deepEqual(byToken(fcm.sent), { [`tok-${a2.hex}`]: 's', [`tok-${b1.hex}`]: 'm', [`tok-${b2.hex}`]: 'm' });
    assert.deepEqual(r, { kind: 'message', sent: 3, failed: 0, removed: 0 });
    // Nothing but the token identifies anything.
    for (const m of fcm.sent) {
      const rest = JSON.stringify({ ...m, token: undefined });
      for (const id of [c, a1.hex, a2.hex, b1.hex, b2.hex, A]) assert.ok(!rest.includes(id), 'identifier in payload');
    }
  });

  test('revoked, pending and stale devices are never targeted; dead tokens are removed', async () => {
    const { A, c, a1, a2, b1, b2 } = await couple();
    await db.doc(`users/${b2.accountId}/devices/${b2.hex}`).update({ status: 'revoked' });
    await db.doc(`users/${a2.accountId}/devices/${a2.hex}`).update({ status: 'pending' });
    await db.doc(`pushTokens/${b1.hex}`).update({ updatedAt: Timestamp.fromMillis(Date.now() - STALE_TOKEN_MS - 1000) });
    const fcm = fakeFcm();
    const r = await onMessageCreated(db, fcm.send, c, A, a1.hex, now());
    assert.equal(fcm.sent.length, 0);
    assert.equal(r.removed, 1, 'the stale token');
    assert.equal((await db.doc(`pushTokens/${b1.hex}`).get()).exists, false);

    // FCM says a token is no longer registered (uninstall / reinstall).
    await db.doc(`users/${b2.accountId}/devices/${b2.hex}`).update({ status: 'active' });
    const fcm2 = fakeFcm({ [`tok-${b2.hex}`]: 'unregistered' });
    const r2 = await onMessageCreated(db, fcm2.send, c, A, a1.hex, now());
    assert.deepEqual(r2, { kind: 'message', sent: 0, failed: 1, removed: 1 });
    assert.equal((await db.doc(`pushTokens/${b2.hex}`).get()).exists, false);
  });

  test('a token document claiming another account is never used', async () => {
    const { A, c, a1, b1 } = await couple();
    await db.doc(`pushTokens/${b1.hex}`).update({ accountId: A });
    const fcm = fakeFcm();
    await onMessageCreated(db, fcm.send, c, A, a1.hex, now());
    assert.ok(!fcm.sent.some((m) => m.token === `tok-${b1.hex}`));
  });

  test('a commit wakes every other active device silently', async () => {
    const { c, a1, a2, b1, b2 } = await couple();
    const fcm = fakeFcm();
    await onCommitCreated(db, fcm.send, c, b1.hex, now());
    assert.deepEqual(byToken(fcm.sent), { [`tok-${a1.hex}`]: 's', [`tok-${a2.hex}`]: 's', [`tok-${b2.hex}`]: 's' });
    assert.ok(fcm.sent.every((m) => m.android.notification === undefined && m.android.priority === 'normal'));
  });

  test('revocation deletes the token at once and wakes the rest of both accounts', async () => {
    const { A, a1, a2, b1, b2 } = await couple();
    await db.doc(`users/${A}/devices/${a2.hex}`).update({ status: 'revoked' });
    const fcm = fakeFcm();
    const r = await onDeviceStatusChanged(db, fcm.send, A, a2.hex, 'active', 'revoked', now());
    assert.equal((await db.doc(`pushTokens/${a2.hex}`).get()).exists, false);
    assert.deepEqual(byToken(fcm.sent), { [`tok-${a1.hex}`]: 's', [`tok-${b1.hex}`]: 's', [`tok-${b2.hex}`]: 's' });
    assert.equal(r.removed, 1);
  });

  test('identity reset: every revoked device loses its token', async () => {
    const { A, a1, a2 } = await couple();
    for (const d of [a1, a2]) {
      await db.doc(`users/${A}/devices/${d.hex}`).update({ status: 'revoked' });
      await onDeviceStatusChanged(db, fakeFcm().send, A, d.hex, 'active', 'revoked', now());
    }
    for (const d of [a1, a2]) assert.equal((await db.doc(`pushTokens/${d.hex}`).get()).exists, false);
  });

  test('other status changes: no wake-ups; activation keeps tokens', async () => {
    const { A, a1 } = await couple();
    const fcm = fakeFcm();
    assert.deepEqual(await onDeviceStatusChanged(db, fcm.send, A, a1.hex, 'pending', 'active', now()), {
      kind: 'none',
      sent: 0,
      failed: 0,
      removed: 0,
    });
    assert.equal(await tokenOf(a1), `tok-${a1.hex}`);
    const expired = await onDeviceStatusChanged(db, fcm.send, A, a1.hex, 'pending', 'expired', now());
    assert.equal(expired.sent, 0);
    assert.equal(fcm.sent.length, 0);
    assert.equal((await db.doc(`pushTokens/${a1.hex}`).get()).exists, false);
  });

  test('a conversation without tokens sends nothing and fails nothing', async () => {
    const c = unique('c').padEnd(32, '0').slice(0, 32);
    await db.doc(`conversations/${c}`).set({ members: [unique('x'), unique('y')], state: 'active', epoch: 1 });
    const fcm = fakeFcm();
    assert.deepEqual(await onMessageCreated(db, fcm.send, c, 'x', 'ab'.repeat(16), now()), {
      kind: 'message',
      sent: 0,
      failed: 0,
      removed: 0,
    });
  });
});
