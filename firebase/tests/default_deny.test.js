// Proves the default-deny baseline: until a phase explicitly opens a path
// (with its own tests), nobody can read or write anything — including a
// signed-in user.
import { readFileSync } from 'node:fs';
import { after, before, describe, test } from 'node:test';
import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

const readRules = (file) =>
  readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sirf-hum',
    firestore: { rules: readRules('firestore.rules') },
    storage: { rules: readRules('storage.rules') },
  });
});

after(() => env.cleanup());

const callers = {
  unauthenticated: () => env.unauthenticatedContext(),
  authenticated: () => env.authenticatedContext('person-a'),
};

for (const [caller, context] of Object.entries(callers)) {
  describe(`${caller} caller`, () => {
    test('cannot read or write Firestore documents', async () => {
      const db = context().firestore();
      await assertFails(getDoc(doc(db, 'couples/c1')));
      await assertFails(setDoc(doc(db, 'couples/c1'), { a: 1 }));
      await assertFails(getDoc(doc(db, 'users/person-b')));
      await assertFails(setDoc(doc(db, 'users/person-a'), { a: 1 }));
    });

    test('cannot read or write Storage objects', async () => {
      const object = ref(context().storage(), 'couples/c1/media/m1.bin');
      await assertFails(uploadBytes(object, new Uint8Array([1, 2, 3])));
      await assertFails(getBytes(object));
    });
  });
}
