// Push tokens are server-only (Prompt 11, D-098): no client may read,
// create, change or delete one, whatever its relationship to the device.
import { readFileSync } from 'node:fs';
import { after, before, describe, test } from 'node:test';
import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const readRules = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sirf-hum-push',
    firestore: { rules: readRules('firestore.rules') },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'accountPartners/A'), { partnerAccountId: 'B', conversationId: 'c' });
    await setDoc(doc(db, 'accountPartners/B'), { partnerAccountId: 'A', conversationId: 'c' });
    await setDoc(doc(db, `users/A/devices/${A1}`), { status: 'active' });
    await setDoc(doc(db, `pushTokens/${A1}`), { accountId: 'A', deviceId: A1, token: 't', updatedAt: serverTimestamp() });
  });
});
after(() => env.cleanup());

const A1 = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const token = { accountId: 'A', deviceId: A1, token: 'attacker', updatedAt: serverTimestamp() };

describe('pushTokens/* is server-only', () => {
  for (const [who, context] of [
    ['the owner', () => env.authenticatedContext('A')],
    ['the partner', () => env.authenticatedContext('B')],
    ['an outsider', () => env.authenticatedContext('X')],
    ['anonymous', () => env.unauthenticatedContext()],
  ]) {
    test(`${who} cannot read, list, create, change or delete tokens`, async () => {
      const db = context().firestore();
      await assertFails(getDoc(doc(db, `pushTokens/${A1}`)));
      await assertFails(getDocs(collection(db, 'pushTokens')));
      await assertFails(setDoc(doc(db, 'pushTokens/b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1'), token));
      await assertFails(setDoc(doc(db, `pushTokens/${A1}`), token));
      await assertFails(updateDoc(doc(db, `pushTokens/${A1}`), { token: 'x' }));
      await assertFails(deleteDoc(doc(db, `pushTokens/${A1}`)));
    });
  }
});
