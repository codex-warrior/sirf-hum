// Prompt 09 against the Firestore emulator: signed revocation (D-081),
// identity reset (D-082), trust epoch (D-083), stored lineage evidence
// (D-084), state-machine edges, concurrency races and rate-limit boundaries.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { randomBytes } from 'node:crypto';
import process from 'node:process';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import common from '../../lib/device/common.js';
import rateLimit from '../../lib/device/rateLimit.js';
import registration from '../../lib/device/registration.js';
import reset from '../../lib/device/reset.js';
import revocationModule from '../../lib/device/revocation.js';
import statements from '../../lib/device/statements.js';
import trust from '../../lib/device/trust.js';
import { keyFromSeed, makeApproval, makeCertificate, makeProof, makeRecoveryApproval, makeRecoveryRegistration, makeResetCancel, makeRevocation } from '../support.mjs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

const { DeviceError, TTL } = common;
const { LIMITS } = rateLimit;
const { activateDevice, issueDeviceChallenge, registerDevice } = registration;
const { cancelIdentityReset, completeIdentityReset, requestIdentityReset } = reset;
const { revokeDevice } = revocationModule;
const { verifyApproval, verifyRecoveryApproval, verifyRecoveryRegistration, verifyRevocation } = statements;
const { approveDevice, proveDeviceEnrollment, recoverDevice, registerRecoveryKey, rejectDeviceApproval, requestDeviceApproval } = trust;

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'hardening-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const account = () => `hd${++n}x${Date.now()}`;
const now = () => new Date();
const b64 = (buf) => Buffer.from(buf).toString('base64');
const fromB64 = (s) => Buffer.from(s, 'base64');

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

const record = async (acct, d) => (await db.doc(`users/${acct}/devices/${d.hex}`).get()).data();
const trustOf = async (acct) => (await db.doc(`accountTrust/${acct}`).get()).data();
const register = (acct, d) => registerDevice(db, acct, { deviceId: d.hex, platform: 'android', certificate: b64(d.certificate) }, now());

async function bootstrap(acct, d) {
  await register(acct, d);
  const c = await issueDeviceChallenge(db, acct, { deviceId: d.hex, purpose: 'activation' }, now());
  const { signature } = makeProof({ device: d.device, accountId: acct, deviceId: d.deviceId, certificate: d.certificate, challenge: fromB64(c.challenge) });
  await activateDevice(db, acct, { deviceId: d.hex, challengeId: c.challengeId, proof: b64(signature) }, now());
}

async function enroll(acct, d, { registered = false } = {}) {
  if (!registered) await register(acct, d);
  const request = await requestDeviceApproval(db, acct, { deviceId: d.hex }, now());
  const { signature } = makeProof({ device: d.device, accountId: acct, deviceId: d.deviceId, certificate: d.certificate, challenge: fromB64(request.challenge), purpose: 2 });
  await proveDeviceEnrollment(db, acct, { requestId: request.requestId, proof: b64(signature) }, now());
  return request;
}

const approvalSig = (acct, approver, d, request) =>
  b64(makeApproval({ approver, newDevice: d, accountId: acct, challenge: fromB64(request.challenge), expiresAtUnix: request.expiresAtUnix }).signature);

const approve = (acct, approver, request, signature, at = now()) =>
  approveDevice(db, acct, { requestId: request.requestId, approverDeviceId: approver.hex, signature }, at);

async function approveNew(acct, approver, d) {
  const request = await enroll(acct, d);
  await approve(acct, approver, request, approvalSig(acct, approver, d, request));
  return request;
}

/** The real, signed revocation path (D-081). */
async function revoke(acct, revoker, target, { reason = 2, signer, at } = {}) {
  const c = await issueDeviceChallenge(db, acct, { deviceId: revoker.hex, purpose: 'revocation' }, now());
  const { signature } = makeRevocation({ revoker, revoked: target, accountId: acct, reason, challenge: fromB64(c.challenge), expiresAtUnix: c.expiresAtUnix, signer });
  await revokeDevice(db, acct, { revokerDeviceId: revoker.hex, deviceId: target.hex, reason, challengeId: c.challengeId, signature: b64(signature) }, at ?? now());
  return c;
}

/** Bypasses rate limits/transactions to set server state directly (setup only). */
const forceStatus = (acct, d, status) => db.doc(`users/${acct}/devices/${d.hex}`).update({ status });

describe('signed revocation (D-081)', () => {
  test('a trusted device revokes another: signed evidence kept, epoch bumped', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const before = (await trustOf(acct)).trustEpoch;
    await revoke(acct, A, B, { reason: 3 });
    const r = await record(acct, B);
    assert.equal(r.status, 'revoked');
    assert.equal(r.revokedReason, 'stolen');
    assert.equal(r.revocation.authority, 'device');
    assert.equal(r.revocation.revokerDeviceId, A.hex);
    // The stored statement is independently verifiable (what peers do).
    verifyRevocation(acct, Buffer.from(r.revocation.revokerCertificate), B.certificate, r.revocation.reason, Buffer.from(r.revocation.challenge), r.revocation.expiresAtUnix, Buffer.from(r.revocation.signature));
    assert.equal((await trustOf(acct)).trustEpoch, before + 1);
    assert.equal(r.revokedEpoch, before + 1);
    assert.equal(r.activatedEpoch, before, 'activation order survives revocation (D-084)');
  });

  test('self-revocation by the device itself', async () => {
    const acct = account();
    const A = newDevice();
    await bootstrap(acct, A);
    await revoke(acct, A, A, { reason: 1 });
    assert.equal((await record(acct, A)).status, 'revoked');
  });

  test('a revoked, pending or foreign device cannot revoke; forgery fails', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await register(acct, C); // pending
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: C.hex, purpose: 'revocation' }, now()), 'approver_not_trusted');
    // Forged signature (wrong key) from a trusted revoker's challenge.
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'revocation' }, now());
    const forged = makeRevocation({ revoker: A, revoked: B, accountId: acct, reason: 2, challenge: fromB64(c.challenge), expiresAtUnix: c.expiresAtUnix, signer: B.person }).signature;
    await rejectsWith(revokeDevice(db, acct, { revokerDeviceId: A.hex, deviceId: B.hex, reason: 2, challengeId: c.challengeId, signature: b64(forged) }, now()), 'revocation_invalid');
    assert.equal((await record(acct, B)).status, 'active');
    // Revoked B cannot revoke A.
    await revoke(acct, A, B);
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'revocation' }, now()), 'approver_not_trusted');
  });

  test('replayed revocation and revoking twice fail; the challenge is single-use', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'revocation' }, now());
    const { signature } = makeRevocation({ revoker: A, revoked: B, accountId: acct, reason: 2, challenge: fromB64(c.challenge), expiresAtUnix: c.expiresAtUnix });
    const args = { revokerDeviceId: A.hex, deviceId: B.hex, reason: 2, challengeId: c.challengeId, signature: b64(signature) };
    await revokeDevice(db, acct, args, now());
    await rejectsWith(revokeDevice(db, acct, args, now()), 'challenge_invalid');
    // A fresh, valid revocation of an already-revoked device is refused.
    await rejectsWith(revoke(acct, A, B), 'device_not_pending');
  });

  test('wrong account: another account cannot revoke this account\'s devices', async () => {
    const victim = account();
    const attacker = account();
    const [A, X] = [newDevice(), newDevice()];
    await bootstrap(victim, A);
    await bootstrap(attacker, X);
    const c = await issueDeviceChallenge(db, attacker, { deviceId: X.hex, purpose: 'revocation' }, now());
    const { signature } = makeRevocation({ revoker: X, revoked: A, accountId: attacker, reason: 2, challenge: fromB64(c.challenge), expiresAtUnix: c.expiresAtUnix });
    // The target is looked up in the CALLER's account: not found there.
    await rejectsWith(revokeDevice(db, attacker, { revokerDeviceId: X.hex, deviceId: A.hex, reason: 2, challengeId: c.challengeId, signature: b64(signature) }, now()), 'device_not_found');
    assert.equal((await record(victim, A)).status, 'active');
  });

  test('stale revocation challenge and malformed reason', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const later = new Date(Date.now() + TTL.challengeMs + 1000);
    await rejectsWith(revoke(acct, A, B, { at: later }), 'challenge_expired');
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'revocation' }, now());
    await rejectsWith(revokeDevice(db, acct, { revokerDeviceId: A.hex, deviceId: B.hex, reason: 9, challengeId: c.challengeId, signature: b64(Buffer.alloc(64)) }, now()), 'invalid_argument');
  });
});

describe('stored lineage evidence (D-084)', () => {
  test('approval and recovery records carry evidence a peer can verify', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    const recovery = keyFromSeed(randomBytes(32));
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const rb = await record(acct, B);
    assert.equal(rb.approval.protocolVersion, 1);
    verifyApproval(acct, Buffer.from(rb.approval.approverCertificate), B.certificate, Buffer.from(rb.approval.challenge), rb.approval.expiresAtUnix, Buffer.from(rb.approval.signature));
    // B registers a recovery key; it recovers C.
    const ch = await issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'recovery_registration' }, now());
    const reg = makeRecoveryRegistration({ registrar: B, recovery, accountId: acct, challenge: fromB64(ch.challenge), expiresAtUnix: ch.expiresAtUnix });
    await registerRecoveryKey(db, acct, { deviceId: B.hex, challengeId: ch.challengeId, recoveryPublicKey: b64(recovery.publicKey), signature: b64(reg.signature) }, now());
    const request = await enroll(acct, C);
    const rec = makeRecoveryApproval({ recovery, newDevice: C, accountId: acct, challenge: fromB64(request.challenge), expiresAtUnix: request.expiresAtUnix });
    await recoverDevice(db, acct, { requestId: request.requestId, signature: b64(rec.signature) }, now());
    const rc = await record(acct, C);
    const e = rc.recovery;
    verifyRecoveryRegistration(acct, Buffer.from(e.registration.registrarCertificate), Buffer.from(e.recoveryPublicKey), Buffer.from(e.registration.challenge), e.registration.expiresAtUnix, Buffer.from(e.registration.signature));
    verifyRecoveryApproval(acct, Buffer.from(e.recoveryPublicKey), C.certificate, Buffer.from(e.challenge), e.expiresAtUnix, Buffer.from(e.signature));
    assert.equal(e.registration.registrarDeviceId, B.hex);
  });
});

describe('trust epoch (D-083)', () => {
  test('every trust change strictly increases the epoch; registration does not', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    const epochs = [];
    const snap = async () => epochs.push((await trustOf(acct))?.trustEpoch ?? 0);
    await snap();
    await bootstrap(acct, A);
    await snap();
    await register(acct, B);
    await snap(); // registration: unchanged
    const rb = await enroll(acct, B, { registered: true });
    await approve(acct, A, rb, approvalSig(acct, A, B, rb));
    await snap();
    await revoke(acct, A, B);
    await snap();
    await approveNew(acct, A, C);
    await snap();
    assert.deepEqual(epochs, [0, 1, 1, 2, 3, 4]);
  });
});

describe('identity reset (D-082)', () => {
  test('a trusted device cancels a reset requested with only the password', async () => {
    const acct = account();
    const A = newDevice();
    await bootstrap(acct, A);
    const r = await requestIdentityReset(db, acct, {}, now());
    assert.ok(r.effectiveAtMillis - Date.now() > TTL.identityResetDelayMs - 60_000);
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'reset_cancel' }, now());
    const { signature } = makeResetCancel({ device: A, accountId: acct, challenge: fromB64(c.challenge), expiresAtUnix: c.expiresAtUnix });
    await cancelIdentityReset(db, acct, { deviceId: A.hex, challengeId: c.challengeId, signature: b64(signature) }, now());
    assert.equal((await trustOf(acct)).reset, undefined);
    const later = new Date(Date.now() + TTL.identityResetDelayMs + 1000);
    await rejectsWith(completeIdentityReset(db, acct, {}, later), 'reset_unavailable');
    assert.equal((await record(acct, A)).status, 'active');
  });

  test('without any trusted device: reset completes only after the delay, then one new bootstrap', async () => {
    const acct = account();
    const [A, B, N1, N2] = [newDevice(), newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await forceStatus(acct, A, 'revoked'); // all devices lost
    await forceStatus(acct, B, 'revoked');
    await requestIdentityReset(db, acct, {}, now());
    // Repeating the request returns the same pending reset (no delay reset).
    const again = await requestIdentityReset(db, acct, {}, now());
    await rejectsWith(completeIdentityReset(db, acct, {}, now()), 'reset_not_ready');
    const later = new Date(again.effectiveAtMillis + 1000);
    await completeIdentityReset(db, acct, {}, later);
    const t = await trustOf(acct);
    assert.equal(t.bootstrapOpen, true);
    assert.equal(t.identityEpoch, 1);
    assert.equal(t.recoveryKey, undefined);
    // Exactly one new first device.
    await bootstrap(acct, N1);
    assert.equal((await record(acct, N1)).activationMethod, 'first_device');
    await register(acct, N2);
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: N2.hex, purpose: 'activation' }, now()), 'approval_required');
    // The old identity can never come back.
    await rejectsWith(register(acct, A), 'duplicate_device');
  });

  test('completing revokes every live device (authority identity_reset)', async () => {
    const acct = account();
    const [A, P] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await register(acct, P); // a pending device too
    const r = await requestIdentityReset(db, acct, {}, now());
    await completeIdentityReset(db, acct, {}, new Date(r.effectiveAtMillis + 1000));
    for (const d of [A, P]) {
      const rec = await record(acct, d);
      assert.equal(rec.status, 'revoked');
      assert.equal(rec.revocation.authority, 'identity_reset');
    }
    await rejectsWith(completeIdentityReset(db, acct, {}, new Date(r.effectiveAtMillis + 2000)), 'reset_unavailable');
  });

  test('no reset before trust exists; a revoked device cannot cancel; forged cancel fails', async () => {
    const empty = account();
    await rejectsWith(requestIdentityReset(db, empty, {}, now()), 'reset_unavailable');
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await requestIdentityReset(db, acct, {}, now());
    const c = await issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'reset_cancel' }, now());
    const forged = makeResetCancel({ device: B, accountId: acct, challenge: fromB64(c.challenge), expiresAtUnix: c.expiresAtUnix, signer: A.device }).signature;
    await rejectsWith(cancelIdentityReset(db, acct, { deviceId: B.hex, challengeId: c.challengeId, signature: b64(forged) }, now()), 'approval_invalid');
    await revoke(acct, A, B);
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'reset_cancel' }, now()), 'approver_not_trusted');
    assert.equal((await trustOf(acct)).reset.status, 'pending');
  });
});

describe('state machine edges (§8)', () => {
  test('approval after rejection, after expiry, and recovery after revocation all fail', async () => {
    const acct = account();
    const [A, B, C, D] = [newDevice(), newDevice(), newDevice(), newDevice()];
    const recovery = keyFromSeed(randomBytes(32));
    await bootstrap(acct, A);
    // Rejected: the rejected device can never be approved.
    const rB = await enroll(acct, B);
    const sigB = approvalSig(acct, A, B, rB);
    await rejectDeviceApproval(db, acct, { requestId: rB.requestId }, now());
    await rejectsWith(approve(acct, A, rB, sigB), 'request_invalid');
    await rejectsWith(requestDeviceApproval(db, acct, { deviceId: B.hex }, now()), 'device_not_pending');
    // Expired device (pending past its deadline).
    const rC = await enroll(acct, C);
    await db.doc(`users/${acct}/devices/${C.hex}`).update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    await rejectsWith(approve(acct, A, rC, approvalSig(acct, A, C, rC)), 'device_expired');
    // The refused transaction rolls back; the device is never active and the
    // scheduled cleanup marks it expired.
    assert.equal((await record(acct, C)).status, 'pending');
    // Recovery after the target was revoked.
    const ch = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now());
    const reg = makeRecoveryRegistration({ registrar: A, recovery, accountId: acct, challenge: fromB64(ch.challenge), expiresAtUnix: ch.expiresAtUnix });
    await registerRecoveryKey(db, acct, { deviceId: A.hex, challengeId: ch.challengeId, recoveryPublicKey: b64(recovery.publicKey), signature: b64(reg.signature) }, now());
    const rD = await enroll(acct, D);
    await forceStatus(acct, D, 'revoked');
    const rec = makeRecoveryApproval({ recovery, newDevice: D, accountId: acct, challenge: fromB64(rD.challenge), expiresAtUnix: rD.expiresAtUnix });
    await rejectsWith(recoverDevice(db, acct, { requestId: rD.requestId, signature: b64(rec.signature) }, now()), 'device_not_pending');
  });

  test('wrong protocol version: an approval signed over a v2 header is invalid', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B);
    const { payload } = makeApproval({ approver: A, newDevice: B, accountId: acct, challenge: fromB64(request.challenge), expiresAtUnix: request.expiresAtUnix });
    const v2 = Buffer.from(payload);
    v2['SirfHum-DeviceApproval-v1'.length] = 2; // the version byte
    const { sign } = await import('node:crypto');
    await rejectsWith(approve(acct, A, request, b64(sign(null, v2, A.person.privateKey))), 'approval_invalid');
  });

  test('registration while account trust exists stays pending; several pending devices allowed up to the cap', async () => {
    const acct = account();
    const [A, B, C, D, E] = [newDevice(), newDevice(), newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    for (const d of [B, C, D]) await register(acct, d);
    for (const d of [B, C, D]) assert.equal((await record(acct, d)).status, 'pending');
    await rejectsWith(register(acct, E), 'too_many_pending');
  });
});

describe('concurrency and races (§9)', () => {
  const outcomes = async (promises) => {
    const results = await Promise.allSettled(promises);
    return {
      ok: results.filter((r) => r.status === 'fulfilled').length,
      failures: results.filter((r) => r.status === 'rejected').map((r) => r.reason?.failure ?? String(r.reason)),
    };
  };

  test('two simultaneous approvals of one request: exactly one wins', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    const request = await enroll(acct, B);
    const sig = approvalSig(acct, A, B, request);
    const r = await outcomes([approve(acct, A, request, sig), approve(acct, A, request, sig)]);
    assert.equal(r.ok, 1, JSON.stringify(r));
    assert.equal((await record(acct, B)).status, 'active');
  });

  test('two first devices bootstrapping at once: only one becomes the root', async () => {
    const acct = account();
    const [A, B] = [newDevice(), newDevice()];
    await register(acct, A);
    await register(acct, B);
    const challenge = async (d) => {
      const c = await issueDeviceChallenge(db, acct, { deviceId: d.hex, purpose: 'activation' }, now());
      const { signature } = makeProof({ device: d.device, accountId: acct, deviceId: d.deviceId, certificate: d.certificate, challenge: fromB64(c.challenge) });
      return { deviceId: d.hex, challengeId: c.challengeId, proof: b64(signature) };
    };
    const [ca, cb] = [await challenge(A), await challenge(B)];
    const r = await outcomes([activateDevice(db, acct, ca, now()), activateDevice(db, acct, cb, now())]);
    assert.equal(r.ok, 1, JSON.stringify(r));
    assert.deepEqual(r.failures, ['approval_required']);
    const statuses = [(await record(acct, A)).status, (await record(acct, B)).status].sort();
    assert.deepEqual(statuses, ['active', 'pending']);
    assert.equal((await trustOf(acct)).trustEpoch, 1);
  });

  test('repeated consumption of one activation challenge: one success', async () => {
    const acct = account();
    const A = newDevice();
    await register(acct, A);
    const c = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'activation' }, now());
    const { signature } = makeProof({ device: A.device, accountId: acct, deviceId: A.deviceId, certificate: A.certificate, challenge: fromB64(c.challenge) });
    const args = { deviceId: A.hex, challengeId: c.challengeId, proof: b64(signature) };
    const r = await outcomes([activateDevice(db, acct, args, now()), activateDevice(db, acct, args, now()), activateDevice(db, acct, args, now())]);
    assert.equal(r.ok, 1, JSON.stringify(r));
  });

  test('two recovery attempts with one single-use key: one wins', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    const recovery = keyFromSeed(randomBytes(32));
    await bootstrap(acct, A);
    const ch = await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now());
    const reg = makeRecoveryRegistration({ registrar: A, recovery, accountId: acct, challenge: fromB64(ch.challenge), expiresAtUnix: ch.expiresAtUnix });
    await registerRecoveryKey(db, acct, { deviceId: A.hex, challengeId: ch.challengeId, recoveryPublicKey: b64(recovery.publicKey), signature: b64(reg.signature) }, now());
    const [rB, rC] = [await enroll(acct, B), await enroll(acct, C)];
    const sig = (d, req) => b64(makeRecoveryApproval({ recovery, newDevice: d, accountId: acct, challenge: fromB64(req.challenge), expiresAtUnix: req.expiresAtUnix }).signature);
    const r = await outcomes([
      recoverDevice(db, acct, { requestId: rB.requestId, signature: sig(B, rB) }, now()),
      recoverDevice(db, acct, { requestId: rC.requestId, signature: sig(C, rC) }, now()),
    ]);
    assert.equal(r.ok, 1, JSON.stringify(r));
    assert.deepEqual(r.failures, ['recovery_unavailable']);
  });

  test('approval racing a revocation of its approver: the end state is consistent', async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    const request = await enroll(acct, C);
    const sig = approvalSig(acct, A, C, request);
    const rc = await issueDeviceChallenge(db, acct, { deviceId: B.hex, purpose: 'revocation' }, now());
    const rev = makeRevocation({ revoker: B, revoked: A, accountId: acct, reason: 4, challenge: fromB64(rc.challenge), expiresAtUnix: rc.expiresAtUnix }).signature;
    await outcomes([
      approve(acct, A, request, sig),
      revokeDevice(db, acct, { revokerDeviceId: B.hex, deviceId: A.hex, reason: 4, challengeId: rc.challengeId, signature: b64(rev) }, now()),
    ]);
    const a = await record(acct, A);
    const c = await record(acct, C);
    assert.equal(a.status, 'revoked');
    // Either the approval committed first (C active, epoch before the
    // revocation) or it was refused (C pending). Never active after A's revocation.
    if (c.status === 'active') assert.ok(c.activatedEpoch < a.revokedEpoch, 'approval must precede the revocation');
    else assert.equal(c.status, 'pending');
  });

  test('concurrent registrations never exceed the pending cap', async () => {
    const acct = account();
    const devices = [newDevice(), newDevice(), newDevice(), newDevice(), newDevice()];
    const r = await outcomes(devices.map((d) => register(acct, d)));
    const pending = (await db.collection(`users/${acct}/devices`).where('status', '==', 'pending').get()).size;
    assert.ok(pending <= 3, `pending ${pending}`);
    assert.equal(r.ok, pending);
  });
});

describe('rate-limit boundaries (§12)', () => {
  test('exactly the limit passes, one over is refused, a new window resets', async () => {
    const acct = account();
    const A = newDevice();
    await bootstrap(acct, A); // 1 registration + 1 challenge used
    const limit = LIMITS.challenge.max;
    for (let i = 1; i < limit; i++) {
      await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now());
    }
    await rejectsWith(issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now()), 'rate_limited');
    const nextWindow = new Date(Date.now() + LIMITS.challenge.windowMs + 1000);
    await issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, nextWindow);
  });

  test('concurrent attempts cannot exceed a limit', async () => {
    const acct = account();
    const A = newDevice();
    await bootstrap(acct, A);
    const tries = Array.from({ length: LIMITS.challenge.max + 4 }, () =>
      issueDeviceChallenge(db, acct, { deviceId: A.hex, purpose: 'recovery_registration' }, now()),
    );
    const results = await Promise.allSettled(tries);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    // 1 challenge was already used by bootstrap.
    assert.ok(ok <= LIMITS.challenge.max - 1, `ok ${ok}`);
    for (const r of results.filter((x) => x.status === 'rejected')) assert.equal(r.reason.failure, 'rate_limited');
  });

  test('limits are per account: one account at its limit does not affect another', async () => {
    const a = account();
    const b = account();
    for (let i = 0; i < LIMITS.register.max; i++) {
      const d = newDevice();
      await register(a, d).catch(() => {});
      await db.doc(`users/${a}/devices/${d.hex}`).update({ status: 'expired' }).catch(() => {});
    }
    await rejectsWith(register(a, newDevice()), 'rate_limited');
    await register(b, newDevice());
  });
});

describe('person key uniqueness (Prompt 17, D-122)', () => {
  /** What a holder of `person`'s PIK can certify: a fresh device ID and key. */
  function sibling(person) {
    const device = keyFromSeed(randomBytes(32));
    const deviceId = randomBytes(16);
    return { person, device, deviceId, hex: deviceId.toString('hex'), certificate: makeCertificate({ person, device, deviceId }) };
  }

  async function activate(acct, d) {
    const c = await issueDeviceChallenge(db, acct, { deviceId: d.hex, purpose: 'activation' }, now());
    const { signature } = makeProof({ device: d.device, accountId: acct, deviceId: d.deviceId, certificate: d.certificate, challenge: fromB64(c.challenge) });
    return activateDevice(db, acct, { deviceId: d.hex, challengeId: c.challengeId, proof: b64(signature) }, now());
  }

  test("a revoked device's PIK never returns under a new device ID, even through an unaware approver", async () => {
    const acct = account();
    const [A, B, C] = [newDevice(), newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, B);
    await approveNew(acct, A, C);
    await revoke(acct, A, B);
    // B's holder certifies a fresh device ID with B's retained PIK; C has
    // not refreshed lineage, so only the server stands in the way here.
    await rejectsWith(register(acct, sibling(B.person)), 'duplicate_device');
    assert.equal((await db.doc(`personKeyIndex/${registration.personKeyIndexId(B.person.publicKey)}`).get()).get('deviceId'), B.hex);
  });

  test('two pending devices sharing a PIK: the second activation is refused, whoever approves it', async () => {
    const acct = account();
    const [A, C] = [newDevice(), newDevice()];
    await bootstrap(acct, A);
    await approveNew(acct, A, C);
    // Both registered while the PIK was still unused (registration cannot
    // see the future), so activation must re-check.
    const X = newDevice();
    const twin = sibling(X.person);
    await register(acct, X);
    await register(acct, twin);
    const first = await enroll(acct, X, { registered: true });
    await approve(acct, A, first, approvalSig(acct, A, X, first));
    const second = await enroll(acct, twin, { registered: true });
    await rejectsWith(approve(acct, C, second, approvalSig(acct, C, twin, second)), 'duplicate_device');
    assert.equal((await record(acct, twin)).status, 'pending');
    assert.equal((await record(acct, X)).status, 'active');
  });

  test('a PIK is global: another account cannot activate a device with it, even when registered first', async () => {
    const [mine, theirs] = [account(), account()];
    const A = newDevice();
    const copy = sibling(A.person);
    await register(mine, A);
    await register(theirs, copy); // both pending, neither activated yet
    await activate(mine, A);
    await rejectsWith(activate(theirs, copy), 'duplicate_device');
    assert.equal((await record(theirs, copy)).status, 'pending');
    assert.equal(await trustOf(theirs), undefined, 'the refused bootstrap created no trust');
    await rejectsWith(register(theirs, sibling(A.person)), 'duplicate_device');
  });

  test("after an identity reset the old root's PIK cannot root the new identity", async () => {
    const acct = account();
    const A = newDevice();
    await bootstrap(acct, A);
    const r = await requestIdentityReset(db, acct, {}, now());
    await completeIdentityReset(db, acct, {}, new Date(r.effectiveAtMillis + 1000));
    await rejectsWith(register(acct, sibling(A.person)), 'duplicate_device');
    const N = newDevice();
    await bootstrap(acct, N);
    assert.equal((await trustOf(acct)).firstDeviceId, N.hex);
  });
});
