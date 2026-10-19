// Multi-device trust statements (D-075, D-076): approval, recovery-key
// registration, recovery approval and the comparison code.
// Runs against the compiled output (`npm run build` first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';
import { URL } from 'node:url';
import statementsModule from '../lib/device/statements.js';
import { keyFromSeed, makeApproval, makeDevice, makeProof, makeRecoveryApproval, makeRecoveryRegistration, seed, trustVectors } from './support.mjs';

const { approvalCode, InvalidStatementError, verifyApproval, verifyRecoveryApproval, verifyRecoveryRegistration } =
  statementsModule;

const committed = JSON.parse(readFileSync(new URL('./vectors/device_trust_v1.json', import.meta.url), 'utf8'));
const hex = (s) => Buffer.from(s, 'hex');

const account = 'accountA';
const challenge = Buffer.alloc(32, 9);
const expiresAtUnix = 1_800_000_000;
const A = makeDevice(1, 2, '11'.repeat(16));
const B = makeDevice(3, 4, '22'.repeat(16));
const C = makeDevice(5, 6, '33'.repeat(16));
const recovery = keyFromSeed(seed(7));

const approve = (o = {}) => {
  const v = { approver: A, newDevice: B, accountId: account, challenge, expiresAtUnix, ...o };
  const { signature } = makeApproval(v);
  return () => verifyApproval(o.verifyAccount ?? account, (o.verifyApprover ?? A).certificate, (o.verifyNew ?? B).certificate, o.verifyChallenge ?? challenge, o.verifyExpires ?? expiresAtUnix, o.signature ?? signature);
};

describe('golden vectors', () => {
  test('committed vectors equal a fresh deterministic regeneration', () => {
    assert.deepEqual(trustVectors(), committed);
  });

  test('committed vectors verify', () => {
    const v = committed;
    const exp = Number(v.expiresAtUnix);
    verifyApproval(v.accountId, hex(v.approverCertificateHex), hex(v.newCertificateHex), hex(v.challengeHex), exp, hex(v.approvalSignatureHex));
    verifyRecoveryRegistration(v.accountId, hex(v.approverCertificateHex), hex(v.recoveryPublicKeyHex), hex(v.challengeHex), exp, hex(v.registrationSignatureHex));
    verifyRecoveryApproval(v.accountId, hex(v.recoveryPublicKeyHex), hex(v.newCertificateHex), hex(v.challengeHex), exp, hex(v.recoverySignatureHex));
  });
});

describe('device approval', () => {
  test('valid approval verifies', () => {
    approve()();
  });

  test('wrong account, approver, device, challenge or expiry is rejected', () => {
    for (const altered of [
      { verifyAccount: 'accountB' },
      { verifyApprover: C },
      { verifyNew: C },
      { verifyChallenge: Buffer.alloc(32, 8) },
      { verifyExpires: expiresAtUnix + 1 },
    ]) {
      assert.throws(approve(altered), InvalidStatementError, JSON.stringify(Object.keys(altered)));
    }
  });

  test('approval by the wrong key (device key, other PIK, recovery key) is rejected', () => {
    for (const signer of [A.device, C.person, recovery]) {
      assert.throws(approve({ signer }), InvalidStatementError);
    }
  });

  test('tampered signature and self-approval are rejected', () => {
    const { signature } = makeApproval({ approver: A, newDevice: B, accountId: account, challenge, expiresAtUnix });
    const bad = Buffer.from(signature);
    bad[5] ^= 1;
    assert.throws(approve({ signature: bad }), InvalidStatementError);
    assert.throws(approve({ newDevice: A, verifyNew: A }), InvalidStatementError);
  });

  test('a Prompt 07 device proof is never accepted as an approval', () => {
    // Same keys, same challenge: the domain strings differ, so it fails.
    const { signature } = makeProof({ device: A.person, accountId: account, deviceId: A.deviceId, certificate: A.certificate, challenge });
    assert.throws(approve({ signature }), InvalidStatementError);
  });

  test('a recovery approval signature is not an approval', () => {
    const { signature } = makeRecoveryApproval({ recovery: A.person, newDevice: B, accountId: account, challenge, expiresAtUnix });
    assert.throws(approve({ signature }), InvalidStatementError);
  });
});

describe('recovery key', () => {
  test('registration verifies only for the registrar PIK and exact fields', () => {
    const { signature } = makeRecoveryRegistration({ registrar: A, recovery, accountId: account, challenge, expiresAtUnix });
    verifyRecoveryRegistration(account, A.certificate, recovery.publicKey, challenge, expiresAtUnix, signature);
    assert.throws(() => verifyRecoveryRegistration('accountB', A.certificate, recovery.publicKey, challenge, expiresAtUnix, signature), InvalidStatementError);
    assert.throws(() => verifyRecoveryRegistration(account, A.certificate, keyFromSeed(seed(8)).publicKey, challenge, expiresAtUnix, signature), InvalidStatementError);
    assert.throws(() => verifyRecoveryRegistration(account, C.certificate, recovery.publicKey, challenge, expiresAtUnix, signature), InvalidStatementError);
  });

  test('recovery approval verifies only for the registered key and exact device', () => {
    const { signature } = makeRecoveryApproval({ recovery, newDevice: B, accountId: account, challenge, expiresAtUnix });
    verifyRecoveryApproval(account, recovery.publicKey, B.certificate, challenge, expiresAtUnix, signature);
    assert.throws(() => verifyRecoveryApproval(account, recovery.publicKey, C.certificate, challenge, expiresAtUnix, signature), InvalidStatementError);
    assert.throws(() => verifyRecoveryApproval(account, keyFromSeed(seed(8)).publicKey, B.certificate, challenge, expiresAtUnix, signature), InvalidStatementError);
    assert.throws(() => verifyRecoveryApproval(account, recovery.publicKey, B.certificate, Buffer.alloc(32), expiresAtUnix, signature), InvalidStatementError);
  });

  test('malformed sizes are rejected', () => {
    assert.throws(() => verifyRecoveryApproval(account, Buffer.alloc(31), B.certificate, challenge, expiresAtUnix, Buffer.alloc(64)), InvalidStatementError);
    assert.throws(() => verifyRecoveryRegistration(account, A.certificate, recovery.publicKey, Buffer.alloc(31), expiresAtUnix, Buffer.alloc(64)), InvalidStatementError);
    assert.throws(() => verifyApproval(account, A.certificate, B.certificate, challenge, -1, Buffer.alloc(64)), InvalidStatementError);
  });
});

describe('comparison code', () => {
  test('six digits, deterministic, bound to certificate and challenge', () => {
    const code = approvalCode(B.certificate, challenge);
    assert.ok(Number.isInteger(code) && code >= 0 && code < 1_000_000);
    assert.equal(approvalCode(B.certificate, challenge), code);
    assert.notEqual(approvalCode(C.certificate, challenge), code);
    assert.notEqual(approvalCode(B.certificate, Buffer.alloc(32, 10)), code);
    assert.equal(String(approvalCode(hex(committed.newCertificateHex), hex(committed.challengeHex))).padStart(6, '0'), committed.approvalCode);
  });
});
