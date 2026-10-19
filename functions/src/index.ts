/**
 * Sirf Hum Cloud Functions entrypoint.
 *
 * Functions are the trusted server: they mint LiveKit tokens, enforce
 * pairing invariants, and fan out privacy-safe notifications. They must
 * never require plaintext private content (docs/security/E2EE-REQUIREMENTS.md).
 *
 * Functions are added in the phase that owns them. Device registration
 * (Prompt 07, docs/security/DEVICE-IDENTITY.md): issueDeviceChallenge,
 * activateDevice. Deploying needs the Blaze plan (D-025); until then they run
 * only in the emulator.
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
import {
  activateDevice as activate,
  issueActivationChallenge,
  RegistrationError,
  type RegistrationFailure,
} from './device/registration';

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

const FAILURE_CODES: Record<RegistrationFailure, FunctionsErrorCode> = {
  invalid_argument: 'invalid-argument',
  unauthenticated: 'unauthenticated',
  device_not_found: 'not-found',
  device_not_pending: 'failed-precondition',
  challenge_invalid: 'permission-denied',
  challenge_expired: 'deadline-exceeded',
  proof_invalid: 'permission-denied',
  certificate_invalid: 'invalid-argument',
  duplicate_device: 'already-exists',
};

/** Maps domain failures to callable errors carrying only the category. */
async function guarded<T>(event: string, run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (error) {
    if (error instanceof RegistrationError) {
      // Category only: never challenges, proofs, certificates or IDs.
      logger.info(event, { outcome: error.failure });
      throw new HttpsError(FAILURE_CODES[error.failure], error.failure);
    }
    logger.error(event, { outcome: 'internal' });
    throw new HttpsError('internal', 'internal');
  }
}

// App Check is defence in depth (FIREBASE-ARCHITECTURE.md), never the
// authorization: auth + proof of possession are.
const deviceCallOptions = { enforceAppCheck: true } as const;

export const issueDeviceChallenge = onCall(deviceCallOptions, (request) =>
  guarded('device_challenge_issued', () =>
    issueActivationChallenge(getFirestore(), request.auth?.uid, request.data, new Date()),
  ),
);

export const activateDevice = onCall(deviceCallOptions, (request) =>
  guarded('device_activation', async () => {
    await activate(getFirestore(), request.auth?.uid, request.data, new Date());
    return { status: 'active' as const };
  }),
);
