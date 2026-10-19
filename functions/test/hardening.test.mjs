// Prompt 09 unit tests: signed revocation and reset-cancel statements,
// golden vectors, and a static guard that server logs carry categories only.
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readdirSync, readFileSync } from 'node:fs';
import { describe, test } from 'node:test';
import { URL } from 'node:url';
import statementsModule from '../lib/device/statements.js';
import { makeApproval, makeDevice, makeResetCancel, makeRevocation, trustVectorsV2 } from './support.mjs';

const { InvalidStatementError, verifyResetCancel, verifyRevocation } = statementsModule;
const committed = JSON.parse(readFileSync(new URL('./vectors/device_trust_v2.json', import.meta.url), 'utf8'));
const hex = (s) => Buffer.from(s, 'hex');

const account = 'accountA';
const challenge = Buffer.alloc(32, 3);
const exp = 1_900_000_000;
const A = makeDevice(1, 2, '11'.repeat(16));
const B = makeDevice(3, 4, '22'.repeat(16));
const C = makeDevice(5, 6, '33'.repeat(16));

describe('v2 golden vectors', () => {
  test('committed vector equals a fresh deterministic regeneration', () => {
    assert.deepEqual(trustVectorsV2(), committed);
  });

  test('committed revocation and reset-cancel statements verify', () => {
    const v = committed;
    const e = Number(v.expiresAtUnix);
    verifyRevocation(v.accountId, hex(v.certAHex), hex(v.certBHex), 3, Buffer.alloc(32, 0x74), e, hex(v.revocationSignatureHex));
    verifyResetCancel(v.accountId, hex(v.certCHex), Buffer.alloc(32, 0x75), e, hex(v.resetCancelSignatureHex));
  });
});

describe('signed revocation (D-081)', () => {
  const sig = makeRevocation({ revoker: A, revoked: B, accountId: account, reason: 2, challenge, expiresAtUnix: exp }).signature;
  const verify = (o = {}) => () =>
    verifyRevocation(o.account ?? account, (o.revoker ?? A).certificate, (o.revoked ?? B).certificate, o.reason ?? 2, o.challenge ?? challenge, o.exp ?? exp, o.sig ?? sig);

  test('valid revocation verifies', () => verify()());

  test('every bound field matters', () => {
    for (const o of [{ account: 'accountB' }, { revoker: C }, { revoked: C }, { reason: 3 }, { challenge: Buffer.alloc(32, 4) }, { exp: exp + 1 }]) {
      assert.throws(verify(o), InvalidStatementError, JSON.stringify(Object.keys(o)));
    }
  });

  test('unknown reasons and foreign signers are rejected', () => {
    assert.throws(verify({ reason: 9 }), InvalidStatementError);
    const forged = makeRevocation({ revoker: A, revoked: B, accountId: account, reason: 2, challenge, expiresAtUnix: exp, signer: C.person }).signature;
    assert.throws(verify({ sig: forged }), InvalidStatementError);
  });

  test('an approval signature is never a revocation (domain separation)', () => {
    const approval = makeApproval({ approver: A, newDevice: B, accountId: account, challenge, expiresAtUnix: exp }).signature;
    assert.throws(verify({ sig: approval }), InvalidStatementError);
  });
});

describe('identity reset cancellation (D-082)', () => {
  test('binds device and account', () => {
    const { signature } = makeResetCancel({ device: A, accountId: account, challenge, expiresAtUnix: exp });
    verifyResetCancel(account, A.certificate, challenge, exp, signature);
    assert.throws(() => verifyResetCancel(account, B.certificate, challenge, exp, signature), InvalidStatementError);
    assert.throws(() => verifyResetCancel('accountB', A.certificate, challenge, exp, signature), InvalidStatementError);
  });
});

describe('secret-safe server logging (static guard)', () => {
  test('every logger call logs only an event name and an outcome category', () => {
    const src = new URL('../src/', import.meta.url);
    const files = ['index.ts', ...readdirSync(new URL('device/', src)).map((f) => `device/${f}`)];
    let calls = 0;
    for (const file of files) {
      const text = readFileSync(new URL(file, src), 'utf8');
      for (const m of text.matchAll(/logger\.(info|warn|error|debug|log)\(([^;]*)\);/gs)) {
        calls += 1;
        const args = m[2];
        // Allowed: a string event and { outcome: ... } or a spread of the
        // cleanup counters. Nothing derived from request data.
        assert.match(args, /^\s*(event|'[a-z_]+'),\s*\{\s*(outcome: (error\.failure|'internal')|\.\.\.result)\s*\}\s*$/s, `${file}: ${args}`);
      }
      assert.doesNotMatch(text, /console\./, `${file} uses console`);
    }
    assert.ok(calls >= 3, 'expected the guarded logger calls to be found');
  });
});
