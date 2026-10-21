// Pins the gates of .github/workflows/production-build.yml (D-150, D-137,
// D-143), so none is dropped without a failing test. Run:
//   node --test tool/test_production_build.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const production = read('../.github/workflows/production-build.yml');
const staging = read('../.github/workflows/staging-build.yml');
// Comments say what is forbidden; only the YAML itself is checked.
const code = production.split('\n').filter((l) => !l.trimStart().startsWith('#')).join('\n');

test('manual only, from main, with the typed confirmation', () => {
  assert.match(code, /^on:\n  workflow_dispatch:\n/m);
  assert.doesNotMatch(code, /^\s+(push|pull_request|schedule|workflow_run):/m);
  assert.match(code, /"\$REF" != "refs\/heads\/main"/);
  assert.match(code, /"\$CONFIRM" != "sirf-hum-prod"/);
  assert.match(code, /CONFIRM: \$\{\{ inputs\.confirm \}\}/);
});

test('bound to the production environment', () => {
  assert.match(code, /^    environment: production$/m);
});

test('waits for the launch gate (D-137)', () => {
  assert.match(code, /launch_gate\.json"\)\.productionTraffic/);
  assert.match(code, /"\$gate" != "open"/);
});

test('production config only, attestation App Check, never edited (D-147 is staging only)', () => {
  assert.match(code, /node tool\/check_env_config\.mjs production config\/env\/production\.json/);
  assert.match(code, /"\$provider" == "attestation"/);
  assert.doesNotMatch(code, /SH_APPCHECK_PROVIDER\s*=\s*"debug"|c\.SH_APPCHECK_PROVIDER=/);
  assert.doesNotMatch(code, /--flavor (staging|development)/);
});

test('never debug-signed and never the staging key (D-143)', () => {
  assert.doesNotMatch(code, /SH_ALLOW_DEBUG_SIGNED_RELEASE/);
  assert.match(code, /vars\.PRODUCTION_CERT_SHA256/);
  const stagingCert = staging.match(/STAGING_CERT_SHA256: ([0-9a-f]{64})/)[1];
  assert.equal(code.match(/STAGING_CERT_SHA256: ([0-9a-f]{64})/)[1], stagingCert);
  assert.match(code, /the staging key must never sign production/);
  assert.match(code, /APK carries the staging certificate/);
});

test('verifies only production identifiers are embedded', () => {
  assert.match(code, /1:244475624083:android:/);
  assert.match(code, /for number in 203770631547 627383930881/);
});

test('uploads nowhere but a short-lived workflow artifact', () => {
  assert.doesNotMatch(code, /upload-google-play|play-publisher|firebase appdistribution|gcloud|firebase deploy/i);
  assert.match(code, /retention-days: 3/);
  for (const uses of code.matchAll(/uses: ([^\s]+)/g)) {
    assert.match(uses[1], /@[0-9a-f]{40}$/, `${uses[1]} is pinned to a commit`);
  }
});
