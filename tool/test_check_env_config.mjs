// Tests for tool/check_env_config.mjs (Prompt 19). Run: node --test tool/test_check_env_config.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkEnvConfig } from './check_env_config.mjs';

const staging = () => ({
  SH_ENV: 'staging',
  SH_FIREBASE_PROJECT_ID: 'sirf-hum-staging',
  SH_FIREBASE_MESSAGING_SENDER_ID: '203770631547',
  SH_FIREBASE_STORAGE_BUCKET: 'sirf-hum-staging.firebasestorage.app',
  SH_FIREBASE_AUTH_DOMAIN: 'sirf-hum-staging.firebaseapp.com',
  SH_FIREBASE_ANDROID_APP_ID: '1:203770631547:android:aaaa',
  SH_FIREBASE_WEB_APP_ID: '1:203770631547:web:bbbb',
  SH_FIREBASE_ANDROID_API_KEY: 'AIzaFakeKeyForTests',
});

test('a staging-only config passes', () => {
  assert.deepEqual(checkEnvConfig('staging', staging()), []);
});

test('the wrong SH_ENV fails', () => {
  assert.notDeepEqual(checkEnvConfig('staging', { ...staging(), SH_ENV: 'production' }), []);
});

test('a staging config is not a production config', () => {
  assert.notDeepEqual(checkEnvConfig('production', staging()), []);
});

test('a production Android app ID inside a staging config fails', () => {
  const problems = checkEnvConfig('staging', {
    ...staging(),
    SH_FIREBASE_ANDROID_APP_ID: '1:244475624083:android:cccc',
  });
  assert.ok(problems.some((p) => p.includes('SH_FIREBASE_ANDROID_APP_ID')));
  assert.ok(problems.some((p) => p.includes('production')));
});

test('a production bucket inside a staging config fails', () => {
  const problems = checkEnvConfig('staging', {
    ...staging(),
    SH_FIREBASE_STORAGE_BUCKET: 'sirf-hum-prod.firebasestorage.app',
  });
  assert.ok(problems.some((p) => p === 'SH_FIREBASE_STORAGE_BUCKET references production'));
});

test('the wrong sender ID fails', () => {
  assert.notDeepEqual(
    checkEnvConfig('staging', { ...staging(), SH_FIREBASE_MESSAGING_SENDER_ID: '627383930881' }),
    [],
  );
});

test('production refuses the App Check debug provider', () => {
  const prod = {
    SH_ENV: 'production',
    SH_FIREBASE_PROJECT_ID: 'sirf-hum-prod',
    SH_FIREBASE_MESSAGING_SENDER_ID: '244475624083',
    SH_FIREBASE_ANDROID_APP_ID: '1:244475624083:android:dddd',
  };
  assert.deepEqual(checkEnvConfig('production', prod), []);
  assert.notDeepEqual(checkEnvConfig('production', { ...prod, SH_APPCHECK_PROVIDER: 'debug' }), []);
});

test('non-objects and unknown environments fail', () => {
  assert.notDeepEqual(checkEnvConfig('staging', null), []);
  assert.notDeepEqual(checkEnvConfig('staging', []), []);
  assert.notDeepEqual(checkEnvConfig('qa', staging()), []);
});

test('problems name keys, never values', () => {
  const problems = checkEnvConfig('staging', { ...staging(), SH_FIREBASE_ANDROID_API_KEY: 'sirf-hum-prod' });
  assert.ok(problems.length > 0);
  for (const p of problems) assert.ok(!p.includes('AIza'));
});
