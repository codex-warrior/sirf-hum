#!/usr/bin/env node
// Refuses a client config that belongs to another environment, before a
// build is made from it or handed to a tester (Prompt 19,
// docs/STAGING-BETA.md). The runtime guard (lib/app/environment_guard.dart)
// refuses such a build at start-up; this catches it earlier and also
// catches a config that mixes identifiers of two projects (e.g. a staging
// project ID with a production Android app ID), which the runtime guard
// does not compare.
//
//   node tool/check_env_config.mjs staging [config/env/staging.json]
//
// Values are public client identifiers; the script prints only key names.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Project IDs and numbers (the number prefixes every app ID and is the
// messaging sender ID). Public identifiers, see docs/STAGING-BETA.md §1.
export const PROJECTS = {
  development: { id: 'sirf-hum-dev', number: '627383930881' },
  staging: { id: 'sirf-hum-staging', number: '203770631547' },
  production: { id: 'sirf-hum-prod', number: '244475624083' },
};

export function isGoogleClientOf(project, clientId) {
  return clientId.startsWith(`${project.number}-`) && clientId.endsWith('.apps.googleusercontent.com');
}

/** Returns the list of problems (empty when the config is valid for `env`). */
export function checkEnvConfig(env, config) {
  const own = PROJECTS[env];
  if (!own) return [`unknown environment "${env}"`];
  if (config === null || typeof config !== 'object' || Array.isArray(config)) {
    return ['config is not a JSON object'];
  }
  const problems = [];
  if (config.SH_ENV !== env) problems.push('SH_ENV does not match the environment');
  if (config.SH_FIREBASE_PROJECT_ID !== own.id) {
    problems.push('SH_FIREBASE_PROJECT_ID is not this environment\'s project');
  }
  if (config.SH_FIREBASE_MESSAGING_SENDER_ID !== own.number) {
    problems.push('SH_FIREBASE_MESSAGING_SENDER_ID is not this environment\'s project number');
  }
  for (const [key, value] of Object.entries(config)) {
    if (/^SH_FIREBASE_[A-Z]+_APP_ID$/.test(key) && !String(value).startsWith(`1:${own.number}:`)) {
      problems.push(`${key} does not belong to this environment's project`);
    }
    for (const [otherEnv, other] of Object.entries(PROJECTS)) {
      if (otherEnv === env) continue;
      const text = String(value);
      // Word-bounded: 'sirf-hum-dev' must not match inside a longer ID.
      if (new RegExp(`(^|[^a-z0-9-])${other.id}($|[^a-z0-9-])`).test(text) || text.includes(other.number)) {
        problems.push(`${key} references ${otherEnv}`);
      }
    }
  }
  // Google ID tokens are minted for this OAuth client (D-150): it must be
  // one of this project's (Google prefixes client IDs with the project
  // number). Also checked at start-up (environment_guard.dart).
  const google = config.SH_GOOGLE_SERVER_CLIENT_ID ?? '';
  if (google !== '' && !isGoogleClientOf(own, String(google))) {
    problems.push("SH_GOOGLE_SERVER_CLIENT_ID is not an OAuth client of this environment's project");
  }
  if (env === 'production') {
    // Production never ships the debug provider (also refused at start-up).
    if (config.SH_APPCHECK_PROVIDER === 'debug') {
      problems.push('production must not use the App Check debug provider');
    }
    // The production build offers Google sign-in (D-150).
    if (google === '') problems.push('production requires SH_GOOGLE_SERVER_CLIENT_ID');
  }
  return problems;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [env, path = `config/env/${process.argv[2]}.json`] = process.argv.slice(2);
  if (!PROJECTS[env]) {
    console.error(`usage: check_env_config.mjs ${Object.keys(PROJECTS).join('|')} [path]`);
    process.exit(2);
  }
  let config;
  try {
    config = JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    console.error(`cannot read ${path} as JSON`);
    process.exit(1);
  }
  const problems = checkEnvConfig(env, config);
  if (problems.length > 0) {
    for (const p of problems) console.error(`env config: ${p}`);
    process.exit(1);
  }
  console.log(`env config is ${env}-only`);
}
