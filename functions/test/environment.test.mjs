// Runs against the compiled output: `npm run build` first (`npm run check`).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import envModule from '../lib/config/environment.js';

const { assertProjectMatches, parseEnvironment, REGION } = envModule;

test('region is asia-south1', () => {
  assert.equal(REGION, 'asia-south1');
});

test('parses only the three known environments', () => {
  for (const env of ['development', 'staging', 'production']) {
    assert.equal(parseEnvironment(env), env);
  }
  for (const bad of [undefined, '', 'prod', 'Production']) {
    assert.throws(() => parseEnvironment(bad));
  }
});

test('each environment may only run in its own project', () => {
  assertProjectMatches('development', 'sirf-hum-dev');
  assertProjectMatches('staging', 'sirf-hum-staging');
  assertProjectMatches('production', 'sirf-hum-prod');
  assert.throws(() => assertProjectMatches('development', 'sirf-hum-prod'));
  assert.throws(() => assertProjectMatches('production', 'sirf-hum-dev'));
  assert.throws(() => assertProjectMatches('staging', undefined));
});

test('emulator demo projects are always allowed', () => {
  assertProjectMatches('production', 'demo-sirf-hum');
});
