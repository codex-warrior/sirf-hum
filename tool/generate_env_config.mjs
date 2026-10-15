#!/usr/bin/env node
// Writes config/env/<environment>.json from the live Firebase project, so no
// one copies keys by hand. Output is git-ignored.
//
//   node tool/generate_env_config.mjs development|staging|production
//
// Requires `firebase login` with access to the project. Values are client
// identifiers (public by design), not secrets. Optional App Check settings
// already present in the target file are preserved.
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECTS = {
  development: { projectId: 'sirf-hum-dev', bundleId: 'com.sirfhum.app.dev' },
  staging: { projectId: 'sirf-hum-staging', bundleId: 'com.sirfhum.app.staging' },
  production: { projectId: 'sirf-hum-prod', bundleId: 'com.sirfhum.app' },
};
const PRESERVED_KEYS = [
  'SH_APPCHECK_PROVIDER',
  'SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY',
  'SH_CRASH_REPORTING',
];

const env = process.argv[2];
const target = PROJECTS[env];
if (!target) {
  console.error(`usage: generate_env_config.mjs ${Object.keys(PROJECTS).join('|')}`);
  process.exit(2);
}
const { projectId, bundleId } = target;

function firebase(args) {
  const out = execSync(`firebase ${args} --project ${projectId} --json`, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const parsed = JSON.parse(out);
  if (parsed.status !== 'success') throw new Error(`firebase ${args} failed`);
  return parsed.result;
}

const apps = firebase('apps:list');
function appFor(platform, predicate = () => true) {
  const matches = apps.filter((a) => a.platform === platform && predicate(a));
  if (matches.length !== 1) {
    throw new Error(`Expected exactly one ${platform} app in ${projectId}, found ${matches.length}.`);
  }
  return matches[0];
}

const web = appFor('WEB');
const android = appFor('ANDROID', (a) => a.namespace === bundleId);
const ios = appFor('IOS', (a) => a.namespace === bundleId);

const webConfig = firebase(`apps:sdkconfig WEB ${web.appId}`).sdkConfig;
const androidFile = JSON.parse(firebase(`apps:sdkconfig ANDROID ${android.appId}`).fileContents);
const androidClient = androidFile.client.find(
  (c) => c.client_info.android_client_info.package_name === bundleId,
);
const iosPlist = firebase(`apps:sdkconfig IOS ${ios.appId}`).fileContents;
const plistValue = (key) => {
  const match = iosPlist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`));
  if (!match) throw new Error(`iOS config is missing ${key}`);
  return match[1];
};

if (webConfig.projectId !== projectId) throw new Error('Project mismatch in web config.');

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const outPath = join(repoRoot, 'config', 'env', `${env}.json`);
const previous = existsSync(outPath) ? JSON.parse(readFileSync(outPath, 'utf8')) : {};

const config = {
  SH_ENV: env,
  SH_FIREBASE_PROJECT_ID: projectId,
  SH_FIREBASE_MESSAGING_SENDER_ID: webConfig.messagingSenderId,
  SH_FIREBASE_STORAGE_BUCKET: webConfig.storageBucket ?? '',
  SH_FIREBASE_AUTH_DOMAIN: webConfig.authDomain ?? '',
  SH_FIREBASE_IOS_BUNDLE_ID: bundleId,
  SH_FIREBASE_ANDROID_APP_ID: androidClient.client_info.mobilesdk_app_id,
  SH_FIREBASE_ANDROID_API_KEY: androidClient.api_key[0].current_key,
  SH_FIREBASE_IOS_APP_ID: plistValue('GOOGLE_APP_ID'),
  SH_FIREBASE_IOS_API_KEY: plistValue('API_KEY'),
  SH_FIREBASE_WEB_APP_ID: webConfig.appId,
  SH_FIREBASE_WEB_API_KEY: webConfig.apiKey,
};
for (const key of PRESERVED_KEYS) {
  if (previous[key] !== undefined) config[key] = previous[key];
}

writeFileSync(outPath, `${JSON.stringify(config, null, 2)}\n`);
console.log(`Wrote ${outPath} for ${projectId} (git-ignored).`);
