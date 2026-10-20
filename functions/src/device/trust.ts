/**
 * Multi-device trust: approval by a trusted device, and recovery-key
 * recovery (D-075, D-076). docs/security/DEVICE-IDENTITY.md §15–§18.
 *
 * New device B (pending; the account already has trusted devices):
 *   requestDeviceApproval   → single-use request with a 32-byte challenge,
 *                             10-minute server-chosen expiry
 *   proveDeviceEnrollment   → B proves possession of its device key
 *                             (device proof, purpose `enrollment`)
 * Trusted device A (active):
 *   listDeviceApprovalRequests → proven, unexpired requests (public material)
 *   approveDevice           → A's PIK signs the approval statement; the
 *                             server verifies it against A's *stored*
 *                             certificate, A must be active NOW, and B is
 *                             activated atomically
 *   rejectDeviceApproval    → request closed, B `rejected` (terminal)
 * Recovery (no trusted device left):
 *   registerRecoveryKey     → an active device's PIK registers the recovery
 *                             key's PUBLIC half (the server never sees the secret)
 *   recoverDevice           → the recovery key approves proven device B;
 *                             the registered key is consumed (single-use)
 *
 * Every request/challenge is consumed by its first use, success or failure.
 * The server enforces status and expiry; it never holds private keys and
 * cannot sign approvals, so it cannot create trust by itself.
 */
import { randomBytes } from 'node:crypto';
import { type DocumentReference, type DocumentSnapshot, FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { type DeviceCertificate, InvalidCertificateError, verifyCertificate } from './certificate';
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
  trustRef,
  TTL,
} from './common';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from './proof';
import { bumpEpoch } from './epoch';
import { consume, requireBudget } from './rateLimit';
import { activationIndexes, anyIndexTaken, challengeFailure, claimIndexes, pendingFailure, recordFailure } from './registration';
import {
  InvalidStatementError,
  RECOVERY_KEY_BYTES,
  SIGNATURE_BYTES,
  verifyApproval,
  verifyRecoveryApproval,
  verifyRecoveryRegistration,
} from './statements';

const requestRef = (db: Firestore, requestId: string): DocumentReference =>
  db.collection(Collections.approvalRequests).doc(requestId);

export interface ApprovalRequest {
  readonly requestId: string;
  readonly challenge: string;
  readonly expiresAtUnix: number;
}

export interface PendingApproval extends ApprovalRequest {
  readonly deviceId: string;
  readonly platform: string;
  /** Base64; the approver computes the comparison code from it. */
  readonly certificate: string;
}

/** `null` when the request belongs to the caller, is in `state`, and is live. */
function requestFailure(snap: DocumentSnapshot, accountId: string, state: 'open' | 'proven', now: Date): DeviceFailure | null {
  if (!snap.exists || snap.get('accountId') !== accountId || snap.get('status') !== state) return 'request_invalid';
  const expiresAt = snap.get('expiresAt') as unknown;
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'request_expired';
  return null;
}

const expiresAtUnixOf = (snap: DocumentSnapshot): number =>
  toUnixSeconds((snap.get('expiresAt') as Timestamp).toMillis());

/** Opens an approval request for the caller's pending device B. */
export async function requestDeviceApproval(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<ApprovalRequest> {
  const accountId = requireAccount(uid);
  const deviceId = requirePattern(input(data).deviceId, DEVICE_ID_PATTERN);
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'approvalRequest', now);

  const [device, trust, older] = await Promise.all([
    deviceRef(db, accountId, deviceId).get(),
    trustRef(db, accountId).get(),
    db.collection(Collections.approvalRequests).where('accountId', '==', accountId).where('deviceId', '==', deviceId).get(),
  ]);
  const failure = pendingFailure(device, now);
  if (failure === 'device_expired') await device.ref.update({ status: 'expired' });
  if (failure !== null) throw new DeviceError(failure);
  // No trusted device yet: the first device bootstraps instead (registration.ts).
  if (!trust.exists) throw new DeviceError('request_invalid');

  const requestId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.approvalRequestMs);
  const batch = db.batch();
  // One live request per device: a new request supersedes older ones.
  older.docs.forEach((doc) => batch.delete(doc.ref));
  batch.create(requestRef(db, requestId), {
    accountId,
    deviceId,
    challenge,
    status: 'open',
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  await batch.commit();
  return { requestId, challenge: challenge.toString('base64'), expiresAtUnix };
}

/** B proves possession of its device key; only proven requests are shown to approvers. */
export async function proveDeviceEnrollment(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const requestId = requirePattern(args.requestId, RECORD_ID_PATTERN);
  const proof = requireBytes(args.proof, PROOF_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const request = await tx.get(requestRef(db, requestId));
    const requestState = requestFailure(request, accountId, 'open', now);
    if (requestState !== null) {
      if (request.exists && request.get('accountId') === accountId) tx.delete(request.ref);
      return requestState;
    }
    const deviceId = request.get('deviceId') as string;
    const device = await tx.get(deviceRef(db, accountId, deviceId));
    let outcome = pendingFailure(device, now);
    if (outcome === null) {
      try {
        verifyDeviceProof(
          ProofPurpose.enrollment,
          accountId,
          Buffer.from(device.get('certificate') as Uint8Array),
          Buffer.from(request.get('challenge') as Uint8Array),
          proof,
        );
      } catch (error) {
        if (error instanceof InvalidCertificateError) outcome = 'certificate_invalid';
        else if (error instanceof InvalidProofError) outcome = 'proof_invalid';
        else throw error;
      }
    }
    if (outcome !== null) {
      tx.delete(request.ref); // single-use: a failed proof closes the request
      if (outcome === 'device_expired') tx.update(device.ref, { status: 'expired' });
      return outcome;
    }
    tx.update(request.ref, { status: 'proven' });
    return null;
  });
  if (failure !== null) {
    if (failure === 'proof_invalid' || failure === 'certificate_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}

/** Proven, unexpired requests of the caller's account (public material only). */
export async function listDeviceApprovalRequests(db: Firestore, uid: string | undefined, now: Date): Promise<PendingApproval[]> {
  const accountId = requireAccount(uid);
  const requests = await db
    .collection(Collections.approvalRequests)
    .where('accountId', '==', accountId)
    .where('status', '==', 'proven')
    .get();
  const out: PendingApproval[] = [];
  for (const request of requests.docs) {
    if (requestFailure(request, accountId, 'proven', now) !== null) continue;
    const deviceId = request.get('deviceId') as string;
    const device = await deviceRef(db, accountId, deviceId).get();
    if (pendingFailure(device, now) !== null) continue;
    out.push({
      requestId: request.id,
      deviceId,
      platform: device.get('platform') as string,
      certificate: Buffer.from(device.get('certificate') as Uint8Array).toString('base64'),
      challenge: Buffer.from(request.get('challenge') as Uint8Array).toString('base64'),
      expiresAtUnix: expiresAtUnixOf(request),
    });
  }
  return out;
}

interface Activation {
  readonly method: 'approval' | 'recovery';
  readonly approvedBy?: string;
  /**
   * The signed evidence of this activation, kept on the device record so
   * every device can verify the account's trust chain itself (D-084).
   */
  readonly evidence: Record<string, unknown>;
}

/** Statement format version stored with every piece of evidence. */
const EVIDENCE_VERSION = 1;

/**
 * Shared tail of approval and recovery inside one transaction (all reads
 * already done except the uniqueness indexes): checks uniqueness, consumes
 * the request, activates B.
 */
async function activateApproved(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  accountId: string,
  request: DocumentSnapshot,
  device: DocumentSnapshot,
  trust: DocumentSnapshot,
  activation: Activation,
  trustFields: Record<string, unknown> = {},
): Promise<DeviceFailure | null> {
  let cert: DeviceCertificate;
  try {
    cert = verifyCertificate(device.get('certificate') as Uint8Array);
  } catch {
    return 'certificate_invalid';
  }
  const deviceId = device.id;
  // D-122: also refuses a person key any device ever activated with, e.g. a
  // revoked device's retained PIK approved by a device that did not know.
  const indexes = activationIndexes(db, deviceId, cert);
  if (await anyIndexTaken(tx, indexes)) return 'duplicate_device';
  const epoch = bumpEpoch(tx, trust.ref, trust, trustFields);
  claimIndexes(tx, indexes, accountId, deviceId);
  tx.update(device.ref, {
    status: 'active',
    activatedAt: FieldValue.serverTimestamp(),
    activationMethod: activation.method,
    ...(activation.approvedBy === undefined ? {} : { approvedBy: activation.approvedBy }),
    [activation.method]: activation.evidence,
    activatedEpoch: epoch,
    expiresAt: FieldValue.delete(),
  });
  tx.delete(request.ref);
  return null;
}

/** Trusted device A approves proven request → B active. */
export async function approveDevice(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const requestId = requirePattern(args.requestId, RECORD_ID_PATTERN);
  const approverId = requirePattern(args.approverDeviceId, DEVICE_ID_PATTERN);
  const signature = requireBytes(args.signature, SIGNATURE_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const request = await tx.get(requestRef(db, requestId));
    const requestState = requestFailure(request, accountId, 'proven', now);
    if (requestState !== null) {
      if (request.exists && request.get('accountId') === accountId) tx.delete(request.ref);
      return requestState;
    }
    const newId = request.get('deviceId') as string;
    const [device, approver, trust] = await Promise.all([
      tx.get(deviceRef(db, accountId, newId)),
      tx.get(deviceRef(db, accountId, approverId)),
      tx.get(trustRef(db, accountId)),
    ]);
    const close = (outcome: DeviceFailure): DeviceFailure => {
      tx.delete(request.ref);
      return outcome;
    };
    const pending = pendingFailure(device, now);
    if (pending !== null) return close(pending);
    // The approver must be a trusted device of this account at THIS moment:
    // approvals made before a revocation die with the approver.
    if (!approver.exists || approver.get('status') !== 'active' || approverId === newId) {
      return close('approver_not_trusted');
    }
    try {
      verifyApproval(
        accountId,
        Buffer.from(approver.get('certificate') as Uint8Array),
        Buffer.from(device.get('certificate') as Uint8Array),
        Buffer.from(request.get('challenge') as Uint8Array),
        expiresAtUnixOf(request),
        signature,
      );
    } catch (error) {
      if (error instanceof InvalidStatementError || error instanceof InvalidCertificateError) {
        return close('approval_invalid');
      }
      throw error;
    }
    const outcome = await activateApproved(db, tx, accountId, request, device, trust, {
      method: 'approval',
      approvedBy: approverId,
      evidence: {
        protocolVersion: EVIDENCE_VERSION,
        approverDeviceId: approverId,
        approverCertificate: Buffer.from(approver.get('certificate') as Uint8Array),
        challenge: Buffer.from(request.get('challenge') as Uint8Array),
        expiresAtUnix: expiresAtUnixOf(request),
        signature,
      },
    });
    return outcome === null ? null : close(outcome);
  });
  if (failure !== null) {
    if (failure === 'approval_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}

/** Closes a request and rejects its device (terminal). */
export async function rejectDeviceApproval(db: Firestore, uid: string | undefined, data: unknown, _now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const requestId = requirePattern(input(data).requestId, RECORD_ID_PATTERN);
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const request = await tx.get(requestRef(db, requestId));
    if (!request.exists || request.get('accountId') !== accountId) return 'request_invalid';
    const device = await tx.get(deviceRef(db, accountId, request.get('deviceId') as string));
    tx.delete(request.ref);
    if (device.exists && device.get('status') === 'pending') {
      tx.update(device.ref, { status: 'rejected', rejectedAt: FieldValue.serverTimestamp(), expiresAt: FieldValue.delete() });
    }
    return null;
  });
  if (failure !== null) throw new DeviceError(failure);
}

/** An active device registers (or replaces) the account's recovery key. */
export async function registerRecoveryKey(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const recoveryPublicKey = requireBytes(args.recoveryPublicKey, RECOVERY_KEY_BYTES);
  const signature = requireBytes(args.signature, SIGNATURE_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const [challenge, device, trust] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, deviceId)),
      tx.get(trustRef(db, accountId)),
    ]);
    if (!challenge.exists) return 'challenge_invalid';
    tx.delete(challengeRef);
    const state = challengeFailure(challenge, accountId, deviceId, 'recovery_registration', now);
    if (state !== null) return state;
    if (!device.exists || device.get('status') !== 'active' || !trust.exists) return 'approver_not_trusted';
    try {
      verifyRecoveryRegistration(
        accountId,
        Buffer.from(device.get('certificate') as Uint8Array),
        recoveryPublicKey,
        Buffer.from(challenge.get('challenge') as Uint8Array),
        toUnixSeconds((challenge.get('expiresAt') as Timestamp).toMillis()),
        signature,
      );
    } catch (error) {
      if (error instanceof InvalidStatementError || error instanceof InvalidCertificateError) return 'approval_invalid';
      throw error;
    }
    // Keep the registration's signed evidence: recovery activations carry
    // it so peers can verify that a chain device registered this key.
    bumpEpoch(tx, trust.ref, trust, {
      recoveryKey: {
        publicKey: recoveryPublicKey,
        registeredByDeviceId: deviceId,
        registrarCertificate: Buffer.from(device.get('certificate') as Uint8Array),
        challenge: Buffer.from(challenge.get('challenge') as Uint8Array),
        expiresAtUnix: toUnixSeconds((challenge.get('expiresAt') as Timestamp).toMillis()),
        signature,
        registeredAt: FieldValue.serverTimestamp(),
      },
    });
    return null;
  });
  if (failure !== null) {
    if (failure === 'approval_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}

/**
 * The recovery key approves the caller's proven device B. On success the
 * registered key is deleted (single-use: it has now been typed into a new
 * device); the user creates a fresh one from B.
 */
export async function recoverDevice(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const requestId = requirePattern(args.requestId, RECORD_ID_PATTERN);
  const signature = requireBytes(args.signature, SIGNATURE_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'recovery', now);

  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const request = await tx.get(requestRef(db, requestId));
    const requestState = requestFailure(request, accountId, 'proven', now);
    if (requestState !== null) {
      if (request.exists && request.get('accountId') === accountId) tx.delete(request.ref);
      return requestState;
    }
    const [device, trust] = await Promise.all([
      tx.get(deviceRef(db, accountId, request.get('deviceId') as string)),
      tx.get(trustRef(db, accountId)),
    ]);
    const close = (outcome: DeviceFailure): DeviceFailure => {
      tx.delete(request.ref);
      return outcome;
    };
    const pending = pendingFailure(device, now);
    if (pending !== null) return close(pending);
    const recoveryKey = trust.get('recoveryKey.publicKey') as unknown;
    if (!trust.exists || !(recoveryKey instanceof Uint8Array)) return close('recovery_unavailable');
    try {
      verifyRecoveryApproval(
        accountId,
        Buffer.from(recoveryKey),
        Buffer.from(device.get('certificate') as Uint8Array),
        Buffer.from(request.get('challenge') as Uint8Array),
        expiresAtUnixOf(request),
        signature,
      );
    } catch (error) {
      if (error instanceof InvalidStatementError || error instanceof InvalidCertificateError) return close('recovery_invalid');
      throw error;
    }
    const registration = trust.get('recoveryKey') as Record<string, unknown>;
    const outcome = await activateApproved(
      db,
      tx,
      accountId,
      request,
      device,
      trust,
      {
        method: 'recovery',
        evidence: {
          protocolVersion: EVIDENCE_VERSION,
          recoveryPublicKey: Buffer.from(recoveryKey),
          registration: {
            registrarDeviceId: registration.registeredByDeviceId,
            registrarCertificate: registration.registrarCertificate,
            challenge: registration.challenge,
            expiresAtUnix: registration.expiresAtUnix,
            signature: registration.signature,
          },
          challenge: Buffer.from(request.get('challenge') as Uint8Array),
          expiresAtUnix: expiresAtUnixOf(request),
          signature,
        },
      },
      // Single-use: the key is consumed by its first successful recovery.
      { recoveryKey: FieldValue.delete(), lastRecoveryAt: FieldValue.serverTimestamp() },
    );
    if (outcome !== null) return close(outcome);
    return null;
  });
  if (failure !== null) {
    if (failure === 'recovery_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}
