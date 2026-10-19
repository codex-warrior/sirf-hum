// Account profile, couple and pairing rules (Prompt 12,
// docs/security/COUPLE-AND-PAIRING.md, D-100–D-103). Couples and pairings are
// server-authoritative: no client creates, edits or deletes membership.
import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

const readRules = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

let env;
before(async () => {
  // Own demo project: node --test runs files in parallel.
  env = await initializeTestEnvironment({
    projectId: 'demo-sirf-hum-couple',
    firestore: { rules: readRules('firestore.rules') },
  });
});
afterEach(() => env.clearFirestore());
after(() => env.cleanup());

const A = 'accountA';
const B = 'accountB';
const X = 'accountX'; // outsider
const COUPLE = 'c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0';
const PAIRING = 'p0p0p0p0p0p0p0p0p0p0p0p0p0p0p0p0';

const asUser = (uid) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

async function seed(path, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

async function seedCouple() {
  await seed(`couples/${COUPLE}`, { schemaVersion: 1, members: [A, B], status: 'active', pairingId: PAIRING, createdAt: Timestamp.now() });
  await seed(`accountPartners/${A}`, { schemaVersion: 1, partnerAccountId: B, conversationId: 'c', coupleId: COUPLE });
  await seed(`accountPartners/${B}`, { schemaVersion: 1, partnerAccountId: A, conversationId: 'c', coupleId: COUPLE });
}

const profile = (displayName = 'Asha') => ({
  schemaVersion: 1,
  displayName,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

describe('account profile users/{uid}', () => {
  test('the owner creates a minimal profile with server timestamps', async () => {
    await assertSucceeds(setDoc(doc(asUser(A), `users/${A}`), profile()));
    await assertSucceeds(getDoc(doc(asUser(A), `users/${A}`)));
  });

  test('invalid profiles are rejected', async () => {
    const db = asUser(A);
    const ref = doc(db, `users/${A}`);
    for (const bad of [
      { ...profile(), email: 'a@example.com' }, // no extra (sensitive) fields
      { ...profile(), lastSeen: serverTimestamp() }, // no presence/activity
      { ...profile(), coupleId: COUPLE }, // no self-asserted membership
      { ...profile(), schemaVersion: 2 },
      { ...profile(), createdAt: Timestamp.fromMillis(0) }, // client clock
      { schemaVersion: 1, displayName: 'Asha', createdAt: serverTimestamp() }, // missing field
      profile(''),
      profile('   '),
      profile('x'.repeat(65)),
      profile('line\nbreak'),
      profile('nul\u0000'),
      { ...profile(), displayName: 42 },
    ]) {
      await assertFails(setDoc(ref, bad));
    }
  });

  test('the owner edits only the display name; createdAt and version are immutable; no delete', async () => {
    await seed(`users/${A}`, { schemaVersion: 1, displayName: 'Asha', createdAt: Timestamp.fromMillis(1000), updatedAt: Timestamp.fromMillis(1000) });
    const ref = doc(asUser(A), `users/${A}`);
    await assertSucceeds(updateDoc(ref, { displayName: 'Asha K', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { displayName: 'A', updatedAt: Timestamp.fromMillis(5) }));
    await assertFails(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { schemaVersion: 2, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { displayName: 'A', status: 'paired', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { displayName: '', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref));
  });

  test("nobody else writes or reads a profile; the partner reads it once paired", async () => {
    await seed(`users/${A}`, { schemaVersion: 1, displayName: 'Asha', createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
    await assertFails(setDoc(doc(asUser(X), `users/${X === A ? B : A}`), profile('Hijack')));
    await assertFails(updateDoc(doc(asUser(B), `users/${A}`), { displayName: 'x', updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(asUser(B), `users/${A}`)), 'not yet a partner');
    await assertFails(getDoc(doc(asUser(X), `users/${A}`)));
    await assertFails(getDoc(doc(anonymous(), `users/${A}`)));
    await assertFails(setDoc(doc(anonymous(), `users/${A}`), profile()));
    // No enumeration: listing profiles is denied, even with a filter.
    await assertFails(getDocs(collection(asUser(A), 'users')));
    await assertFails(getDocs(query(collection(asUser(A), 'users'), where('displayName', '==', 'Asha'))));
    await seedCouple();
    await assertSucceeds(getDoc(doc(asUser(B), `users/${A}`)));
    await assertFails(getDoc(doc(asUser(X), `users/${A}`)));
  });
});

describe('couples/{coupleId}', () => {
  test('members read their couple; outsiders and anonymous users do not', async () => {
    await seedCouple();
    await assertSucceeds(getDoc(doc(asUser(A), `couples/${COUPLE}`)));
    await assertSucceeds(getDoc(doc(asUser(B), `couples/${COUPLE}`)));
    await assertFails(getDoc(doc(asUser(X), `couples/${COUPLE}`)));
    await assertFails(getDoc(doc(anonymous(), `couples/${COUPLE}`)));
    await assertFails(getDoc(doc(asUser(A), 'couples/ffffffffffffffffffffffffffffffff')), 'unknown couple');
    await assertFails(getDocs(collection(asUser(X), 'couples')), 'no listing');
    await assertSucceeds(getDocs(query(collection(asUser(A), 'couples'), where('members', 'array-contains', A))));
  });

  test('no client creates, edits, joins or dissolves a couple', async () => {
    const forged = { schemaVersion: 1, members: [A, X], status: 'active', pairingId: PAIRING, createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(asUser(A), 'couples/forged0000000000000000000000000'), forged));
    await assertFails(setDoc(doc(asUser(X), 'couples/forged0000000000000000000000000'), { ...forged, members: [X, A] }));
    await seedCouple();
    const ref = (uid) => doc(asUser(uid), `couples/${COUPLE}`);
    await assertFails(updateDoc(ref(X), { members: [A, X] }), 'outsider joins');
    await assertFails(updateDoc(ref(A), { members: [A, X] }), 'member swaps partner');
    await assertFails(updateDoc(ref(A), { members: [A, B, X] }), 'third member');
    await assertFails(updateDoc(ref(A), { status: 'dissolved' }), 'client-controlled lifecycle');
    await assertFails(updateDoc(ref(A), { createdAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref(A)));
    await assertFails(deleteDoc(ref(B)));
  });

  test('forged partner records and couple IDs are rejected', async () => {
    await assertFails(setDoc(doc(asUser(X), `accountPartners/${X}`), { schemaVersion: 1, partnerAccountId: A, conversationId: 'c', coupleId: COUPLE }));
    await seedCouple();
    await assertFails(updateDoc(doc(asUser(A), `accountPartners/${A}`), { coupleId: 'ffffffffffffffffffffffffffffffff' }));
    await assertFails(deleteDoc(doc(asUser(A), `accountPartners/${A}`)));
    // X claiming a couple ID gains nothing: still no partner reads of A.
    await assertFails(getDoc(doc(asUser(X), `users/${A}/devices/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`)));
    await assertFails(getDoc(doc(asUser(X), `accountTrust/${A}`)));
  });
});

describe('pairings/* and pairingLocks/* are server-only', () => {
  test('no client reads, lists, creates, accepts or edits a pairing', async () => {
    await seed(`pairings/${PAIRING}`, { schemaVersion: 1, status: 'claimed', inviterAccountId: A, inviteeAccountId: B, confirmationCode: '123456' });
    await seed(`pairingLocks/${A}`, { pairingId: PAIRING, role: 'inviter' });
    for (const uid of [A, B, X]) {
      const db = asUser(uid);
      await assertFails(getDoc(doc(db, `pairings/${PAIRING}`)));
      await assertFails(getDocs(collection(db, 'pairings')));
      await assertFails(getDocs(query(collection(db, 'pairings'), where('inviterAccountId', '==', A))));
      await assertFails(updateDoc(doc(db, `pairings/${PAIRING}`), { status: 'accepted' }));
      await assertFails(deleteDoc(doc(db, `pairings/${PAIRING}`)));
      await assertFails(getDoc(doc(db, `pairingLocks/${uid}`)));
      await assertFails(setDoc(doc(db, `pairingLocks/${uid}`), { pairingId: 'x', role: 'inviter' }));
    }
    await assertFails(setDoc(doc(asUser(X), 'pairings/forged'), { status: 'accepted', accounts: [X, A] }));
    await assertFails(setDoc(doc(asUser(A), 'pairings/forged'), { status: 'pending', inviterAccountId: A, tokenHash: 'x' }));
    await assertFails(getDoc(doc(anonymous(), `pairings/${PAIRING}`)));
  });
});
