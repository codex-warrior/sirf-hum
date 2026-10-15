/**
 * Sirf Hum Cloud Functions entrypoint.
 *
 * Functions are the trusted server: they mint LiveKit tokens, enforce
 * pairing invariants, and fan out privacy-safe notifications. They must
 * never require plaintext private content (docs/security/E2EE-REQUIREMENTS.md).
 *
 * No functions are exported yet; each is added in the phase that owns it.
 */
import { onInit } from 'firebase-functions/v2/core';
import { defineString } from 'firebase-functions/params';
import { setGlobalOptions } from 'firebase-functions/v2';
import {
  assertProjectMatches,
  parseEnvironment,
  REGION,
} from './config/environment';

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
