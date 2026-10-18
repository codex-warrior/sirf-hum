/**
 * Signed device revocation (D-081). docs/security/MULTI-DEVICE-TRUST.md §6.
 *
 * Authority: an ACTIVE device of the same account (another device, or the
 * device itself) signs a revocation statement with its PIK over a
 * single-use server challenge (the revocation's unique ID). The server
 * checks the revoker is active NOW, the target is pending or active, and the
 * signature against both STORED certificates; then marks the target revoked
 * and keeps the signed statement on its record, so the revocation is
 * auditable and peers can verify it themselves (lineage, D-084).
 *
 * A signed-in session alone can no longer revoke (Prompt 08's unsigned
 * owner revocation, D-080, is superseded): nobody without a trusted
 * device's key can manufacture a revocation. Losing every device is handled
 * by recovery or by the delayed identity reset (D-082).
 */
import { FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { InvalidCertificateError } from './certificate';
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
} from './common';
import { bumpEpoch } from './epoch';
import { consume, requireBudget } from './rateLimit';
import { challengeFailure, recordFailure } from './registration';
import { InvalidStatementError, REVOCATION_REASONS, RevocationReason, SIGNATURE_BYTES, verifyRevocation } from './statements';

const REASON_NAMES: Record<number, string> = {
  [RevocationReason.removed]: 'removed',
  [RevocationReason.lost]: 'lost',
  [RevocationReason.stolen]: 'stolen',
  [RevocationReason.compromised]: 'compromised',
};

export async function revokeDevice(db: Firestore, uid: string | undefined, data: unknown, now: Date): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const revokerId = requirePattern(args.revokerDeviceId, DEVICE_ID_PATTERN);
  const targetId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const signature = requireBytes(args.signature, SIGNATURE_BYTES);
  const reason = args.reason;
  if (typeof reason !== 'number' || !REVOCATION_REASONS.includes(reason)) throw new DeviceError('invalid_argument');
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'revocation', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const [challenge, revoker, target, trust] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, revokerId)),
      tx.get(deviceRef(db, accountId, targetId)),
      tx.get(trustRef(db, accountId)),
    ]);
    if (!challenge.exists) return 'challenge_invalid';
    tx.delete(challengeRef); // single-use whatever the outcome
    const state = challengeFailure(challenge, accountId, revokerId, 'revocation', now);
    if (state !== null) return state;
    if (!revoker.exists || revoker.get('status') !== 'active') return 'approver_not_trusted';
    if (!target.exists) return 'device_not_found';
    const targetStatus = target.get('status') as unknown;
    if (targetStatus !== 'pending' && targetStatus !== 'active') return 'device_not_pending';
    const expiresAtUnix = toUnixSeconds((challenge.get('expiresAt') as Timestamp).toMillis());
    const revokerCertificate = Buffer.from(revoker.get('certificate') as Uint8Array);
    const challengeBytes = Buffer.from(challenge.get('challenge') as Uint8Array);
    try {
      verifyRevocation(
        accountId,
        revokerCertificate,
        Buffer.from(target.get('certificate') as Uint8Array),
        reason,
        challengeBytes,
        expiresAtUnix,
        signature,
      );
    } catch (error) {
      if (error instanceof InvalidStatementError || error instanceof InvalidCertificateError) {
        return 'revocation_invalid';
      }
      throw error;
    }
    const epoch = bumpEpoch(tx, trust.ref, trust);
    tx.update(target.ref, {
      status: 'revoked',
      revokedAt: FieldValue.serverTimestamp(),
      revokedReason: REASON_NAMES[reason],
      revocation: {
        protocolVersion: 1,
        authority: 'device',
        revokerDeviceId: revokerId,
        revokerCertificate,
        reason,
        challenge: challengeBytes,
        expiresAtUnix,
        signature,
      },
      revokedEpoch: epoch,
      expiresAt: FieldValue.delete(),
    });
    return null;
  });
  if (failure !== null) {
    if (failure === 'revocation_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}
