// Multi-device trust against the Firestore emulator (Prompt 08 §13, §24):
// approval, chains, revocation, offline devices, stale approvals, recovery,
// copied metadata/state, rate limits and expiry.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { randomBytes } from 'node:crypto';
import process from 'node:process';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import cleanupModule from '../../lib/device/cleanup.js';
import common from '../../lib/device/common.js';
import registration from '../../lib/device/registration.js';
import trust from '../../lib/device/trust.js';
import { keyFromSeed, makeApproval, makeCertificate, makeProof, makeRecoveryApproval, makeRecoveryRegistration } from '../support.mjs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

const { DeviceError, TTL } = common;
const { activateDevice, issueDeviceChallenge, registerDevice } = registration;
const { approveDevice, listDeviceApprovalRequests, proveDeviceEnrollment, recoverDevice, registerRecoveryKey, rejectDeviceApproval, requestDeviceApproval } = trust;
const { cleanupExpired } = cleanupModule;

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'multi-device-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const account = () => `md${++n}x${Date.now()}`;
const now = () => new Date();
const b64 = (buf) => Buffer.from(buf).toString('base64');

/** A device with its OWN fresh PIK and device key (D-074). */
function newDevice() {
  const person = keyFromSeed(randomBytes(32));
  const device = keyFromSeed(randomBytes(32));
  const deviceId = randomBytes(16);
  return { person, device, deviceId, hex: deviceId.toString('hex'), certificate: makeCertificate({ person, device, deviceId }) };
}

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof DeviceError, `expected DeviceError(${failure}), got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

const statusOf = async (acct, d) => (await db.doc(`users/${acct}/devices/${d.hex}`).get()).get('status');
const recordOf = async (acct, d) => (await db.doc(`users/${acct}/devices/${d.hex}`).get()).data();

const register = (acct, d, platform = 'android') =>
  registerDevice(db, acct, { deviceId: d.hex, platform, certificate: b64(d.certificate) }, now());

/** First device of an account: proof of possession only. */
async function bootstrap(acct, d) {
  await register(acct, d);
  const c = await issueDeviceChallenge(db, acct, { deviceId: d.hex, purpose: 'activation' }, now());
  const { signature } = makeProof({ device: d.device, accountId: acct, deviceId: d.deviceId, certificate: d.certificate, challenge: Buffer.from(c.challenge, 'base64') });
  await activateDevice(db, acct, { deviceId: d.hex, challengeId: c.challengeId, proof: b64(signature) }, now());
}

/** New device: register, open request, prove possession (purpose enrollment). */
async function enroll(acct, d, { prove = true, alreadyRegistered = false } = {}) {
  if (!alreadyRegistered) await register(acct, d);
  const request = await requestDeviceApproval(db, acct, { deviceId: d.hex }, now());
  if (prove) {
    const { signature } = makeProof({ device: d.device, accountId: acct, deviceId: d.deviceId, certificate: d.certificate, challenge: Buffer.from(request.challenge, 'base64'), purpose: 2 });
    await proveDeviceEnrollment(db, acct, { requestId: request.requestId, proof: b64(signature) }, now());
  }
  return request;
}

function approvalSignature(acct, approver, d, request, overrides = {}) {
  const { signature } = makeApproval({
    approver, newDevice: d, accountId: overrides.accountId ?? acct,
    challenge: Buffer.from(request.challenge, 'base64'), expiresAtUnix: overrides.expiresAtUnix ?? request.expiresAtUnix,
    signer: overrides.signer,
  });
  return b64(signature);
}

const approve = (acct, approver, request, signature, at = now()) =>
  approveDevice(db, acct, { requestId: request.requestId, approverDeviceId: approver.hex, signature }, at);

async function approveNew(acct, approver, d) {
  const request = await enroll(acct, d);
  await approve(acct, approver, request, approvalSignature(acct, approver, d, request));
  return request;
}

/** Setup only: puts a device into `revoked` directly. The real, signed path (D-081) is tested in hardening.test.mjs. */
const revoke = (acct, d) => db.doc(`users/${acct}/devices/${d.hex}`).update({ status: 'revoked', revokedAt: Timestamp.now(), revokedReason: 'user_removed' });

async function registerRecovery(acct, registrar, recovery) {
  const c = await issueDeviceChallenge(db, acct, { deviceId: registrar.hex, purpose: 'recovery_registration' }, now());
  const { signature } = makeRecoveryRegistration({ registrar, recovery, accountId: acct, challenge: Buffer.from(c.challenge, 'base64'), expiresAtUnix: c.expiresAtUnix });
  await registerRecoveryKey(db, acct, { deviceId: registrar.hex, challengeId: c.challengeId, recoveryPublicKey: b64(recovery.publicKey), signature: b64(signature) }, now());
  return c;
}

function recoverySignature(acct, recovery, d, request) {
  const { signature } = makeRecoveryApproval({ recovery, newDevice: d, accountId: acct, challenge: Buffer.from(request.challenge, 'base64'), expiresAtUnix: request.expiresAtUnix });
  return b64(signature);
}

describe('enrollment and approval', () => {
  test('A approves B: B becomes active, approved by A; Firebase auth alone never did it', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await register(acct, B);
    // Proof of possession alone no longer activates a second device.
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'activation' }, now()), 'approval_required');
    const request = await enroll(acct, B, { alreadyRegistered: true });
    const listed = await listDeviceApprovalRequests(db, acct, now());
    assert.equal(listed.length, 1);
    assert.equal(listed[0].deviceId, B.hex);
    await approve(acct, A, request, approvalSignature(acct, A, B, request));
    const record = await recordOf(acct, B);
    assert.equal(record.status, 'active');
    assert.equal(record.activationMethod, 'approval');
    assert.equal(record.approvedBy, A.hex);
    assert.equal(record.expiresAt, undefined);
  });

  test('chain: A approves B, B approves C; revoking B leaves C valid; revoked B cannot approve', async () => {
    const acct = account();
    const [A, B, C, D] = [newDevice(), newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await approveNew(acct, B, C);
    assert.equal(await statusOf(acct, C), 'active');
    await revoke(acct, B);
    assert.equal(await statusOf(acct, C), 'active', 'past approvals stand (no cascade)');
    const request = await enroll(acct, D);
    await rejectsWith(approve(acct, B, request, approvalSignature(acct, B, D, request)), 'approver_not_trusted');
    assert.equal(await statusOf(acct, D), 'pending');
  });

  test('A approves B, A revokes B: B can never reactivate or re-register', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await revoke(acct, B);
    await rejectsWith(requestDeviceApproval(db, acct, { deviceId: B.hex }, now()), 'device_not_pending');
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'activation' }, now()), 'device_not_pending');
    await rejectsWith(register(acct, B), 'duplicate_device');
  });

  test('A lost, B the only trusted device: B approves C', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await revoke(acct, A);
    await approveNew(acct, B, C);
    assert.equal(await statusOf(acct, C), 'active');
  });

  test('unproven request is neither listed nor approvable', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B, { prove: false });
    assert.equal((await listDeviceApprovalRequests(db, acct, now())).length, 0);
    await rejectsWith(approve(acct, A, request, approvalSignature(acct, A, B, request)), 'request_invalid');
  });

  test('enrollment proof with the wrong key fails and closes the request', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B, { prove: false });
    const { signature } = makeProof({ device: keyFromSeed(randomBytes(32)), accountId: acct, deviceId: B.deviceId, certificate: B.certificate, challenge: Buffer.from(request.challenge, 'base64'), purpose: 2 });
    await rejectsWith(proveDeviceEnrollment(db, acct, { requestId: request.requestId, proof: b64(signature) }, now()), 'proof_invalid');
    await rejectsWith(proveDeviceEnrollment(db, acct, { requestId: request.requestId, proof: b64(signature) }, now()), 'request_invalid');
  });

  test('an activation proof (purpose 1) is not an enrollment proof (purpose 2)', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B, { prove: false });
    const { signature } = makeProof({ device: B.device, accountId: acct, deviceId: B.deviceId, certificate: B.certificate, challenge: Buffer.from(request.challenge, 'base64'), purpose: 1 });
    await rejectsWith(proveDeviceEnrollment(db, acct, { requestId: request.requestId, proof: b64(signature) }, now()), 'proof_invalid');
  });

  test('rejection is terminal for the device', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B);
    await rejectDeviceApproval(db, acct, { requestId: request.requestId }, now());
    assert.equal(await statusOf(acct, B), 'rejected');
    await rejectsWith(requestDeviceApproval(db, acct, { deviceId: B.hex }, now()), 'device_not_pending');
    await rejectsWith(approve(acct, A, request, approvalSignature(acct, A, B, request)), 'request_invalid');
  });
});

describe('stale and forged approvals (§13)', () => {
  async function setup() {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B);
    return { acct, A, B, request };
  }

  test('expired approval', async () => {
    const { acct, A, B, request } = await setup();
    const late = new Date(Date.now() + TTL.approvalRequestMs + 1000);
    await rejectsWith(approve(acct, A, request, approvalSignature(acct, A, B, request), late), 'request_expired');
  });

  test('already-consumed (replayed / duplicated) approval', async () => {
    const { acct, A, B, request } = await setup();
    const signature = approvalSignature(acct, A, B, request);
    await approve(acct, A, request, signature);
    await rejectsWith(approve(acct, A, request, signature), 'request_invalid');
  });

  test('approval created before the approver was revoked, submitted after', async () => {
    const { acct, A, B, request } = await setup();
    const signature = approvalSignature(acct, A, B, request);
    await revoke(acct, A); // A was offline when another device revoked it
    await rejectsWith(approve(acct, A, request, signature), 'approver_not_trusted');
    assert.equal(await statusOf(acct, B), 'pending');
  });

  test('approval after the target device was revoked', async () => {
    const { acct, A, B, request } = await setup();
    await revoke(acct, B);
    await rejectsWith(approve(acct, A, request, approvalSignature(acct, A, B, request)), 'device_not_pending');
  });

  test('altered approval, wrong expiry, wrong signer', async () => {
    for (const make of [
      ({ acct, A, B, request }) => {
        const s = Buffer.from(approvalSignature(acct, A, B, request), 'base64');
        s[3] ^= 1;
        return b64(s);
      },
      ({ acct, A, B, request }) => approvalSignature(acct, A, B, request, { expiresAtUnix: request.expiresAtUnix + 60 }),
      ({ acct, A, B, request }) => approvalSignature(acct, A, B, request, { signer: A.device }),
    ]) {
      const ctx = await setup();
      await rejectsWith(approve(ctx.acct, ctx.A, ctx.request, make(ctx)), 'approval_invalid');
      assert.equal(await statusOf(ctx.acct, ctx.B), 'pending');
    }
  });

  test('wrong account: an approval signed for another account', async () => {
    const { acct, A, B, request } = await setup();
    await rejectsWith(approve(acct, A, request, approvalSignature(acct, A, B, request, { accountId: 'someoneElse' })), 'approval_invalid');
  });

  test('wrong device: an approval for D replayed onto C\'s request', async () => {
    const acct = account();
    const [A, C, D] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    const requestC = await enroll(acct, C);
    await rejectsWith(approve(acct, A, requestC, approvalSignature(acct, A, D, requestC)), 'approval_invalid');
  });

  test('cross-account: another account cannot approve, list or reject', async () => {
    const { acct, B, request } = await setup();
    const attacker = account();
    const X = newDevice();
    await bootstrap(attacker, X);
    await rejectsWith(approve(attacker, X, request, approvalSignature(attacker, X, B, request)), 'request_invalid');
    assert.equal((await listDeviceApprovalRequests(db, attacker, now())).length, 0);
    await rejectsWith(rejectDeviceApproval(db, attacker, { requestId: request.requestId }, now()), 'request_invalid');
    assert.equal(await statusOf(acct, B), 'pending');
  });
});

describe('offline and stale devices (§12)', () => {
  test('A offline, B revokes A, A reconnects: server status is authoritative', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const request = await enroll(acct, C);
    const signedWhileOffline = approvalSignature(acct, A, C, request);
    await revoke(acct, A); // B (or the owner) revokes A while A is offline
    // A reconnects: it reads its own status...
    assert.equal(await statusOf(acct, A), 'revoked');
    // ...and nothing it signed offline creates trust.
    await rejectsWith(approve(acct, A, request, signedWhileOffline), 'approver_not_trusted');
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now()), 'approver_not_trusted');
  });

  test('copied stale local state (same keys) cannot come back', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await revoke(acct, A);
    // An attacker restores A's old app state elsewhere: same keys, same ID.
    await rejectsWith(register(acct, A), 'duplicate_device');
    const other = account();
    await rejectsWith(register(other, A), 'duplicate_device');
  });

  test('attacker copies server metadata (another device\'s certificate)', async () => {
    const victim = account();
    const attacker = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(victim, A);
    await register(victim, B); // pending, not yet indexed
    // Copying an ACTIVE device's certificate: rejected outright.
    await rejectsWith(register(attacker, A), 'duplicate_device');
    // Copying a PENDING one: the record can be filed, but never proven.
    await register(attacker, B);
    const c = await issueDeviceChallenge(db, attacker, { deviceId: B.hex, purpose: 'activation' }, now());
    const { signature } = makeProof({ device: keyFromSeed(randomBytes(32)), accountId: attacker, deviceId: B.deviceId, certificate: B.certificate, challenge: Buffer.from(c.challenge, 'base64') });
    await rejectsWith(activateDevice(db, attacker, { deviceId: B.hex, challengeId: c.challengeId, proof: b64(signature) }, now()), 'proof_invalid');
  });

  test('a forged certificate is refused at registration', async () => {
    const acct = account();
    const d = newDevice();
    const bad = Buffer.from(d.certificate);
    bad[45] ^= 1;
    await rejectsWith(registerDevice(db, acct, { deviceId: d.hex, platform: 'ios', certificate: b64(bad) }, now()), 'certificate_invalid');
    const other = newDevice();
    await rejectsWith(registerDevice(db, acct, { deviceId: other.hex, platform: 'ios', certificate: b64(d.certificate) }, now()), 'certificate_invalid');
  });
});

describe('recovery (§14–16)', () => {
  test('all devices lost, recovery key registered: recovery activates a new device once', async () => {
    const acct = account();
    const [A, B, C, D] = [newDevice(), newDevice(), newDevice(), newDevice()];
    const recovery = keyFromSeed(randomBytes(32));
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await registerRecovery(acct, A, recovery);
    await revoke(acct, A);
    await revoke(acct, B);
    const request = await enroll(acct, C);
    await recoverDevice(db, acct, { requestId: request.requestId, signature: recoverySignature(acct, recovery, C, request) }, now());
    const record = await recordOf(acct, C);
    assert.equal(record.status, 'active');
    assert.equal(record.activationMethod, 'recovery');
    // Single-use: the key is gone after use.
    const next = await enroll(acct, D);
    await rejectsWith(recoverDevice(db, acct, { requestId: next.requestId, signature: recoverySignature(acct, recovery, D, next) }, now()), 'recovery_unavailable');
  });

  test('all devices lost and no recovery key: no way back (and no re-bootstrap)', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await revoke(acct, A);
    await revoke(acct, B);
    await register(acct, C);
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: C.hex, purpose: 'activation' }, now()), 'approval_required');
    const request = await enroll(acct, C, { alreadyRegistered: true });
    await rejectsWith(recoverDevice(db, acct, { requestId: request.requestId, signature: b64(Buffer.alloc(64, 1)) }, now()), 'recovery_unavailable');
    assert.equal(await statusOf(acct, C), 'pending');
  });

  test('wrong recovery key fails and closes the request', async () => {
    const acct = account();
    const [A, C] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await registerRecovery(acct, A, keyFromSeed(randomBytes(32)));
    const request = await enroll(acct, C);
    const wrong = keyFromSeed(randomBytes(32));
    await rejectsWith(recoverDevice(db, acct, { requestId: request.requestId, signature: recoverySignature(acct, wrong, C, request) }, now()), 'recovery_invalid');
    await rejectsWith(recoverDevice(db, acct, { requestId: request.requestId, signature: recoverySignature(acct, wrong, C, request) }, now()), 'request_invalid');
  });

  test('a revoked device cannot register a recovery key; a challenge is single-use', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    const recovery = keyFromSeed(randomBytes(32));
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now());
    const { signature } = makeRecoveryRegistration({ registrar: A, recovery, accountId: acct, challenge: Buffer.from(c.challenge, 'base64'), expiresAtUnix: c.expiresAtUnix });
    const args = { deviceId: A.hex, challengeId: c.challengeId, recoveryPublicKey: b64(recovery.publicKey), signature: b64(signature) };
    await revoke(acct, A);
    await rejectsWith(registerRecoveryKey(db, acct, args, now()), 'approver_not_trusted');
    // Replayed challenge (already consumed by the attempt above).
    await rejectsWith(registerRecoveryKey(db, acct, args, now()), 'challenge_invalid');
    // B (still trusted) can.
    await registerRecovery(acct, B, recovery);
  });
});

describe('rate limits, caps and expiry (§18–19)', () => {
  test('pending devices are capped per account', async () => {
    const acct = account();
    for (let i = 0; i < 3; i++) await register(acct, newDevice());
    await rejectsWith(register(acct, newDevice()), 'too_many_pending');
  });

  test('registration is rate-limited per account (and only that account)', async () => {
    const acct = account();
    for (let i = 0; i < 3; i++) await register(acct, newDevice());
    // Expire them so the pending cap does not interfere.
    const pending = await db.collection(`users/${acct}/devices`).get();
    await Promise.all(pending.docs.map((d) => d.ref.update({ status: 'expired' })));
    await register(acct, newDevice());
    await register(acct, newDevice());
    await rejectsWith(register(acct, newDevice()), 'rate_limited');
    await register(account(), newDevice()); // other accounts unaffected
  });

  test('repeated failed approvals exhaust the failure budget, even for a valid one', async () => {
    const acct = account();
    const [A, B, T] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    const valid = await enroll(acct, B); // request 1 of 5 this hour
    await register(acct, T);
    // Four failed approvals on one target (requests 2–5)...
    for (let i = 0; i < 4; i++) {
      const request = await enroll(acct, T, { alreadyRegistered: true });
      await rejectsWith(approve(acct, A, request, b64(Buffer.alloc(64, 7))), 'approval_invalid');
    }
    // ...and a fifth failure of another kind (forged recovery registration).
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now());
    await rejectsWith(
      registerRecoveryKey(db, acct, { deviceId: A.hex, challengeId: c.challengeId, recoveryPublicKey: b64(Buffer.alloc(32, 1)), signature: b64(Buffer.alloc(64, 2)) }, now()),
      'approval_invalid',
    );
    // The budget is spent: even a valid approval is refused for this window.
    await rejectsWith(approve(acct, A, valid, approvalSignature(acct, A, B, valid)), 'rate_limited');
    assert.equal(await statusOf(acct, B), 'pending');
  });

  test('stale pending devices expire lazily and by cleanup; active ones never', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await register(acct, B);
    await register(acct, C);
    const past = Timestamp.fromMillis(Date.now() - 1000);
    await db.doc(`users/${acct}/devices/${B.hex}`).update({ expiresAt: past });
    await db.doc(`users/${acct}/devices/${C.hex}`).update({ expiresAt: past });
    // Lazy: any operation on an expired record expires it.
    await rejectsWith(requestDeviceApproval(db, acct, { deviceId: B.hex }, now()), 'device_expired');
    assert.equal(await statusOf(acct, B), 'expired');
    // Cleanup: the other one; the active device is untouched; idempotent.
    const first = await cleanupExpired(db, now());
    assert.ok(first.expiredDevices >= 1);
    assert.equal(await statusOf(acct, C), 'expired');
    assert.equal(await statusOf(acct, A), 'active');
    const again = await cleanupExpired(db, now());
    assert.equal(again.expiredDevices, 0);
  });

  test('cleanup deletes expired challenges and requests only', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const live = await enroll(acct, B);
    const stale = db.collection('deviceApprovalRequests').doc();
    await stale.set({ accountId: acct, deviceId: B.hex, status: 'open', challenge: randomBytes(32), expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    await cleanupExpired(db, now());
    assert.equal((await stale.get()).exists, false);
    assert.equal((await db.doc(`deviceApprovalRequests/${live.requestId}`).get()).exists, true);
  });
});
