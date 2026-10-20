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
 * Notifications (Prompt 11, docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md):
 * signed push-token registration and content-free fan-out triggers.
 * Couple pairing (Prompt 12, docs/security/COUPLE-AND-PAIRING.md): signed,
 * two-consent invitation → acceptance → confirmation.
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
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import {
  onCommitCreated,
  onCoupleChanged,
  onDeviceStatusChanged,
  onMessageCreated,
  onTrustChanged,
  type PushSender,
  type SendResult,
} from './notification/fanout';
import { registerPushToken as registerToken, requestPushTokenChallenge as requestTokenChallenge } from './notification/tokens';
import {
  acceptPairingInvitation as acceptInvitation,
  cancelPairing as cancelPairingStep,
  confirmPairing as confirmPairingStep,
  createPairingInvitation as createInvitation,
  getPairingState as pairingState,
  rejectPairing as rejectPairingStep,
  requestPairingChallenge as requestPairingStepChallenge,
} from './couple/pairing';
import { PairingError, type PairingFailure } from './couple/state';
import { requestCommitChallenge as commitChallenge, submitConversationCommit as submitCommit } from './conversation/commit';
import { recoverConversation as recover17c, requestRecoveryChallenge as recoveryChallenge } from './conversation/recovery';
import { requestUnpairChallenge as unpairChallenge, unpairCouple as unpair } from './couple/unpair';
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
  device_not_active: 'failed-precondition',
  commit_conflict: 'aborted',
  conversation_unavailable: 'not-found',
  conversation_changed: 'aborted',
  couple_unavailable: 'not-found',
};

const PAIRING_FAILURE_CODES: Record<PairingFailure, FunctionsErrorCode> = {
  invitation_invalid: 'not-found',
  pairing_not_found: 'not-found',
  pairing_not_open: 'failed-precondition',
  pairing_expired: 'deadline-exceeded',
  pairing_invalidated: 'aborted',
  pairing_in_progress: 'failed-precondition',
  confirmation_code_invalid: 'permission-denied',
  already_paired: 'already-exists',
  identity_reset_pending: 'failed-precondition',
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
    if (error instanceof PairingError) {
      // Category only: never tokens, confirmation codes or IDs.
      logger.info(event, { outcome: error.failure });
      throw new HttpsError(PAIRING_FAILURE_CODES[error.failure], error.failure);
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

// --------------------------------------- MLS commits (Prompt 17B, D-127)

/**
 * The only way a conversation's epoch moves: a commit authorized by the
 * device key of an active member device. Clients can no longer write
 * commits, Welcomes or the epoch (rules), so a Firebase session alone can
 * never stall a conversation.
 */
export const requestCommitChallenge = callable('commit_challenge_issued', (uid, data, now) =>
  commitChallenge(getFirestore(), uid, data, now),
);

export const submitMlsCommit = callable('commit_submitted', (uid, data, now) =>
  submitCommit(getFirestore(), uid, data, now),
);

// ------------------------------------------------ couple pairing (Prompt 12)

/**
 * Pairing steps (D-101–D-104). Each is signed by an active device of the
 * caller (proof purpose `pairing` = 4). Successful transitions leave a
 * category-only audit line; the pairing record itself keeps the acting
 * device IDs and server timestamps (server-only).
 */
const audited = <T>(event: string, run: (uid: string | undefined, data: unknown, now: Date) => Promise<T>) =>
  callable(event, async (uid, data, now) => {
    const result = await run(uid, data, now);
    logger.info(event, { outcome: 'ok' });
    return result;
  });

export const requestPairingChallenge = callable('pairing_challenge_issued', (uid, data, now) =>
  requestPairingStepChallenge(getFirestore(), uid, data, now),
);

export const createPairingInvitation = audited('pairing_invitation_created', (uid, data, now) =>
  createInvitation(getFirestore(), uid, data, now),
);

export const acceptPairingInvitation = audited('pairing_invitation_accepted', (uid, data, now) =>
  acceptInvitation(getFirestore(), uid, data, now),
);

export const confirmPairing = audited('pairing_confirmed', (uid, data, now) =>
  confirmPairingStep(getFirestore(), uid, data, now),
);

export const rejectPairing = audited('pairing_rejected', async (uid, data, now) => {
  await rejectPairingStep(getFirestore(), uid, data, now);
  return done;
});

export const cancelPairing = audited('pairing_cancelled', async (uid, data, now) => {
  await cancelPairingStep(getFirestore(), uid, data, now);
  return done;
});

export const getPairingState = callable('pairing_state_read', (uid, _data, now) => pairingState(getFirestore(), uid, now));

// ------------------------------- conversation recovery (Prompt 17C, D-135)

/**
 * Retires a stalled conversation and re-provisions a new MLS group for the
 * same couple, after a device-key proof (purpose 7) bound to the
 * conversation, its epoch and the account's trust epoch. The only callable
 * that creates a conversation besides the pairing confirmation, and only
 * for an existing, active couple.
 */
export const requestRecoveryChallenge = callable('recovery_challenge_issued', (uid, data, now) =>
  recoveryChallenge(getFirestore(), uid, data, now),
);

export const recoverConversation = audited('conversation_recovered', (uid, data, now) =>
  recover17c(getFirestore(), uid, data, now),
);

// ------------------------------------------- unpairing (Prompt 17C, D-136)

/** Either partner, unilaterally, from an active device (purpose 8). */
export const requestUnpairChallenge = callable('unpair_challenge_issued', (uid, data, now) =>
  unpairChallenge(getFirestore(), uid, data, now),
);

export const unpairCouple = audited('couple_unpaired', async (uid, data, now) => {
  await unpair(getFirestore(), uid, data, now);
  return done;
});

// ------------------------------------------------ notifications (Prompt 11)

/** Signed push-token registration (D-098): the device key proves it. */
export const requestPushTokenChallenge = callable('push_token_challenge_issued', (uid, data, now) =>
  requestTokenChallenge(getFirestore(), uid, data, now),
);

export const registerPushToken = callable('push_token_registered', async (uid, data, now) => {
  await registerToken(getFirestore(), uid, data, now);
  return done;
});

/** FCM error codes only; never tokens or messages. */
const UNREGISTERED = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);

const fcm: PushSender = async (messages) => {
  const response = await getMessaging().sendEach(messages);
  return response.responses.map((r): SendResult => {
    if (r.success) return 'ok';
    return UNREGISTERED.has(r.error?.code ?? '') ? 'unregistered' : 'failed';
  });
};

// Firestore triggers (Eventarc: Blaze, D-025). Each reads ONLY routing
// fields; the event snapshot also carries ciphertext, which is never read,
// copied or logged. Logs are counts and a kind category.
export const notifyOnMessage = onDocumentCreated('conversations/{conversationId}/messages/{messageId}', async (event) => {
  const doc = event.data;
  if (doc === undefined) return;
  const result = await onMessageCreated(
    getFirestore(),
    fcm,
    event.params.conversationId,
    String(doc.get('senderAccountId')),
    String(doc.get('senderDeviceId')),
    new Date(),
  );
  logger.info('push_fanout', { ...result });
});

export const notifyOnCommit = onDocumentCreated('conversations/{conversationId}/commits/{epoch}', async (event) => {
  const doc = event.data;
  if (doc === undefined) return;
  const result = await onCommitCreated(getFirestore(), fcm, event.params.conversationId, String(doc.get('senderDeviceId')), new Date());
  logger.info('push_fanout', { ...result });
});

/**
 * Identity reset alerts (Prompt 17B, D-132): reads only the reset status of
 * the account trust record; the payload is the constant security alert.
 */
export const notifyOnTrustChange = onDocumentUpdated('accountTrust/{accountId}', async (event) => {
  const change = event.data;
  if (change === undefined) return;
  const result = await onTrustChanged(
    getFirestore(),
    fcm,
    event.params.accountId,
    change.before.get('reset'),
    change.after.get('reset'),
    new Date(),
  );
  logger.info('push_fanout', { ...result });
});

/** Unpairing (D-136): both accounts' devices sync silently. Reads status and members only. */
export const notifyOnCoupleChange = onDocumentUpdated('couples/{coupleId}', async (event) => {
  const change = event.data;
  if (change === undefined) return;
  const result = await onCoupleChanged(getFirestore(), fcm, change.before.get('status'), change.after.get('status'), change.after.get('members'), new Date());
  logger.info('push_fanout', { ...result });
});

/** Revocation-aware: a device leaving `active` loses its token at once. */
export const notifyOnDeviceStatus = onDocumentUpdated('users/{accountId}/devices/{deviceId}', async (event) => {
  const change = event.data;
  if (change === undefined) return;
  const result = await onDeviceStatusChanged(
    getFirestore(),
    fcm,
    event.params.accountId,
    event.params.deviceId,
    change.before.get('status'),
    change.after.get('status'),
    new Date(),
  );
  logger.info('push_fanout', { ...result });
});
