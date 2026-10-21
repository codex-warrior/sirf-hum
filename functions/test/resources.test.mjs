// Resource guardrails for every function (cost and the regional Cloud Run
// CPU quota; Prompt 19). A function that needs more sets it explicitly.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { URL } from 'node:url';

const index = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const globals = index.match(/setGlobalOptions\(\{([^}]*)\}\);/)?.[1] ?? '';

test('global options cap instances and use fractional CPU', () => {
  assert.match(globals, /maxInstances: 10,/);
  assert.match(globals, /cpu: 'gcf_gen1',/);
});

test('no function asks for minimum (always-on) instances', () => {
  assert.doesNotMatch(index, /minInstances/);
});
