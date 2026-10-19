/**
 * Device registration, challenges and first-device bootstrap (D-069, D-070,
 * D-075).
 *
 *   registerDevice        client → server: create the `pending` record
 *                         (certificate verified, rate-limited, capped)
 *   issueDeviceChallenge  single-use challenge for `activation` (pending
 *                         device) or `recovery_registration` (active device)
 *   activateDevice        BOOTSTRAP ONLY: proof of possession activates the
 *                         account's first device, once ever. Every later
 *                         device needs approval by a trusted device or the
 *                         recovery key (trust.ts): `approval_required`.
 *
 * Firebase Auth proves the account; it never makes a device trusted.
 * Pure logic over an injected Firestore + clock (emulator-tested); callable
 * wrappers live in ../index.ts.
 */
import { createHash, randomBytes } from 'node:crypto';
import { type DocumentSnapshot, FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { InvalidCertificateError, MAX_CERTIFICATE_BYTES, verifyCertificate } from './certificate';
import {
  Collections,
  DEVICE_ID_PATTERN,
  DEVICE_SCHEMA_VERSION,
  DeviceError,
  type DeviceFailure,
  deviceRef,
  input,
  MAX_PENDING_DEVICES,
  PLATFORMS,
  RECORD_ID_PATTERN,
  requireAccount,
  requireBytes,
  requireBytesUpTo,
  requirePattern,
  toUnixSeconds,
  trustRef,
  TTL,
} from './common';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from './proof';
import { consume, requireBudget } from './rateLimit';

export const CHALLENGE_PURPOSES = ['activation', 'recovery_registration'] as const;
export type ChallengePurpose = (typeof CHALLENGE_PURPOSES)[number];

export interface IssuedChallenge {
  readonly challengeId: string;
  /** Base64 of 32 random bytes. */
  readonly challenge: string;
  readonly expiresAtMillis: number;
  /** The value signed into statements (whole seconds). */
  readonly expiresAtUnix: number;
}

export const keyIndexId = (deviceSignatureKey: Buffer): string =>
  createHash('sha256').update(deviceSignatureKey).digest('hex');

/** Counts a failed verification toward the account's failure budget. */
export async function recordFailure(db: Firestore, accountId: string, now: Date): Promise<void> {
  try {
    await consume(db, accountId, 'verificationFailure', now);
  } catch (error) {
    if (!(error instanceof DeviceError)) throw error;
  }
}

/**
 * `null` when the record is a live pending device; otherwise the failure.
 * Callers lazily expire stale pending records (the cleanup job does too).
 */
export function pendingFailure(device: DocumentSnapshot, now: Date): DeviceFailure | null {
  if (!device.exists) return 'device_not_found';
  if (device.get('status') !== 'pending') return 'device_not_pending';
  if (device.get('schemaVersion') !== DEVICE_SCHEMA_VERSION) return 'certificate_invalid';
  const expiresAt = device.get('expiresAt') as unknown;
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'device_expired';
  return null;
}

/** Creates the caller's `pending` record after verifying its certificate. */
export async function registerDevice(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<{ status: 'pending'; expiresAtMillis: number }> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const platform = args.platform;
  if (typeof platform !== 'string' || !(PLATFORMS as readonly string[]).includes(platform)) {
    throw new DeviceError('invalid_argument');
  }
  const certificate = requireBytesUpTo(args.certificate, MAX_CERTIFICATE_BYTES);
  let deviceSignatureKey: Buffer;
  try {
    const cert = verifyCertificate(certificate);
    if (cert.deviceId.toString('hex') !== deviceId) throw new DeviceError('certificate_invalid');
    deviceSignatureKey = cert.deviceSignatureKey;
  } catch (error) {
    if (error instanceof InvalidCertificateError) throw new DeviceError('certificate_invalid');
    throw error;
  }
  await consume(db, accountId, 'register', now);

  const devices = db.collection(Collections.users).doc(accountId).collection(Collections.devices);
  const pending = await devices.where('status', '==', 'pending').count().get();
  if (pending.data().count >= MAX_PENDING_DEVICES) throw new DeviceError('too_many_pending');

  const expiresAt = new Date(now.getTime() + TTL.pendingDeviceMs);
  await db.runTransaction(async (tx) => {
    const ref = deviceRef(db, accountId, deviceId);
    const [existing, idIndex, keyIndex] = await Promise.all([
      tx.get(ref),
      tx.get(db.collection(Collections.deviceIdIndex).doc(deviceId)),
      tx.get(db.collection(Collections.deviceKeyIndex).doc(keyIndexId(deviceSignatureKey))),
    ]);
    // An existing record (even revoked) or an activated ID/key is never reused.
    if (existing.exists || idIndex.exists || keyIndex.exists) throw new DeviceError('duplicate_device');
    tx.create(ref, {
      schemaVersion: DEVICE_SCHEMA_VERSION,
      status: 'pending',
      platform,
      certificate,
      ciphersuite: 1,
      implementation: 'openmls/0.9.1',
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(expiresAt),
    });
  });
  return { status: 'pending', expiresAtMillis: expiresAt.getTime() };
}

/**
 * Issues a single-use challenge. `activation`: the caller's pending device,
 * only while the account has no trusted device yet (otherwise
 * `approval_required`, so callers switch to the approval flow).
 * `recovery_registration`: the caller's active device.
 */
export async function issueDeviceChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const purpose = (args.purpose ?? 'activation') as unknown;
  if (typeof purpose !== 'string' || !(CHALLENGE_PURPOSES as readonly string[]).includes(purpose)) {
    throw new DeviceError('invalid_argument');
  }
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'challenge', now);

  const [device, trust] = await Promise.all([deviceRef(db, accountId, deviceId).get(), trustRef(db, accountId).get()]);
  if (purpose === 'activation') {
    const failure = pendingFailure(device, now);
    if (failure === 'device_expired') await device.ref.update({ status: 'expired' });
    if (failure !== null) throw new DeviceError(failure);
    if (trust.exists) throw new DeviceError('approval_required');
  } else {
    if (!device.exists) throw new DeviceError('device_not_found');
    if (device.get('status') !== 'active') throw new DeviceError('approver_not_trusted');
  }

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.challengeMs);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose,
    challenge,
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  return {
    challengeId,
    challenge: challenge.toString('base64'),
    expiresAtMillis: expiresAtUnix * 1000,
    expiresAtUnix,
  };
}

/** Checks a challenge snapshot against caller, device, purpose and clock. */
export function challengeFailure(
  snap: DocumentSnapshot,
  accountId: string,
  deviceId: string,
  purpose: ChallengePurpose,
  now: Date,
): DeviceFailure | null {
  if (!snap.exists) return 'challenge_invalid';
  if (snap.get('accountId') !== accountId || snap.get('deviceId') !== deviceId || snap.get('purpose') !== purpose) {
    return 'challenge_invalid';
  }
  const expiresAt = snap.get('expiresAt') as unknown;
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'challenge_expired';
  return null;
}

/**
 * BOOTSTRAP: activates the account's first device after verifying its proof
 * of possession, and marks the account's trust as initialized (forever). If
 * the account already has (or ever had) a trusted device: `approval_required`.
 * The challenge is consumed by the first attempt whatever its outcome.
 */
export async function activateDevice(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const proof = requireBytes(args.proof, PROOF_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const devRef = deviceRef(db, accountId, deviceId);
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const [challengeSnap, deviceSnap, trust] = await Promise.all([
      tx.get(challengeRef),
      tx.get(devRef),
      tx.get(trustRef(db, accountId)),
    ]);
    if (!challengeSnap.exists) return 'challenge_invalid';

    let outcome: DeviceFailure | null =
      challengeFailure(challengeSnap, accountId, deviceId, 'activation', now) ?? pendingFailure(deviceSnap, now);
    if (outcome === null && trust.exists) outcome = 'approval_required';

    let keyId: string | undefined;
    if (outcome === null) {
      try {
        const cert = verifyDeviceProof(
          ProofPurpose.activation,
          accountId,
          Buffer.from(deviceSnap.get('certificate') as Uint8Array),
          Buffer.from(challengeSnap.get('challenge') as Uint8Array),
          proof,
        );
        if (cert.deviceId.toString('hex') !== deviceId) outcome = 'certificate_invalid';
        else keyId = keyIndexId(cert.deviceSignatureKey);
      } catch (error) {
        if (error instanceof InvalidCertificateError) outcome = 'certificate_invalid';
        else if (error instanceof InvalidProofError) outcome = 'proof_invalid';
        else throw error;
      }
    }
    const idIndexRef = db.collection(Collections.deviceIdIndex).doc(deviceId);
    const keyIndexRef = keyId === undefined ? undefined : db.collection(Collections.deviceKeyIndex).doc(keyId);
    if (outcome === null && keyIndexRef !== undefined) {
      const [idIndex, keyIndex] = await Promise.all([tx.get(idIndexRef), tx.get(keyIndexRef)]);
      if (idIndex.exists || keyIndex.exists) outcome = 'duplicate_device';
    }

    tx.delete(challengeRef);
    if (outcome === 'device_expired') tx.update(devRef, { status: 'expired' });
    if (outcome !== null || keyIndexRef === undefined) return outcome;
    tx.create(trustRef(db, accountId), { initializedAt: FieldValue.serverTimestamp(), firstDeviceId: deviceId });
    tx.create(idIndexRef, { accountId });
    tx.create(keyIndexRef, { accountId, deviceId });
    tx.update(devRef, {
      status: 'active',
      activatedAt: FieldValue.serverTimestamp(),
      activationMethod: 'first_device',
      expiresAt: FieldValue.delete(),
    });
    return null;
  });

  if (failure !== null) {
    if (failure === 'proof_invalid' || failure === 'certificate_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}
