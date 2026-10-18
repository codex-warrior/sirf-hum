/**
 * Multi-device trust statements (D-075, D-076), server-side verifiers.
 *
 * Mirrors packages/sirf_hum_crypto/native/src/identity.rs byte for byte
 * (golden vectors in functions/test/vectors are verified by the Rust tests).
 * Each statement has its own domain string, so no signature can be replayed
 * as another kind (or as a Prompt 07 device proof / certificate):
 *
 *   approval:      "SirfHum-DeviceApproval-v1" | v1 | len|account
 *                  | approver id[16] | len|approver cert | new id[16] | len|new cert
 *                  | challenge[32] | expiresAt u64 BE          — signed by approver PIK
 *   registration:  "SirfHum-RecoveryKeyRegistration-v1" | v1 | len|account
 *                  | registrar id[16] | len|registrar cert | recovery key[32]
 *                  | challenge[32] | expiresAt u64 BE          — signed by registrar PIK
 *   recovery:      "SirfHum-RecoveryApproval-v1" | v1 | len|account
 *                  | recovery key[32] | new id[16] | len|new cert
 *                  | challenge[32] | expiresAt u64 BE          — signed by the recovery key
 *
 * Ed25519 via node:crypto; no primitive is implemented here.
 */
import { createHash } from 'node:crypto';
import { decodeCertificate, ed25519Verify, lengthPrefixed, MAX_CERTIFICATE_BYTES, verifyCertificate } from './certificate';
import { CHALLENGE_BYTES } from './proof';

export const TRUST_PROTOCOL_VERSION = 1;
export const RECOVERY_KEY_BYTES = 32;
export const SIGNATURE_BYTES = 64;

const CONTEXT = {
  approval: Buffer.from('SirfHum-DeviceApproval-v1', 'ascii'),
  registration: Buffer.from('SirfHum-RecoveryKeyRegistration-v1', 'ascii'),
  recovery: Buffer.from('SirfHum-RecoveryApproval-v1', 'ascii'),
  code: Buffer.from('SirfHum-ApprovalCode-v1', 'ascii'),
};

export class InvalidStatementError extends Error {
  constructor() {
    super('invalid_statement');
  }
}

function header(context: Buffer, accountId: string): Buffer[] {
  return [context, Buffer.from([TRUST_PROTOCOL_VERSION]), lengthPrefixed(Buffer.from(accountId, 'utf8'))];
}

function u64(value: number): Buffer {
  if (!Number.isSafeInteger(value) || value < 0) throw new InvalidStatementError();
  const out = Buffer.alloc(8);
  out.writeBigUInt64BE(BigInt(value), 0);
  return out;
}

function requireChallenge(challenge: Buffer): void {
  if (challenge.length !== CHALLENGE_BYTES) throw new InvalidStatementError();
}

function requireRecoveryKey(key: Buffer): void {
  if (key.length !== RECOVERY_KEY_BYTES) throw new InvalidStatementError();
}

export function approvalPayload(
  accountId: string,
  approverCertificate: Buffer,
  newCertificate: Buffer,
  challenge: Buffer,
  expiresAtUnix: number,
): Buffer {
  requireChallenge(challenge);
  const approver = decodeCertificate(approverCertificate);
  const created = decodeCertificate(newCertificate);
  return Buffer.concat([
    ...header(CONTEXT.approval, accountId),
    approver.deviceId,
    lengthPrefixed(approverCertificate),
    created.deviceId,
    lengthPrefixed(newCertificate),
    challenge,
    u64(expiresAtUnix),
  ]);
}

/** Both certificates must verify; the approver's PIK must sign the statement. */
export function verifyApproval(
  accountId: string,
  approverCertificate: Buffer,
  newCertificate: Buffer,
  challenge: Buffer,
  expiresAtUnix: number,
  signature: Buffer,
): void {
  const approver = verifyCertificate(approverCertificate);
  const created = verifyCertificate(newCertificate);
  if (approver.deviceId.equals(created.deviceId)) throw new InvalidStatementError();
  const payload = approvalPayload(accountId, approverCertificate, newCertificate, challenge, expiresAtUnix);
  if (!ed25519Verify(approver.personKey, payload, signature)) throw new InvalidStatementError();
}

export function recoveryRegistrationPayload(
  accountId: string,
  registrarCertificate: Buffer,
  recoveryPublicKey: Buffer,
  challenge: Buffer,
  expiresAtUnix: number,
): Buffer {
  requireChallenge(challenge);
  requireRecoveryKey(recoveryPublicKey);
  const registrar = decodeCertificate(registrarCertificate);
  return Buffer.concat([
    ...header(CONTEXT.registration, accountId),
    registrar.deviceId,
    lengthPrefixed(registrarCertificate),
    recoveryPublicKey,
    challenge,
    u64(expiresAtUnix),
  ]);
}

export function verifyRecoveryRegistration(
  accountId: string,
  registrarCertificate: Buffer,
  recoveryPublicKey: Buffer,
  challenge: Buffer,
  expiresAtUnix: number,
  signature: Buffer,
): void {
  const registrar = verifyCertificate(registrarCertificate);
  const payload = recoveryRegistrationPayload(accountId, registrarCertificate, recoveryPublicKey, challenge, expiresAtUnix);
  if (!ed25519Verify(registrar.personKey, payload, signature)) throw new InvalidStatementError();
}

export function recoveryApprovalPayload(
  accountId: string,
  recoveryPublicKey: Buffer,
  newCertificate: Buffer,
  challenge: Buffer,
  expiresAtUnix: number,
): Buffer {
  requireChallenge(challenge);
  requireRecoveryKey(recoveryPublicKey);
  const created = decodeCertificate(newCertificate);
  return Buffer.concat([
    ...header(CONTEXT.recovery, accountId),
    recoveryPublicKey,
    created.deviceId,
    lengthPrefixed(newCertificate),
    challenge,
    u64(expiresAtUnix),
  ]);
}

export function verifyRecoveryApproval(
  accountId: string,
  recoveryPublicKey: Buffer,
  newCertificate: Buffer,
  challenge: Buffer,
  expiresAtUnix: number,
  signature: Buffer,
): void {
  verifyCertificate(newCertificate);
  const payload = recoveryApprovalPayload(accountId, recoveryPublicKey, newCertificate, challenge, expiresAtUnix);
  if (!ed25519Verify(recoveryPublicKey, payload, signature)) throw new InvalidStatementError();
}

/** The six-digit comparison code (mirrors identity::approval_code). */
export function approvalCode(newCertificate: Buffer, challenge: Buffer): number {
  requireChallenge(challenge);
  if (newCertificate.length > MAX_CERTIFICATE_BYTES) throw new InvalidStatementError();
  const digest = createHash('sha256')
    .update(Buffer.concat([CONTEXT.code, lengthPrefixed(newCertificate), challenge]))
    .digest();
  return digest.readUInt32BE(0) % 1_000_000;
}
