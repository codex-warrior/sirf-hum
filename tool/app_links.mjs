#!/usr/bin/env node
// Prints the Digital Asset Links statement (assetlinks.json) for one
// environment's Hosting domain, so Android verifies the email sign-in App
// Link (D-138, D-148). Firebase Hosting does not generate it from the
// fingerprints registered on the Firebase Android app (checked on staging,
// Prompt 19), so tool/deploy.sh writes this into the web build and
// firebase.json serves it at /.well-known/assetlinks.json.
//
//   node tool/app_links.mjs staging
//
// Fingerprints are of PUBLIC signing certificates. An environment without
// a registered release certificate gets an empty list: no app may claim its
// links. Production stays empty until Play App Signing exists (D-143).
import { pathToFileURL } from 'node:url';

export const APP_LINKS = {
  development: { packageName: 'com.sirfhum.app.dev', sha256: [] },
  staging: {
    packageName: 'com.sirfhum.app.staging',
    // Staging signing key (docs/STAGING-BETA.md; staging-build.yml checks it).
    sha256: ['E7:C8:8D:35:F7:C9:F5:20:93:A7:CA:75:8F:F3:20:48:04:60:F6:39:49:9F:9D:B3:D4:E2:55:10:95:A4:BB:C7'],
  },
  production: { packageName: 'com.sirfhum.app', sha256: [] },
};

export function assetLinks(env) {
  const entry = APP_LINKS[env];
  if (!entry) throw new Error(`unknown environment "${env}"`);
  if (entry.sha256.length === 0) return [];
  return [
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: entry.packageName,
        sha256_cert_fingerprints: entry.sha256,
      },
    },
  ];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const env = process.argv[2];
  if (!APP_LINKS[env]) {
    console.error(`usage: app_links.mjs ${Object.keys(APP_LINKS).join('|')}`);
    process.exit(2);
  }
  process.stdout.write(`${JSON.stringify(assetLinks(env), null, 2)}\n`);
}
