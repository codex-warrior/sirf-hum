/**
 * Sirf Hum Cloud Functions entrypoint.
 *
 * Functions are the trusted server: they mint LiveKit tokens, enforce
 * pairing invariants, and fan out privacy-safe notifications. They must
 * never require plaintext private content (docs/security/E2EE-REQUIREMENTS.md).
 *
 * Functions are added in the phase that owns them. Device trust (Prompts
 * 07–08, docs/security/DEVICE-IDENTITY.md): registration, first-device
 * bootstrap, approval by a trusted device, recovery key, scheduled cleanup.
 * Deploying needs the Blaze plan (D-025); until then they run only in the
 * emulator.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { onInit } from 'firebase-functions/v2/core';
import { HttpsError, onCall, type FunctionsErrorCode } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { defineString } from 'firebase-functions/params';
import { setGlobalOptions } from 'firebase-functions/v2';
import {
  assertProjectMatches,
  parseEnvironment,
  REGION,
} from './config/environment';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { cleanupExpired } from './device/cleanup';
import { DeviceError, type DeviceFailure } from './device/common';
import { activateDevice as activate, issueDeviceChallenge as issueChallenge, registerDevice as register } from './device/registration';
import { cancelIdentityReset as cancelReset, completeIdentityReset as completeReset, requestIdentityReset as requestReset } from './device/reset';
import { revokeDevice as revoke } from './device/revocation';
import {
  approveDevice as approve,
  listDeviceApprovalRequests as listRequests,
  proveDeviceEnrollment as proveEnrollment,
  recoverDevice as recover,
  registerRecoveryKey as registerRecovery,
  rejectDeviceApproval as reject,
  requestDeviceApproval as requestApproval,
} from './device/trust';

const shEnv = defineString('SH_ENV');

setGlobalOptions({
  region: REGION,
  // Cost guardrail against runaway scaling; raise per function as needed.
  maxInstances: 10,
});

// Runs once per instance at cold start (not during deploy analysis).
onInit(() => {
  assertProjectMatches(parseEnvironment(shEnv.value()), process.env.GCLOUD_PROJECT);
});

initializeApp();

const FAILURE_CODES: Record<DeviceFailure, FunctionsErrorCode> = {
  invalid_argument: 'invalid-argument',
  unauthenticated: 'unauthenticated',
  device_not_found: 'not-found',
  device_not_pending: 'failed-precondition',
  device_expired: 'failed-precondition',
  challenge_invalid: 'permission-denied',
  challenge_expired: 'deadline-exceeded',
  proof_invalid: 'permission-denied',
  certificate_invalid: 'invalid-argument',
  duplicate_device: 'already-exists',
  too_many_pending: 'resource-exhausted',
  approval_required: 'failed-precondition',
  request_invalid: 'permission-denied',
  request_expired: 'deadline-exceeded',
  approver_not_trusted: 'permission-denied',
  approval_invalid: 'permission-denied',
  recovery_unavailable: 'failed-precondition',
  recovery_invalid: 'permission-denied',
  revocation_invalid: 'permission-denied',
  reset_unavailable: 'failed-precondition',
  reset_not_ready: 'failed-precondition',
  rate_limited: 'resource-exhausted',
};

/** Maps domain failures to callable errors carrying only the category. */
async function guarded<T>(event: string, run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (error) {
    if (error instanceof DeviceError) {
      // Category only: never challenges, proofs, signatures, keys or IDs.
      logger.info(event, { outcome: error.failure });
      throw new HttpsError(FAILURE_CODES[error.failure], error.failure);
    }
    logger.error(event, { outcome: 'internal' });
    throw new HttpsError('internal', 'internal');
  }
}

// App Check is defence in depth (FIREBASE-ARCHITECTURE.md), never the
// authorization: auth + signatures by trusted keys are.
const deviceCallOptions = { enforceAppCheck: true } as const;

const callable = <T>(event: string, run: (uid: string | undefined, data: unknown, now: Date) => Promise<T>) =>
  onCall(deviceCallOptions, (request) => guarded(event, () => run(request.auth?.uid, request.data, new Date())));

const done = { ok: true } as const;

export const registerDevice = callable('device_registered', (uid, data, now) => register(getFirestore(), uid, data, now));

export const issueDeviceChallenge = callable('device_challenge_issued', (uid, data, now) =>
  issueChallenge(getFirestore(), uid, data, now),
);

/** First device of an account only (bootstrap); later devices need approval. */
export const activateDevice = callable('device_activation', async (uid, data, now) => {
  await activate(getFirestore(), uid, data, now);
  return { status: 'active' as const };
});

export const requestDeviceApproval = callable('device_approval_requested', (uid, data, now) =>
  requestApproval(getFirestore(), uid, data, now),
);

export const proveDeviceEnrollment = callable('device_enrollment_proven', async (uid, data, now) => {
  await proveEnrollment(getFirestore(), uid, data, now);
  return done;
});

export const listDeviceApprovalRequests = callable('device_approval_listed', (uid, _data, now) =>
  listRequests(getFirestore(), uid, now),
);

export const approveDevice = callable('device_approved', async (uid, data, now) => {
  await approve(getFirestore(), uid, data, now);
  return done;
});

export const rejectDeviceApproval = callable('device_approval_rejected', async (uid, data, now) => {
  await reject(getFirestore(), uid, data, now);
  return done;
});

export const registerRecoveryKey = callable('recovery_key_registered', async (uid, data, now) => {
  await registerRecovery(getFirestore(), uid, data, now);
  return done;
});

export const recoverDevice = callable('device_recovered', async (uid, data, now) => {
  await recover(getFirestore(), uid, data, now);
  return done;
});

/** Signed revocation by an active device of the account (D-081). */
export const revokeDevice = callable('device_revoked', async (uid, data, now) => {
  await revoke(getFirestore(), uid, data, now);
  return done;
});

/** Identity reset (D-082): delayed, cancellable by any trusted device. */
export const requestIdentityReset = callable('identity_reset_requested', (uid, data, now) =>
  requestReset(getFirestore(), uid, data, now),
);

export const cancelIdentityReset = callable('identity_reset_cancelled', async (uid, data, now) => {
  await cancelReset(getFirestore(), uid, data, now);
  return done;
});

export const completeIdentityReset = callable('identity_reset_completed', (uid, data, now) =>
  completeReset(getFirestore(), uid, data, now),
);

/** Needs Cloud Scheduler (Blaze, D-025). Lazy expiry works without it. */
export const cleanupExpiredDeviceRecords = onSchedule({ schedule: 'every 24 hours', timeZone: 'Etc/UTC' }, async () => {
  const result = await cleanupExpired(getFirestore(), new Date());
  logger.info('device_cleanup', { ...result });
});
