// Prompt 18 (D-139): every client-callable endpoint enforces App Check.
// App Check is defence in depth, never the authorization (device proofs
// are), but a callable added without it would silently accept requests
// from any script once deployed. Static, because the v2 endpoint metadata
// does not carry `enforceAppCheck`.
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, test } from 'node:test';
import { fileURLToPath, URL } from 'node:url';

const srcDir = fileURLToPath(new URL('../src/', import.meta.url));
const index = readFileSync(join(srcDir, 'index.ts'), 'utf8');

function sources(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? sources(path) : path.endsWith('.ts') ? [path] : [];
  });
}

describe('App Check on callables (D-139)', () => {
  test('the one onCall wrapper enforces App Check', () => {
    assert.match(index, /const deviceCallOptions = \{ enforceAppCheck: true \} as const;/);
    const calls = [...index.matchAll(/\bonCall\(/g)];
    assert.equal(calls.length, 1, 'onCall must be used only by the shared `callable` wrapper');
    assert.match(index, /onCall\(deviceCallOptions,/);
  });

  test('no other module creates HTTP or callable endpoints', () => {
    for (const file of sources(srcDir)) {
      if (file.endsWith('index.ts')) continue;
      const text = readFileSync(file, 'utf8');
      assert.doesNotMatch(text, /\bon(Call|Request)\(/, `${file} defines an endpoint outside index.ts`);
    }
    assert.doesNotMatch(index, /\bonRequest\(/, 'no plain HTTP endpoints: they would bypass App Check and auth');
  });

  test('every exported client endpoint goes through callable() or audited()', () => {
    const exports = [...index.matchAll(/^export const (\w+) = (\w+)\(/gm)];
    assert.ok(exports.length > 0);
    const triggers = new Set(['onSchedule', 'onDocumentCreated', 'onDocumentUpdated']);
    const endpoints = exports.filter(([, , factory]) => !triggers.has(factory));
    for (const [, name, factory] of endpoints) {
      assert.ok(factory === 'callable' || factory === 'audited', `${name} is created by ${factory}, not callable/audited`);
    }
    // audited() itself must wrap callable().
    assert.match(index, /const audited = [^\n]*\n\s+callable\(event,/);
    // The reviewed callable surface (Prompt 18): adding an endpoint must
    // update this count deliberately, alongside its review.
    assert.equal(endpoints.length, 29, `the callable surface changed: ${endpoints.map(([, n]) => n).join(', ')}`);
  });
});
