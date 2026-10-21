#!/usr/bin/env node
// Web origin header policy (Prompt 18, D-140; docs/security/WEB-SECURITY.md).
// Fails if firebase.json's Hosting headers lose a protection. Headers are
// defence in depth for an origin that holds NO private content (D-046):
// they never make the web client trusted.
//
//   node tool/check_web_headers.mjs [path/to/firebase.json]
import { readFileSync } from 'node:fs';
import process from 'node:process';

const path = process.argv[2] ?? new URL('../firebase.json', import.meta.url);
const config = JSON.parse(readFileSync(path, 'utf8'));
const hosting = [config.hosting].flat();
const failures = [];
const fail = (message) => failures.push(message);

const app = hosting.find((h) => h.target === 'app');
if (app === undefined) fail('no Hosting target "app"');

const headersFor = (source) => {
  const entry = (app?.headers ?? []).find((h) => h.source === source);
  return new Map((entry?.headers ?? []).map(({ key, value }) => [key.toLowerCase(), String(value)]));
};

/** Parses a CSP into directive → list of sources. */
function parseCsp(value) {
  const directives = new Map();
  for (const part of value.split(';')) {
    const [name, ...sources] = part.trim().split(/\s+/).filter(Boolean);
    if (name !== undefined) directives.set(name.toLowerCase(), sources);
  }
  return directives;
}

function checkCsp(label, value) {
  const csp = parseCsp(value);
  const need = (directive, expected) => {
    const sources = csp.get(directive);
    if (sources === undefined) return fail(`${label}: missing ${directive}`);
    if (JSON.stringify(sources) !== JSON.stringify(expected)) {
      fail(`${label}: ${directive} must be exactly ${expected.join(' ')} (is ${sources.join(' ')})`);
    }
  };
  need('default-src', ["'self'"]);
  need('frame-ancestors', ["'none'"]);
  need('object-src', ["'none'"]);
  need('base-uri', ["'self'"]);
  need('form-action', ["'none'"]);
  const script = csp.get('script-src');
  if (script === undefined) {
    fail(`${label}: missing script-src`);
  } else {
    // Flutter needs to compile WebAssembly ('wasm-unsafe-eval'); nothing
    // may allow arbitrary inline or evaluated script.
    for (const banned of ["'unsafe-inline'", "'unsafe-eval'", "'unsafe-hashes'", 'data:', 'blob:', '*', 'http:', 'https:']) {
      if (script.includes(banned)) fail(`${label}: script-src must not contain ${banned}`);
    }
    for (const source of script) {
      if (source.startsWith('http://')) fail(`${label}: script-src must not load over http (${source})`);
      if (source.includes('*')) fail(`${label}: script-src must not use wildcards (${source})`);
    }
  }
  for (const [directive, sources] of csp) {
    if (sources.includes('*')) fail(`${label}: ${directive} must not be *`);
  }
}

const all = headersFor('**');
const expectExact = (key, value) => {
  if (all.get(key) !== value) fail(`"**": ${key} must be "${value}" (is "${all.get(key) ?? 'missing'}")`);
};
expectExact('x-content-type-options', 'nosniff');
expectExact('x-frame-options', 'DENY');
expectExact('referrer-policy', 'strict-origin-when-cross-origin');
expectExact('cross-origin-opener-policy', 'same-origin-allow-popups');
expectExact('cross-origin-resource-policy', 'same-origin');

const hsts = all.get('strict-transport-security') ?? '';
const maxAge = Number(/max-age=(\d+)/.exec(hsts)?.[1] ?? 0);
if (maxAge < 31536000) fail('"**": Strict-Transport-Security max-age must be at least one year');

const permissions = all.get('permissions-policy') ?? '';
for (const feature of ['camera', 'microphone', 'geolocation', 'display-capture', 'payment', 'usb']) {
  if (!permissions.split(',').map((p) => p.trim()).includes(`${feature}=()`)) {
    fail(`"**": Permissions-Policy must disable ${feature}`);
  }
}

// Report-Only until measured on the deployed staging origin (D-140); an
// enforcing policy, once added, must meet the same bar.
const reportOnly = all.get('content-security-policy-report-only');
const enforced = all.get('content-security-policy');
if (reportOnly === undefined && enforced === undefined) fail('"**": no Content-Security-Policy (enforced or Report-Only)');
if (reportOnly !== undefined) checkCsp('CSP-Report-Only', reportOnly);
if (enforced !== undefined) checkCsp('CSP', enforced);

// Code updates must not be pinned in caches: a fixed or revoked build has
// to reach every browser on the next load.
for (const file of ['/index.html', '/flutter_bootstrap.js', '/main.dart.js', '/version.json', '/flutter_service_worker.js']) {
  if (headersFor(file).get('cache-control') !== 'no-cache') fail(`${file}: Cache-Control must be no-cache`);
}

if (failures.length > 0) {
  console.error(`web header policy FAILED:\n- ${failures.join('\n- ')}`);
  process.exit(1);
}
console.log('web header policy passed');
