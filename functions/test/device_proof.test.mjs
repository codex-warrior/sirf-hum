// Device certificate (D-064) and proof-of-possession (D-070) verification.
// Runs against the compiled output (`npm run build` first).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';
import certModule from '../lib/device/certificate.js';
import proofModule from '../lib/device/proof.js';
import { goldenVector, keyFromSeed, makeCertificate, makeProof, seed } from './support.mjs';

const { decodeCertificate, InvalidCertificateError, MAX_CERTIFICATE_BYTES, verifyCertificate } =
  certModule;
const { InvalidProofError, ProofPurpose, verifyDeviceProof } = proofModule;

const committed = JSON.parse(
  readFileSync(new URL('./vectors/device_proof_v1.json', import.meta.url), 'utf8'),
);
const hex = (s) => Buffer.from(s, 'hex');

function fixture() {
  const person = keyFromSeed(seed(1));
  const device = keyFromSeed(seed(2));
  const deviceId = Buffer.alloc(16, 0xab);
  const accountId = 'accountA';
  const challenge = Buffer.alloc(32, 7);
  const certificate = makeCertificate({ person, device, deviceId });
  const { signature } = makeProof({ device, accountId, deviceId, certificate, challenge });
  return { person, device, deviceId, accountId, challenge, certificate, signature };
}

const verifyWith = (f, overrides = {}) => {
  const v = { ...f, ...overrides };
  return verifyDeviceProof(ProofPurpose.activation, v.accountId, v.certificate, v.challenge, v.signature);
};

describe('golden vector', () => {
  test('committed vector equals a fresh deterministic regeneration', () => {
    assert.deepEqual(goldenVector(), committed);
  });

  test('committed vector verifies', () => {
    const cert = verifyDeviceProof(
      ProofPurpose.activation,
      committed.accountId,
      hex(committed.certificateHex),
      hex(committed.challengeHex),
      hex(committed.signatureHex),
    );
    assert.equal(cert.deviceId.toString('hex'), committed.deviceIdHex);
  });
});

describe('certificate', () => {
  test('valid certificate decodes and verifies', () => {
    const f = fixture();
    const cert = verifyCertificate(f.certificate);
    assert.deepEqual(cert.deviceId, f.deviceId);
    assert.deepEqual(cert.deviceSignatureKey, f.device.publicKey);
  });

  test('every single-byte alteration is rejected', () => {
    const f = fixture();
    for (let i = 0; i < f.certificate.length; i++) {
      const altered = Buffer.from(f.certificate);
      altered[i] ^= 1;
      assert.throws(() => verifyCertificate(altered), InvalidCertificateError, `byte ${i} accepted`);
    }
  });

  test('truncated, extended, oversized and wrong-version certificates are rejected', () => {
    const f = fixture();
    assert.throws(() => decodeCertificate(f.certificate.subarray(0, -1)), InvalidCertificateError);
    assert.throws(() => decodeCertificate(Buffer.concat([f.certificate, Buffer.from([0])])), InvalidCertificateError);
    assert.throws(() => decodeCertificate(Buffer.alloc(MAX_CERTIFICATE_BYTES + 1)), InvalidCertificateError);
    const wrongVersion = Buffer.from(f.certificate);
    wrongVersion[0] = 2;
    assert.throws(() => decodeCertificate(wrongVersion), InvalidCertificateError);
    assert.throws(() => decodeCertificate(Buffer.alloc(0)), InvalidCertificateError);
  });

  test('certificate signed by a different person key is rejected', () => {
    const f = fixture();
    const forger = keyFromSeed(seed(9));
    // Claim the victim's person key but sign with the forger's key.
    const forged = makeCertificate({ person: { ...forger, publicKey: f.person.publicKey }, device: f.device, deviceId: f.deviceId });
    assert.throws(() => verifyCertificate(forged), InvalidCertificateError);
  });
});

describe('proof of possession', () => {
  test('valid proof verifies', () => {
    const f = fixture();
    assert.deepEqual(verifyWith(f).deviceId, f.deviceId);
  });

  test('altered account ID is rejected', () => {
    assert.throws(() => verifyWith(fixture(), { accountId: 'accountB' }), InvalidProofError);
  });

  test('stale or different challenge is rejected', () => {
    assert.throws(() => verifyWith(fixture(), { challenge: Buffer.alloc(32, 8) }), InvalidProofError);
    assert.throws(() => verifyWith(fixture(), { challenge: Buffer.alloc(31, 7) }), InvalidProofError);
  });

  test('tampered or wrong-length signature is rejected', () => {
    const f = fixture();
    const bad = Buffer.from(f.signature);
    bad[0] ^= 1;
    assert.throws(() => verifyWith(f, { signature: bad }), InvalidProofError);
    assert.throws(() => verifyWith(f, { signature: f.signature.subarray(0, 63) }), InvalidProofError);
    assert.throws(() => verifyWith(f, { signature: Buffer.alloc(0) }), InvalidProofError);
  });

  test('copied public key under a different device ID cannot be proven without the private key', () => {
    const f = fixture();
    const attackerPerson = keyFromSeed(seed(5));
    const attackerDevice = keyFromSeed(seed(6));
    // Attacker certifies the victim's device key under a new device ID...
    const copiedCert = makeCertificate({ person: attackerPerson, device: f.device, deviceId: Buffer.alloc(16, 0xcd) });
    // ...but can only sign with a key they hold.
    const { signature } = makeProof({ device: attackerDevice, accountId: f.accountId, deviceId: Buffer.alloc(16, 0xcd), certificate: copiedCert, challenge: f.challenge });
    assert.throws(() => verifyWith(f, { certificate: copiedCert, signature }), InvalidProofError);
  });

  test('a proof is bound to its certificate (no reuse with another certificate)', () => {
    const f = fixture();
    const other = makeCertificate({ person: f.person, device: f.device, deviceId: f.deviceId, issuedAt: 1n });
    assert.throws(() => verifyWith(f, { certificate: other }), InvalidProofError);
  });

  test('a proof for another purpose does not verify as activation', () => {
    const f = fixture();
    const { signature } = makeProof({ ...f, purpose: 2 });
    assert.throws(() => verifyWith(f, { signature }), InvalidProofError);
  });
});
