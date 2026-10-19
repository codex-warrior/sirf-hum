/**
 * Push token registration with proof of possession (Prompt 11, D-098).
 *
 *   requestPushTokenChallenge  an ACTIVE device asks to register (or clear)
 *                              a token; the single-use challenge is bound to
 *                              the token's hash
 *   registerPushToken          the device's key signs the challenge
 *                              (ProofPurpose.pushToken, D-070 format); the
 *                              server verifies it against the stored
 *                              certificate and writes `pushTokens/{deviceId}`
 *
 * A Firebase session alone cannot redirect or silence another device's
 * wake-ups (E24): only the device key can register its token. Tokens are
 * delivery addresses, never identity. `pushTokens/*` is server-only (rules
 * deny every client access). One token maps to one device: registering a
 * token removes it from every other device (e.g. account switch on one
 * install).
 */
import { createHash, randomBytes } from 'node:crypto';
import { FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { InvalidCertificateError } from '../device/certificate';
import {
  Collections,
  DEVICE_ID_PATTERN,
  DeviceError,
  type DeviceFailure,
  deviceRef,
  input,
  RECORD_ID_PATTERN,
  requireAccount,
  requireBytes,
  requirePattern,
  toUnixSeconds,
  TTL,
} from '../device/common';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from '../device/proof';
import { consume, requireBudget } from '../device/rateLimit';
import { recordFailure, type IssuedChallenge } from '../device/registration';

export const PUSH_TOKEN_PURPOSE = 'push_token';

/** FCM registration tokens: printable ASCII, bounded. */
const TOKEN_PATTERN = /^[\x21-\x7e]{1,4096}$/;

/** `null` clears the device's token (logout). */
export function requireToken(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== 'string' || !TOKEN_PATTERN.test(value)) throw new DeviceError('invalid_argument');
  return value;
}

/** What the challenge binds: the token (or clearing), never stored itself. */
export function tokenHash(token: string | null): string {
  return createHash('sha256')
    .update(`SirfHum-PushToken-v1|${token === null ? '-' : `+${token}`}`)
    .digest('hex');
}

export const pushTokenRef = (db: Firestore, deviceId: string) =>
  db.collection(Collections.pushTokens).doc(deviceId);

export async function requestPushTokenChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const token = requireToken(args.token);
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'pushToken', now);

  const device = await deviceRef(db, accountId, deviceId).get();
  if (!device.exists) throw new DeviceError('device_not_found');
  if (device.get('status') !== 'active') throw new DeviceError('device_not_active');

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.challengeMs);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose: PUSH_TOKEN_PURPOSE,
    tokenHash: tokenHash(token),
    challenge,
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  return { challengeId, challenge: challenge.toString('base64'), expiresAtMillis: expiresAtUnix * 1000, expiresAtUnix };
}

export async function registerPushToken(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const proof = requireBytes(args.proof, PROOF_BYTES);
  const token = requireToken(args.token);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const tokenRef = pushTokenRef(db, deviceId);
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const [challengeSnap, device, sameToken] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, deviceId)),
      token === null
        ? Promise.resolve(null)
        : tx.get(db.collection(Collections.pushTokens).where('token', '==', token)),
    ]);
    if (!challengeSnap.exists) return 'challenge_invalid';
    // Consumed by the first attempt, whatever its outcome.
    tx.delete(challengeRef);
    if (
      challengeSnap.get('accountId') !== accountId ||
      challengeSnap.get('deviceId') !== deviceId ||
      challengeSnap.get('purpose') !== PUSH_TOKEN_PURPOSE ||
      challengeSnap.get('tokenHash') !== tokenHash(token)
    ) {
      return 'challenge_invalid';
    }
    const expiresAt = challengeSnap.get('expiresAt') as unknown;
    if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'challenge_expired';
    if (!device.exists) return 'device_not_found';
    if (device.get('status') !== 'active') return 'device_not_active';
    try {
      const cert = verifyDeviceProof(
        ProofPurpose.pushToken,
        accountId,
        Buffer.from(device.get('certificate') as Uint8Array),
        Buffer.from(challengeSnap.get('challenge') as Uint8Array),
        proof,
      );
      if (cert.deviceId.toString('hex') !== deviceId) return 'certificate_invalid';
    } catch (error) {
      if (error instanceof InvalidCertificateError) return 'certificate_invalid';
      if (error instanceof InvalidProofError) return 'proof_invalid';
      throw error;
    }
    if (token === null) {
      tx.delete(tokenRef);
      return null;
    }
    // One token, one device.
    for (const other of sameToken?.docs ?? []) {
      if (other.id !== deviceId) tx.delete(other.ref);
    }
    tx.set(tokenRef, { accountId, deviceId, token, updatedAt: FieldValue.serverTimestamp() });
    return null;
  });
  if (failure !== null) {
    if (failure === 'proof_invalid' || failure === 'certificate_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}
