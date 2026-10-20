/**
 * Device proof of possession (D-070), server-side verifier.
 *
 * Mirrors `device_proof_payload` / `verify_device_proof` in
 * packages/sirf_hum_crypto/native/src/identity.rs:
 *
 *   "SirfHum-DeviceProof-v1" | purpose u8 | u32 len | account id (UTF-8)
 *   | device id (16) | u32 len | certificate | challenge (32)
 *
 * signed with the device signature key certified in `certificate`.
 */
import {
  DEVICE_ID_BYTES,
  type DeviceCertificate,
  ed25519Verify,
  lengthPrefixed,
  MAX_CERTIFICATE_BYTES,
  verifyCertificate,
} from './certificate';

export const CHALLENGE_BYTES = 32;
export const PROOF_BYTES = 64;
const PROOF_CONTEXT = Buffer.from('SirfHum-DeviceProof-v1', 'ascii');

/** Signed domains, one per purpose (never reuse a value). */
export const ProofPurpose = { activation: 1, enrollment: 2, pushToken: 3, pairing: 4, commit: 5, approvalRejection: 6 } as const;
export type ProofPurpose = (typeof ProofPurpose)[keyof typeof ProofPurpose];

export class InvalidProofError extends Error {
  constructor() {
    super('invalid_proof');
  }
}

export function deviceProofPayload(
  purpose: ProofPurpose,
  accountId: string,
  deviceId: Buffer,
  certificate: Buffer,
  challenge: Buffer,
): Buffer {
  if (
    deviceId.length !== DEVICE_ID_BYTES ||
    challenge.length !== CHALLENGE_BYTES ||
    certificate.length > MAX_CERTIFICATE_BYTES
  ) {
    throw new InvalidProofError();
  }
  return Buffer.concat([
    PROOF_CONTEXT,
    Buffer.from([purpose]),
    lengthPrefixed(Buffer.from(accountId, 'utf8')),
    deviceId,
    lengthPrefixed(certificate),
    challenge,
  ]);
}

/**
 * Verifies the certificate (person-key signature) and then the device's
 * signature over the proof payload. Returns the certificate on success;
 * throws InvalidCertificateError / InvalidProofError otherwise.
 */
export function verifyDeviceProof(
  purpose: ProofPurpose,
  accountId: string,
  certificate: Buffer,
  challenge: Buffer,
  signature: Buffer,
): DeviceCertificate {
  const cert = verifyCertificate(certificate);
  if (signature.length !== PROOF_BYTES) throw new InvalidProofError();
  const payload = deviceProofPayload(purpose, accountId, cert.deviceId, certificate, challenge);
  if (!ed25519Verify(cert.deviceSignatureKey, payload, signature)) throw new InvalidProofError();
  return cert;
}
