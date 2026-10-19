/**
 * Device registration: challenge issuance and activation (D-069, D-070).
 *
 * Lifecycle (docs/security/DEVICE-IDENTITY.md):
 *   client creates   users/{uid}/devices/{deviceId}  status "pending"   (rules)
 *   server issues    deviceChallenges/{challengeId}  single-use, 5 min  (here)
 *   device signs the challenge with its device key (Rust core, D-070)
 *   server verifies certificate + proof, consumes the challenge, and sets
 *   status "active" (here)
 *
 * Firebase Auth proves only who the *account* is. Activation additionally
 * requires proof of possession of the certified device key, so copied
 * metadata (a certificate, a public key, a device ID) never activates a
 * device. The server never receives private keys.
 *
 * Pure logic over an injected Firestore + clock so it is testable against the
 * emulator; callable wrappers live in ../index.ts.
 */
import { createHash, randomBytes } from 'node:crypto';
import {
  type DocumentReference,
  type DocumentSnapshot,
  FieldValue,
  type Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import { InvalidCertificateError } from './certificate';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from './proof';

export const CHALLENGE_TTL_MS = 5 * 60 * 1000;
export const DEVICE_SCHEMA_VERSION = 1;

export const ACCOUNT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
export const DEVICE_ID_PATTERN = /^[0-9a-f]{32}$/;
const CHALLENGE_ID_PATTERN = /^[0-9a-f]{32}$/;

export const Collections = {
  users: 'users',
  devices: 'devices',
  challenges: 'deviceChallenges',
  deviceIdIndex: 'deviceIdIndex',
  deviceKeyIndex: 'deviceKeyIndex',
} as const;

/** Safe, stable failure categories (no data). Mapped to HttpsError codes. */
export type RegistrationFailure =
  | 'invalid_argument'
  | 'unauthenticated'
  | 'device_not_found'
  | 'device_not_pending'
  | 'challenge_invalid'
  | 'challenge_expired'
  | 'proof_invalid'
  | 'certificate_invalid'
  | 'duplicate_device';

export class RegistrationError extends Error {
  constructor(readonly failure: RegistrationFailure) {
    super(failure);
  }
}

export interface IssuedChallenge {
  readonly challengeId: string;
  /** Base64 of 32 random bytes. */
  readonly challenge: string;
  readonly expiresAtMillis: number;
}

function requireAccount(uid: string | undefined): string {
  if (uid === undefined) throw new RegistrationError('unauthenticated');
  if (!ACCOUNT_ID_PATTERN.test(uid)) throw new RegistrationError('invalid_argument');
  return uid;
}

function requireDeviceId(value: unknown): string {
  if (typeof value !== 'string' || !DEVICE_ID_PATTERN.test(value)) {
    throw new RegistrationError('invalid_argument');
  }
  return value;
}

function deviceRef(db: Firestore, uid: string, deviceId: string) {
  return db.collection(Collections.users).doc(uid).collection(Collections.devices).doc(deviceId);
}

/** Issues a single-use activation challenge for the caller's pending device. */
export async function issueActivationChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const deviceId = requireDeviceId((data as { deviceId?: unknown } | null)?.deviceId);
  const device = await deviceRef(db, accountId, deviceId).get();
  if (!device.exists) throw new RegistrationError('device_not_found');
  if (device.get('status') !== 'pending') throw new RegistrationError('device_not_pending');

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAt = new Date(now.getTime() + CHALLENGE_TTL_MS);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose: ProofPurpose.activation,
    challenge,
    expiresAt: Timestamp.fromDate(expiresAt),
  });
  return {
    challengeId,
    challenge: challenge.toString('base64'),
    expiresAtMillis: expiresAt.getTime(),
  };
}

type Verdict =
  | { failure: RegistrationFailure; deviceSignatureKey?: undefined }
  | { failure: null; deviceSignatureKey: Buffer };

/** All activation checks except uniqueness; reads nothing, writes nothing. */
function verifyActivation(
  accountId: string,
  deviceId: string,
  proof: Buffer,
  challengeSnap: DocumentSnapshot,
  deviceSnap: DocumentSnapshot,
  now: Date,
): Verdict {
  if (
    challengeSnap.get('accountId') !== accountId ||
    challengeSnap.get('deviceId') !== deviceId ||
    challengeSnap.get('purpose') !== ProofPurpose.activation
  ) {
    return { failure: 'challenge_invalid' };
  }
  const expiresAt = challengeSnap.get('expiresAt') as unknown;
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) {
    return { failure: 'challenge_expired' };
  }
  if (!deviceSnap.exists) return { failure: 'device_not_found' };
  if (deviceSnap.get('status') !== 'pending') return { failure: 'device_not_pending' };
  if (deviceSnap.get('schemaVersion') !== DEVICE_SCHEMA_VERSION) {
    return { failure: 'certificate_invalid' };
  }
  const certificate = deviceSnap.get('certificate') as unknown;
  const challenge = challengeSnap.get('challenge') as unknown;
  if (!(certificate instanceof Uint8Array) || !(challenge instanceof Uint8Array)) {
    return { failure: 'certificate_invalid' };
  }
  try {
    const cert = verifyDeviceProof(
      ProofPurpose.activation,
      accountId,
      Buffer.from(certificate),
      Buffer.from(challenge),
      proof,
    );
    // The certificate must certify exactly the device ID it is filed under.
    if (cert.deviceId.toString('hex') !== deviceId) return { failure: 'certificate_invalid' };
    return { failure: null, deviceSignatureKey: cert.deviceSignatureKey };
  } catch (error) {
    if (error instanceof InvalidCertificateError) return { failure: 'certificate_invalid' };
    if (error instanceof InvalidProofError) return { failure: 'proof_invalid' };
    throw error;
  }
}

/**
 * Verifies the proof and activates the device, atomically. The challenge is
 * consumed by the first activation attempt whatever its outcome, so a
 * challenge can never be retried or replayed.
 */
export async function activateDevice(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<void> {
  const accountId = requireAccount(uid);
  const input = (data ?? {}) as { deviceId?: unknown; challengeId?: unknown; proof?: unknown };
  const deviceId = requireDeviceId(input.deviceId);
  if (typeof input.challengeId !== 'string' || !CHALLENGE_ID_PATTERN.test(input.challengeId)) {
    throw new RegistrationError('invalid_argument');
  }
  if (typeof input.proof !== 'string' || input.proof.length > 128) {
    throw new RegistrationError('invalid_argument');
  }
  const proof = Buffer.from(input.proof, 'base64');
  if (proof.length !== PROOF_BYTES) throw new RegistrationError('invalid_argument');

  const challengeRef = db.collection(Collections.challenges).doc(input.challengeId);
  const devRef = deviceRef(db, accountId, deviceId);

  // The transaction returns the failure instead of throwing so the challenge
  // deletion (consumption) commits even when verification fails. Firestore
  // requires every read before any write, so all checks run first.
  const failure = await db.runTransaction(async (tx): Promise<RegistrationFailure | null> => {
    const [challengeSnap, deviceSnap] = await Promise.all([tx.get(challengeRef), tx.get(devRef)]);
    if (!challengeSnap.exists) return 'challenge_invalid';

    const verdict = verifyActivation(accountId, deviceId, proof, challengeSnap, deviceSnap, now);
    let indexes: { idRef: DocumentReference; keyRef: DocumentReference } | undefined;
    let outcome: RegistrationFailure | null = verdict.failure;
    if (verdict.failure === null) {
      // Global uniqueness: a device ID or device key can be activated once,
      // ever (revoked ones stay indexed), so copied public material can never
      // become a second active device.
      indexes = {
        idRef: db.collection(Collections.deviceIdIndex).doc(deviceId),
        keyRef: db
          .collection(Collections.deviceKeyIndex)
          .doc(createHash('sha256').update(verdict.deviceSignatureKey).digest('hex')),
      };
      const [idIndex, keyIndex] = await Promise.all([tx.get(indexes.idRef), tx.get(indexes.keyRef)]);
      if (idIndex.exists || keyIndex.exists) outcome = 'duplicate_device';
    }

    tx.delete(challengeRef);
    if (outcome !== null || indexes === undefined) return outcome;
    tx.create(indexes.idRef, { accountId });
    tx.create(indexes.keyRef, { accountId, deviceId });
    tx.update(devRef, { status: 'active', activatedAt: FieldValue.serverTimestamp() });
    return null;
  });

  if (failure !== null) throw new RegistrationError(failure);
}
