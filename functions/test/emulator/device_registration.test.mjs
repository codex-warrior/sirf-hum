// Device registration against the Firestore emulator (Prompt 07 §10–11;
// since Prompt 08 this is the first-device bootstrap path, so every test uses
// a fresh account):
// challenge issuance, proof of possession, replay, cloning and revocation.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import { Buffer } from 'node:buffer';
import process from 'node:process';
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import common from '../../lib/device/common.js';
import registration from '../../lib/device/registration.js';
import { keyFromSeed, makeCertificate, makeProof, seed } from '../support.mjs';

const { activateDevice, issueDeviceChallenge } = registration;
const { DeviceError: RegistrationError, TTL } = common;
const CHALLENGE_TTL_MS = TTL.challengeMs;
const issueActivationChallenge = (db, uid, data, now) => issueDeviceChallenge(db, uid, { purpose: 'activation', ...data }, now);

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'device-registration-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

const now = () => new Date();
let counter = 0;
const unique = (prefix) => `${prefix}${++counter}${Date.now()}`;

/** A device as its own client would hold it: keys + pending record. */
function newDevice({ person = keyFromSeed(seed(counter % 200 + 1)), deviceKeySeed, deviceIdByte } = {}) {
  counter += 1;
  const device = keyFromSeed(seed(deviceKeySeed ?? ((counter * 7) % 250) + 1));
  const deviceId = Buffer.alloc(16, deviceIdByte ?? (counter * 13) % 256);
  deviceId.writeUInt32BE(counter, 0);
  deviceId.writeUInt32BE(Date.now() % 0xffffffff, 4);
  return { person, device, deviceId, certificate: makeCertificate({ person, device, deviceId }) };
}

/** The pending record a client writes (validated separately by the rules). */
async function createPending(accountId, d, overrides = {}) {
  await db.doc(`users/${accountId}/devices/${d.deviceId.toString('hex')}`).set({
    schemaVersion: 1,
    status: 'pending',
    platform: 'android',
    certificate: d.certificate,
    ciphersuite: 1,
    implementation: 'openmls/0.9.1',
    createdAt: Timestamp.now(),
    // Prompt 08: pending records carry a server-set expiry (D-078).
    expiresAt: Timestamp.fromMillis(Date.now() + TTL.pendingDeviceMs),
    ...overrides,
  });
}

const deviceHex = (d) => d.deviceId.toString('hex');

async function challengeFor(accountId, d) {
  return issueActivationChallenge(db, accountId, { deviceId: deviceHex(d) }, now());
}

function proofFor(accountId, d, issued, signer = d.device) {
  const { signature } = makeProof({
    device: signer,
    accountId,
    deviceId: d.deviceId,
    certificate: d.certificate,
    challenge: Buffer.from(issued.challenge, 'base64'),
  });
  return signature.toString('base64');
}

async function activate(accountId, d, issued, proof, at = now()) {
  return activateDevice(db, accountId, { deviceId: deviceHex(d), challengeId: issued.challengeId, proof }, at);
}

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => e instanceof RegistrationError && e.failure === failure);
}

async function status(accountId, d) {
  return (await db.doc(`users/${accountId}/devices/${deviceHex(d)}`).get()).get('status');
}

describe('activation', () => {
  test('valid proof activates a pending device and consumes the challenge', async () => {
    const account = unique('acct');
    const d = newDevice();
    await createPending(account, d);
    const issued = await challengeFor(account, d);
    assert.equal(Buffer.from(issued.challenge, 'base64').length, 32);
    assert.ok(issued.expiresAtMillis - Date.now() <= CHALLENGE_TTL_MS);

    await activate(account, d, issued, proofFor(account, d, issued));

    const snap = await db.doc(`users/${account}/devices/${deviceHex(d)}`).get();
    assert.equal(snap.get('status'), 'active');
    assert.ok(snap.get('activatedAt') instanceof Timestamp);
    assert.equal((await db.doc(`deviceChallenges/${issued.challengeId}`).get()).exists, false);
    assert.equal((await db.doc(`deviceIdIndex/${deviceHex(d)}`).get()).get('accountId'), account);
  });

  test('replayed proof (same challenge again) is rejected', async () => {
    const account = unique('acct');
    const d = newDevice();
    await createPending(account, d);
    const issued = await challengeFor(account, d);
    const proof = proofFor(account, d, issued);
    await activate(account, d, issued, proof);
    await rejectsWith(activate(account, d, issued, proof), 'challenge_invalid');
  });

  test('a challenge is single-use even when the first attempt fails', async () => {
    const account = unique('acct');
    const d = newDevice();
    await createPending(account, d);
    const issued = await challengeFor(account, d);
    const wrong = keyFromSeed(seed(251));
    await rejectsWith(activate(account, d, issued, proofFor(account, d, issued, wrong)), 'proof_invalid');
    // The correct proof can no longer use the consumed challenge.
    await rejectsWith(activate(account, d, issued, proofFor(account, d, issued)), 'challenge_invalid');
    assert.equal(await status(account, d), 'pending');
  });

  test('stale challenge is rejected', async () => {
    const account = unique('acct');
    const d = newDevice();
    await createPending(account, d);
    const issued = await challengeFor(account, d);
    const later = new Date(Date.now() + CHALLENGE_TTL_MS + 1000);
    await rejectsWith(activate(account, d, issued, proofFor(account, d, issued), later), 'challenge_expired');
    assert.equal(await status(account, d), 'pending');
  });

  test('already-active device cannot be activated again', async () => {
    const account = unique('acct');
    const d = newDevice();
    await createPending(account, d);
    const first = await challengeFor(account, d);
    await activate(account, d, first, proofFor(account, d, first));
    await rejectsWith(challengeFor(account, d), 'device_not_pending');
  });
});

describe('cloning and forgery', () => {
  test("copied record (another account's certificate) cannot be activated without the private key", async () => {
    const victim = unique('victim');
    const attacker = unique('attacker');
    const d = newDevice();
    await createPending(victim, d);
    // Attacker files a byte-identical copy of the victim's public record.
    await createPending(attacker, d);
    const issued = await challengeFor(attacker, d);
    const attackerKey = keyFromSeed(seed(252));
    await rejectsWith(activate(attacker, d, issued, proofFor(attacker, d, issued, attackerKey)), 'proof_invalid');
    assert.equal(await status(attacker, d), 'pending');
  });

  test("the victim's own proof replayed under another account is rejected (account binding)", async () => {
    const victim = unique('victim');
    const attacker = unique('attacker');
    const d = newDevice();
    await createPending(victim, d);
    await createPending(attacker, d);
    const issued = await challengeFor(attacker, d);
    // Even a genuine signature by the victim's device, made for the victim's
    // account, does not activate the device under the attacker's account.
    const victimProof = proofFor(victim, d, issued);
    await rejectsWith(activate(attacker, d, issued, victimProof), 'proof_invalid');
  });

  test("a challenge cannot be used by another account", async () => {
    const owner = unique('owner');
    const other = unique('other');
    const d = newDevice();
    await createPending(owner, d);
    await createPending(other, d);
    const issued = await challengeFor(owner, d);
    await rejectsWith(activate(other, d, issued, proofFor(other, d, issued)), 'challenge_invalid');
  });

  test('duplicate device ID across accounts is rejected', async () => {
    const a = unique('acct');
    const b = unique('acct');
    const first = newDevice();
    // Same device ID, different keys and person.
    const second = { ...newDevice(), deviceId: first.deviceId };
    second.certificate = makeCertificate({ person: second.person, device: second.device, deviceId: second.deviceId });
    await createPending(a, first);
    await createPending(b, second);
    const i1 = await challengeFor(a, first);
    await activate(a, first, i1, proofFor(a, first, i1));
    const i2 = await challengeFor(b, second);
    await rejectsWith(activate(b, second, i2, proofFor(b, second, i2)), 'duplicate_device');
    assert.equal(await status(b, second), 'pending');
  });

  test('duplicate device public key under a different device ID is rejected', async () => {
    const a = unique('acct');
    const b = unique('acct');
    const first = newDevice({ deviceKeySeed: 240 });
    const second = newDevice({ deviceKeySeed: 240 }); // same key, new device ID
    await createPending(a, first);
    await createPending(b, second);
    const i1 = await challengeFor(a, first);
    await activate(a, first, i1, proofFor(a, first, i1));
    const i2 = await challengeFor(b, second);
    await rejectsWith(activate(b, second, i2, proofFor(b, second, i2)), 'duplicate_device');
  });

  test('certificate for a different device ID than the record is rejected', async () => {
    const account = unique('acct');
    const d = newDevice();
    const other = newDevice();
    // File d's certificate under other's device ID.
    await db.doc(`users/${account}/devices/${deviceHex(other)}`).set({
      schemaVersion: 1, status: 'pending', platform: 'ios', certificate: d.certificate,
      ciphersuite: 1, implementation: 'openmls/0.9.1', createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() + TTL.pendingDeviceMs),
    });
    const issued = await challengeFor(account, other);
    const { signature } = makeProof({
      device: d.device, accountId: account, deviceId: d.deviceId, certificate: d.certificate,
      challenge: Buffer.from(issued.challenge, 'base64'),
    });
    await rejectsWith(
      activateDevice(db, account, { deviceId: deviceHex(other), challengeId: issued.challengeId, proof: signature.toString('base64') }, now()),
      'certificate_invalid',
    );
  });

  test('forged (altered) certificate is rejected', async () => {
    const account = unique('acct');
    const d = newDevice();
    const altered = Buffer.from(d.certificate);
    altered[40] ^= 1;
    await createPending(account, { ...d, certificate: altered });
    const issued = await challengeFor(account, d);
    await rejectsWith(activate(account, d, issued, proofFor(account, d, issued)), 'certificate_invalid');
  });
});

describe('revocation and input validation', () => {
  test('revoked device cannot get a challenge or activate', async () => {
    const account = unique('acct');
    const d = newDevice();
    await createPending(account, d);
    const issued = await challengeFor(account, d);
    await db.doc(`users/${account}/devices/${deviceHex(d)}`).update({ status: 'revoked' });
    await rejectsWith(activate(account, d, issued, proofFor(account, d, issued)), 'device_not_pending');
    await rejectsWith(challengeFor(account, d), 'device_not_pending');
  });

  test('unknown device and unauthenticated callers are rejected', async () => {
    const d = newDevice();
    await rejectsWith(challengeFor(unique('acct'), d), 'device_not_found');
    await rejectsWith(issueActivationChallenge(db, undefined, { deviceId: deviceHex(d) }, now()), 'unauthenticated');
    await rejectsWith(activateDevice(db, undefined, {}, now()), 'unauthenticated');
  });

  test('malformed and oversized inputs are rejected before any read', async () => {
    const account = unique('acct');
    const bad = [
      null,
      {},
      { deviceId: 'XYZ' },
      { deviceId: 'a'.repeat(33) },
      { deviceId: 'a'.repeat(32), challengeId: 'nope', proof: '' },
      { deviceId: 'a'.repeat(32), challengeId: 'b'.repeat(32), proof: 'A'.repeat(4096) },
      { deviceId: 'a'.repeat(32), challengeId: 'b'.repeat(32), proof: Buffer.alloc(63).toString('base64') },
      { deviceId: 'a'.repeat(32), challengeId: 'b'.repeat(32), proof: 42 },
    ];
    for (const input of bad) {
      await rejectsWith(activateDevice(db, account, input, now()), 'invalid_argument');
    }
    await rejectsWith(issueActivationChallenge(db, account, { deviceId: '../x' }, now()), 'invalid_argument');
    await rejectsWith(issueActivationChallenge(db, 'bad/uid', { deviceId: 'a'.repeat(32) }, now()), 'invalid_argument');
  });
});
