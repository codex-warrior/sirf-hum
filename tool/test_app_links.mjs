// Tests for tool/app_links.mjs (D-148). Run: node --test tool/test_app_links.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { APP_LINKS, assetLinks } from './app_links.mjs';

test('staging delegates its links to the staging app only', () => {
  const links = assetLinks('staging');
  assert.equal(links.length, 1);
  assert.equal(links[0].target.package_name, 'com.sirfhum.app.staging');
  assert.deepEqual(links[0].relation, ['delegate_permission/common.handle_all_urls']);
  for (const fp of links[0].target.sha256_cert_fingerprints) {
    assert.match(fp, /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
  }
});

test('production and development delegate to no app yet', () => {
  assert.deepEqual(assetLinks('production'), []);
  assert.deepEqual(assetLinks('development'), []);
});

test('no environment names another environment\'s package', () => {
  assert.equal(APP_LINKS.production.packageName, 'com.sirfhum.app');
  assert.notEqual(APP_LINKS.staging.packageName, APP_LINKS.production.packageName);
});

test('the staging fingerprint is the one the build workflow verifies', () => {
  const workflow = readFileSync(new URL('../.github/workflows/staging-build.yml', import.meta.url), 'utf8');
  const pinned = workflow.match(/STAGING_CERT_SHA256: ([0-9a-f]{64})/)[1];
  assert.equal(APP_LINKS.staging.sha256[0].replaceAll(':', '').toLowerCase(), pinned);
});

test('unknown environments are refused', () => {
  assert.throws(() => assetLinks('qa'));
});
