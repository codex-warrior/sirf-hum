/**
 * Identity reset (D-082). docs/security/MULTI-DEVICE-TRUST.md §8.
 *
 * For an account that has lost every trusted device AND its recovery key.
 * It does not recover anything: it abandons the old cryptographic identity
 * and lets the account start a NEW one (option C), after a public delay.
 *
 *   requestIdentityReset   signed-in session; starts a 7-day delay
 *   cancelIdentityReset    any ACTIVE device, by a signed statement:
 *                          a trusted device still exists, so the reset is
 *                          refused (protects against a password thief)
 *   completeIdentityReset  signed-in session, only after the delay: every
 *                          pending/active device is revoked (authority
 *                          `identity_reset`), the recovery key is deleted,
 *                          and one new first-device bootstrap is allowed
 *
 * Nothing old is reactivated or decrypted: the new first device creates a
 * new PIK, so partners see a new, unverified identity (pairing phase).
 * Message history is not recoverable. The server never holds keys.
 */
import { FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { InvalidCertificateError } from './certificate';
import {
  Collections,
  DEVICE_ID_PATTERN,
  DeviceError,
  type DeviceFailure,
  deviceRef,
  identityResetDelayMs,
  input,
  RECORD_ID_PATTERN,
  requireAccount,
  requireBytes,
  requirePattern,
  toUnixSeconds,
  trustRef,
} from './common';
import { bumpEpoch } from './epoch';
import { consume, requireBudget } from './rateLimit';
import { challengeFailure, recordFailure } from './registration';
import { InvalidStatementError, SIGNATURE_BYTES, verifyResetCancel } from './statements';

export interface ResetStatus {
  readonly status: 'pending';
  readonly effectiveAtMillis: number;
}

const pendingReset = (trust: FirebaseFirestore.DocumentSnapshot): { effectiveAtMillis: number } | null => {
  const reset = trust.get('reset') as { status?: unknown; effectiveAtMillis?: unknown } | undefined;
  return reset?.status === 'pending' && typeof reset.effectiveAtMillis === 'number'
    ? { effectiveAtMillis: reset.effectiveAtMillis }
    : null;
};

/** Starts (or returns the already pending) reset. */
export async function requestIdentityReset(
  db: Firestore,
  uid: string | undefined,
  _data: unknown,
  now: Date,
): Promise<ResetStatus> {
  const accountId = requireAccount(uid);
  await consume(db, accountId, 'identityReset', now);
  const result = await db.runTransaction(async (tx): Promise<ResetStatus | DeviceFailure> => {
    const trust = await tx.get(trustRef(db, accountId));
    // Nothing to reset before the account ever had a trusted device, or
    // while a completed reset still awaits its new first device.
    if (!trust.exists || trust.get('bootstrapOpen') === true) return 'reset_unavailable';
    const existing = pendingReset(trust);
    if (existing !== null) return { status: 'pending', effectiveAtMillis: existing.effectiveAtMillis };
    const effectiveAtMillis = now.getTime() + identityResetDelayMs();
    bumpEpoch(tx, trust.ref, trust, {
      reset: { status: 'pending', requestedAt: FieldValue.serverTimestamp(), effectiveAtMillis },
    });
    return { status: 'pending', effectiveAtMillis };
  });
  if (typeof result === 'string') throw new DeviceError(result);
  return result;
}

/** An active device refuses the pending reset with a signed statement. */
export async function cancelIdentityReset(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
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
    const state = challengeFailure(challenge, accountId, deviceId, 'reset_cancel', now);
    if (state !== null) return state;
    if (!device.exists || device.get('status') !== 'active') return 'approver_not_trusted';
    if (pendingReset(trust) === null) return 'reset_unavailable';
    try {
      verifyResetCancel(
        accountId,
        Buffer.from(device.get('certificate') as Uint8Array),
        Buffer.from(challenge.get('challenge') as Uint8Array),
        toUnixSeconds((challenge.get('expiresAt') as Timestamp).toMillis()),
        signature,
      );
    } catch (error) {
      if (error instanceof InvalidStatementError || error instanceof InvalidCertificateError) return 'approval_invalid';
      throw error;
    }
    bumpEpoch(tx, trust.ref, trust, {
      reset: FieldValue.delete(),
      lastResetCancelled: { at: FieldValue.serverTimestamp(), byDeviceId: deviceId },
    });
    return null;
  });
  if (failure !== null) {
    if (failure === 'approval_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}

/** After the delay: revoke every live device and open one new bootstrap. */
export async function completeIdentityReset(
  db: Firestore,
  uid: string | undefined,
  _data: unknown,
  now: Date,
): Promise<{ revokedDevices: number }> {
  const accountId = requireAccount(uid);
  await consume(db, accountId, 'identityReset', now);
  const devices = db.collection(Collections.users).doc(accountId).collection(Collections.devices);
  const result = await db.runTransaction(async (tx): Promise<{ revokedDevices: number } | DeviceFailure> => {
    const [trust, live] = await Promise.all([
      tx.get(trustRef(db, accountId)),
      tx.get(devices.where('status', 'in', ['pending', 'active'])),
    ]);
    const reset = pendingReset(trust);
    if (reset === null) return 'reset_unavailable';
    if (now.getTime() < reset.effectiveAtMillis) return 'reset_not_ready';
    const identityEpoch = Number(trust.get('identityEpoch') ?? 0) + 1;
    const epoch = bumpEpoch(tx, trust.ref, trust, {
      reset: { status: 'completed', completedAt: FieldValue.serverTimestamp(), effectiveAtMillis: reset.effectiveAtMillis },
      bootstrapOpen: true,
      identityEpoch,
      recoveryKey: FieldValue.delete(),
    });
    for (const device of live.docs) {
      tx.update(device.ref, {
        status: 'revoked',
        revokedAt: FieldValue.serverTimestamp(),
        revokedReason: 'identity_reset',
        revocation: { protocolVersion: 1, authority: 'identity_reset', identityEpoch },
        revokedEpoch: epoch,
        expiresAt: FieldValue.delete(),
      });
    }
    return { revokedDevices: live.size };
  });
  if (typeof result === 'string') throw new DeviceError(result);
  return result;
}
