// Device registry rules (Prompt 07 §8, Prompt 08 §21, Prompt 09 §11). Every allowed case
// has a matching denied case; all trust-creating state (registration,
// activation, approvals, recovery, indexes, challenges, rate limits) is
// server-only and unreachable from clients.
import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Bytes,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

const readRules = (file) =>
  readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sirf-hum',
    firestore: { rules: readRules('firestore.rules') },
  });
});
afterEach(() => env.clearFirestore());
after(() => env.cleanup());

const A = 'accountA';
const B = 'accountB';
const DEVICE = '0123456789abcdef0123456789abcdef';
const devicePath = (account, device = DEVICE) => `users/${account}/devices/${device}`;

const asUser = (uid) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

/** The exact v1 pending record a genuine client writes. */
const pending = (overrides = {}) => ({
  schemaVersion: 1,
  status: 'pending',
  platform: 'android',
  certificate: Bytes.fromUint8Array(new Uint8Array(185).fill(1)),
  ciphersuite: 1,
  implementation: 'openmls/0.9.1',
  createdAt: serverTimestamp(),
  ...overrides,
});

/** Seeds a record bypassing rules (what the server would have written). */
async function seed(path, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

const seeded = (status, extra = {}) => ({
  ...pending(),
  createdAt: Timestamp.now(),
  status,
  ...extra,
});

const revocation = () => ({
  status: 'revoked',
  revokedAt: serverTimestamp(),
  revokedReason: 'user_removed',
});

describe('unauthenticated', () => {
  test('1. cannot read device records', async () => {
    await seed(devicePath(A), seeded('active'));
    await assertFails(getDoc(doc(anonymous(), devicePath(A))));
    await assertFails(getDocs(collection(anonymous(), `users/${A}/devices`)));
  });

  test('2. cannot write device records', async () => {
    await assertFails(setDoc(doc(anonymous(), devicePath(A)), pending()));
  });
});

describe('cross-account isolation', () => {
  test("3. user A cannot read user B's devices", async () => {
    await seed(devicePath(B), seeded('active'));
    await assertFails(getDoc(doc(asUser(A), devicePath(B))));
    await assertFails(getDocs(collection(asUser(A), `users/${B}/devices`)));
  });

  test("4. user A cannot create, update or delete user B's devices", async () => {
    await assertFails(setDoc(doc(asUser(A), devicePath(B)), pending()));
    await seed(devicePath(B), seeded('active'));
    await assertFails(updateDoc(doc(asUser(A), devicePath(B)), revocation()));
    await assertFails(deleteDoc(doc(asUser(A), devicePath(B))));
  });

  test('owner can read and list own devices', async () => {
    await seed(devicePath(A), seeded('active'));
    await assertSucceeds(getDoc(doc(asUser(A), devicePath(A))));
    await assertSucceeds(getDocs(collection(asUser(A), `users/${A}/devices`)));
  });
});

describe('registration', () => {
  test('5. self registration goes through the registerDevice Function: even a valid client create is denied', async () => {
    // Prompt 07 allowed this create; Prompt 08 moved registration server-side
    // (certificate verified, rate-limited, capped), so it is now denied.
    await assertFails(setDoc(doc(asUser(A), devicePath(A)), pending()));
    await assertFails(
      setDoc(doc(asUser(A), devicePath(A, 'ffffffffffffffffffffffffffffffff')), pending({ platform: 'ios' })),
    );
  });

  test('6. invalid registrations are denied', async () => {
    const db = asUser(A);
    const invalid = {
      'client claims active': pending({ status: 'active' }),
      'client claims revoked': pending({ status: 'revoked' }),
      'unknown field': pending({ email: 'a@example.com' }),
      'server field activatedAt': pending({ activatedAt: serverTimestamp() }),
      'unknown platform': pending({ platform: 'web' }),
      'wrong schema version': pending({ schemaVersion: 2 }),
      'wrong ciphersuite': pending({ ciphersuite: 2 }),
      'wrong implementation': pending({ implementation: 'openmls/0.10.0' }),
      'certificate as string': pending({ certificate: 'AAAA' }),
      'empty certificate': pending({ certificate: Bytes.fromUint8Array(new Uint8Array(0)) }),
      'oversized certificate': pending({ certificate: Bytes.fromUint8Array(new Uint8Array(513)) }),
      'client-chosen createdAt': pending({ createdAt: Timestamp.fromMillis(0) }),
    };
    for (const [name, data] of Object.entries(invalid)) {
      await assertFails(setDoc(doc(db, devicePath(A, '00000000000000000000000000000001')), data), name);
    }
    const { certificate: _drop, ...missing } = pending();
    await assertFails(setDoc(doc(db, devicePath(A)), missing));
  });

  test('invalid device IDs are denied', async () => {
    for (const id of ['ABCDEF0123456789ABCDEF0123456789', 'abc', 'g'.repeat(32), '0'.repeat(33)]) {
      await assertFails(setDoc(doc(asUser(A), devicePath(A, id)), pending()));
    }
  });

  test('re-registering an existing device ID is denied (set on an existing record)', async () => {
    await seed(devicePath(A), seeded('revoked', { revokedAt: Timestamp.now(), revokedReason: 'user_removed' }));
    await assertFails(setDoc(doc(asUser(A), devicePath(A)), pending()));
  });
});

describe('immutability and revocation', () => {
  test('7. immutable identity fields cannot be modified', async () => {
    await seed(devicePath(A), seeded('active'));
    const db = asUser(A);
    const changes = [
      { certificate: Bytes.fromUint8Array(new Uint8Array(185).fill(2)) },
      { platform: 'ios' },
      { schemaVersion: 2 },
      { implementation: 'other' },
      { createdAt: serverTimestamp() },
      { ...revocation(), certificate: Bytes.fromUint8Array(new Uint8Array(185).fill(3)) },
    ];
    for (const change of changes) {
      await assertFails(updateDoc(doc(db, devicePath(A)), change));
    }
  });

  test('client cannot activate its own device (server-only)', async () => {
    await seed(devicePath(A), seeded('pending'));
    await assertFails(updateDoc(doc(asUser(A), devicePath(A)), { status: 'active' }));
    await assertFails(
      updateDoc(doc(asUser(A), devicePath(A)), { status: 'active', activatedAt: serverTimestamp() }),
    );
  });

  test('D-081: even the owner cannot revoke by a direct write (signed revokeDevice only)', async () => {
    await seed(devicePath(A), seeded('active'));
    await assertFails(updateDoc(doc(asUser(A), devicePath(A)), revocation()));
    const other = devicePath(A, 'ffffffffffffffffffffffffffffffff');
    await seed(other, seeded('pending'));
    await assertFails(updateDoc(doc(asUser(A), other), revocation()));
  });

  test('8. revocation cannot be reversed by a client', async () => {
    await seed(devicePath(A), seeded('revoked', { revokedAt: Timestamp.now(), revokedReason: 'user_removed' }));
    const db = asUser(A);
    for (const status of ['active', 'pending']) {
      await assertFails(updateDoc(doc(db, devicePath(A)), { status }));
    }
    await assertFails(updateDoc(doc(db, devicePath(A)), revocation()));
    await assertFails(deleteDoc(doc(db, devicePath(A))));
  });

  test('no shape of revocation write is accepted', async () => {
    await seed(devicePath(A), seeded('active'));
    const db = asUser(A);
    await assertFails(updateDoc(doc(db, devicePath(A)), { ...revocation(), revokedAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(doc(db, devicePath(A)), { ...revocation(), revokedReason: 'free text' }));
    await assertFails(updateDoc(doc(db, devicePath(A)), { status: 'revoked' }));
    // Fabricated signed evidence is still a client write: denied.
    await assertFails(
      updateDoc(doc(db, devicePath(A)), {
        ...revocation(),
        revocation: { authority: 'device', revokerDeviceId: DEVICE, signature: Bytes.fromUint8Array(new Uint8Array(64)) },
      }),
    );
  });

  test('records can never be deleted, even by the owner', async () => {
    await seed(devicePath(A), seeded('pending'));
    await assertFails(deleteDoc(doc(asUser(A), devicePath(A))));
  });
});

describe('Prompt 08: terminal states and server-controlled fields', () => {
  test('rejected and expired records can never change, not even to revoked', async () => {
    for (const status of ['rejected', 'expired']) {
      const path = devicePath(A, status === 'rejected' ? 'a'.repeat(32) : 'b'.repeat(32));
      await seed(path, seeded(status));
      for (const change of [revocation(), { status: 'pending' }, { status: 'active' }]) {
        await assertFails(updateDoc(doc(asUser(A), path), change));
      }
    }
  });

  test('client cannot write server-controlled trust fields', async () => {
    await seed(devicePath(A), seeded('pending', { expiresAt: Timestamp.now() }));
    const db = asUser(A);
    for (const change of [
      { activationMethod: 'approval' },
      { approvedBy: 'c'.repeat(32) },
      { expiresAt: Timestamp.fromMillis(Date.now() + 1e10) },
      { activatedAt: serverTimestamp() },
      { ...revocation(), approvedBy: 'c'.repeat(32) },
    ]) {
      await assertFails(updateDoc(doc(db, devicePath(A)), change));
    }
  });

  test('a revoked device (its own owner session) cannot restore its state', async () => {
    await seed(devicePath(A), seeded('revoked', { revokedAt: Timestamp.now(), revokedReason: 'user_removed', activationMethod: 'approval' }));
    const db = asUser(A);
    await assertFails(updateDoc(doc(db, devicePath(A)), { status: 'active' }));
    await assertFails(updateDoc(doc(db, devicePath(A)), { status: 'active', revokedAt: null, revokedReason: null }));
    await assertFails(setDoc(doc(db, devicePath(A)), seeded('active')));
  });

  test("unauthorized revocation: another account cannot revoke A's device", async () => {
    await seed(devicePath(A), seeded('active'));
    await assertFails(updateDoc(doc(asUser(B), devicePath(A)), revocation()));
    await assertFails(updateDoc(doc(anonymous(), devicePath(A)), revocation()));
  });
});

describe('Prompt 09: account trust state (D-082, D-083)', () => {
  const trustDoc = { trustEpoch: 3, identityEpoch: 0, bootstrapOpen: false, firstDeviceId: DEVICE };

  test('the owner can read its trust epoch and reset state', async () => {
    await seed(`accountTrust/${A}`, trustDoc);
    await assertSucceeds(getDoc(doc(asUser(A), `accountTrust/${A}`)));
  });

  test('other accounts and unauthenticated sessions cannot read it', async () => {
    await seed(`accountTrust/${A}`, trustDoc);
    await assertFails(getDoc(doc(asUser(B), `accountTrust/${A}`)));
    await assertFails(getDoc(doc(anonymous(), `accountTrust/${A}`)));
  });

  test('no client can write it: no epoch rollback, bootstrap reopen or fake reset', async () => {
    await seed(`accountTrust/${A}`, trustDoc);
    const db = asUser(A);
    for (const change of [
      { trustEpoch: 1 },
      { trustEpoch: 99 },
      { bootstrapOpen: true },
      { reset: { status: 'completed' } },
      { identityEpoch: 5 },
    ]) {
      await assertFails(updateDoc(doc(db, `accountTrust/${A}`), change));
    }
    await assertFails(setDoc(doc(db, `accountTrust/${A}`), { ...trustDoc, bootstrapOpen: true }));
    await assertFails(deleteDoc(doc(db, `accountTrust/${A}`)));
    await assertFails(setDoc(doc(asUser(B), `accountTrust/${B}`), { bootstrapOpen: true }));
  });
});

describe('server-only collections', () => {
  test('challenges, approvals, indexes and limits are unreachable from clients', async () => {
    for (const path of [
      'deviceChallenges/c1',
      'deviceIdIndex/i1',
      'deviceKeyIndex/k1',
      'deviceApprovalRequests/r1',
      `rateLimits/${A}__register`,
    ]) {
      await seed(path, { accountId: A });
      await assertFails(getDoc(doc(asUser(A), path)));
      await assertFails(setDoc(doc(asUser(A), path), { accountId: A }));
      await assertFails(deleteDoc(doc(asUser(A), path)));
    }
    // Replayed approval metadata: writing an "approved" request is impossible.
    await assertFails(
      setDoc(doc(asUser(A), 'deviceApprovalRequests/r2'), { accountId: A, status: 'proven', deviceId: DEVICE }),
    );
  });

  test('the account document itself stays closed', async () => {
    await assertFails(getDoc(doc(asUser(A), `users/${A}`)));
    await assertFails(setDoc(doc(asUser(A), `users/${A}`), { a: 1 }));
  });
});
