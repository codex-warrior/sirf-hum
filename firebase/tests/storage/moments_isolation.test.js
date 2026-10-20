// Couple isolation for Moments (Prompt 15, D-113, docs/architecture/
// MOMENTS-ARCHITECTURE.md §6). A moment adds NO server surface: it is the
// ciphertext objects of its photos plus encrypted messages in the couple's
// conversation. These tests walk exactly that write and read path for two
// couples and prove the existing rules isolate them: no client-supplied
// couple or conversation ID, device or account grants access, and nothing
// can be deleted or rewritten (so no deletion is ever faked).
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, test } from 'node:test';
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
import { deleteObject, getBytes, listAll, ref, uploadBytes } from 'firebase/storage';

const readRules = (file) => readFileSync(new URL(`../../${file}`, import.meta.url), 'utf8');

let env;
before(async () => {
  // Cross-service rules read the emulators' own project (see
  // media_storage.test.js); this file runs serially with it.
  env = await initializeTestEnvironment({
    projectId: 'demo-sirf-hum',
    firestore: { rules: readRules('firestore.rules') },
    storage: { rules: readRules('storage.rules') },
  });
});
afterEach(async () => {
  await env.clearStorage();
  await env.clearFirestore();
});
after(() => env.cleanup());

// Couple 1: Asha (A) + Ravi (B). Couple 2: Dev (D) + Esha (E).
const A = 'momentsAsha';
const B = 'momentsRavi';
const D = 'momentsDev';
const E = 'momentsEsha';
const C1 = '1111aaaa1111aaaa1111aaaa1111aaaa';
const C2 = '2222bbbb2222bbbb2222bbbb2222bbbb';
const COUPLE1 = 'c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c1';
const COUPLE2 = 'c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c2';
const A1 = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const A2 = 'a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2'; // revoked
const A3 = 'a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3'; // pending (stale / never activated)
const B1 = 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1';
const D1 = 'd1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1';
const PHOTO = '0123456789abcdef0123456789abcdef';
const MANIFEST = 'fedcba9876543210fedcba9876543210';

const OCTET = 'application/octet-stream';
const objectPath = (c, m = PHOTO) => `conversations/${c}/media/${m}`;
const messagePath = (c, m = MANIFEST) => `conversations/${c}/messages/${m}`;
const fs = (uid) => env.authenticatedContext(uid).firestore();
const st = (uid) => env.authenticatedContext(uid).storage();
const anonFs = () => env.unauthenticatedContext().firestore();
const anonSt = () => env.unauthenticatedContext().storage();
const blob = (n = 64) => new Uint8Array(n).fill(9);

async function seed(path, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

const message = (uid, device) => ({
  schemaVersion: 1,
  protocolVersion: 1,
  senderAccountId: uid,
  senderDeviceId: device,
  epoch: 1,
  ciphertext: Bytes.fromUint8Array(blob(300)),
  serverTime: serverTimestamp(),
});

const putPhoto = (uid, device, c) =>
  uploadBytes(ref(st(uid), objectPath(c)), blob(), {
    contentType: OCTET,
    customMetadata: { sd: device },
  });
const putManifest = (uid, device, c) => setDoc(doc(fs(uid), messagePath(c)), message(uid, device));

/** One moment, written as the app does: the photo object, then the message. */
async function storedMoment(c, uid, device) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), objectPath(c)), blob(), {
      contentType: OCTET,
      customMetadata: { sd: device },
    });
    await setDoc(doc(ctx.firestore(), messagePath(c)), { ...message(uid, device), serverTime: Timestamp.now() });
  });
}

beforeEach(async () => {
  const conversation = (members, coupleId) => ({
    schemaVersion: 1,
    protocolVersion: 1,
    ciphersuite: 1,
    members,
    coupleId,
    pairingId: `p-${coupleId}`,
    state: 'active',
    epoch: 1,
    createdAt: Timestamp.now(),
  });
  await seed(`conversations/${C1}`, conversation([A, B], COUPLE1));
  await seed(`conversations/${C2}`, conversation([D, E], COUPLE2));
  for (const [account, device, status] of [
    [A, A1, 'active'],
    [A, A2, 'revoked'],
    [A, A3, 'pending'],
    [B, B1, 'active'],
    [D, D1, 'active'],
  ]) {
    await seed(`users/${account}/devices/${device}`, { schemaVersion: 1, status });
  }
});

describe('a couple keeps its own moments', () => {
  test('Asha saves a moment from an active phone; Ravi can fetch it', async () => {
    await assertSucceeds(putPhoto(A, A1, C1));
    await assertSucceeds(putManifest(A, A1, C1));
    await assertSucceeds(getBytes(ref(st(B), objectPath(C1))));
    await assertSucceeds(getDoc(doc(fs(B), messagePath(C1))));
  });
});

describe('another couple gets nothing', () => {
  test("couple 2 cannot read couple 1's photos or moments", async () => {
    await storedMoment(C1, A, A1);
    for (const uid of [D, E]) {
      await assertFails(getBytes(ref(st(uid), objectPath(C1))), `${uid} object`);
      await assertFails(getDoc(doc(fs(uid), messagePath(C1))), `${uid} message`);
      await assertFails(getDocs(collection(fs(uid), `conversations/${C1}/messages`)), `${uid} list`);
      await assertFails(getDoc(doc(fs(uid), `conversations/${C1}`)), `${uid} conversation`);
    }
  });

  test('a forged couple or conversation reference grants nothing', async () => {
    // Dev aims his own active device at couple 1's conversation.
    await assertFails(putPhoto(D, D1, C1), 'object into another couple');
    await assertFails(putManifest(D, D1, C1), 'moment into another couple');
    // Asha aims at couple 2's conversation, even with her active device.
    await assertFails(putPhoto(A, A1, C2), 'object into couple 2');
    await assertFails(putManifest(A, A1, C2), 'moment into couple 2');
    // A made-up conversation ID, or the couple ID used as one.
    for (const c of ['9999999999999999999999999999999f', COUPLE1]) {
      await assertFails(putPhoto(A, A1, c), `object ${c}`);
      await assertFails(putManifest(A, A1, c), `moment ${c}`);
    }
    // Malformed references never match a rule.
    await assertFails(putPhoto(A, A1, 'not-a-conversation'));
  });

  test('no one can list conversations or media to find moments', async () => {
    await storedMoment(C1, A, A1);
    await assertFails(getDocs(collection(fs(A), 'conversations')));
    await assertFails(listAll(ref(st(A), `conversations/${C1}/media`)));
  });
});

describe('device trust and accounts', () => {
  test('revoked, stale or another account\'s devices cannot add moments', async () => {
    await assertFails(putPhoto(A, A2, C1), 'revoked');
    await assertFails(putManifest(A, A2, C1), 'revoked');
    await assertFails(putPhoto(A, A3, C1), 'pending');
    await assertFails(putManifest(A, A3, C1), 'pending');
    await assertFails(putPhoto(A, B1, C1), "Ravi's device under Asha's account");
    await assertFails(
      setDoc(doc(fs(A), messagePath(C1)), message(B, B1)),
      'claiming to be Ravi',
    );
  });

  test('signed out: nothing can be read or written', async () => {
    await storedMoment(C1, A, A1);
    await assertFails(getBytes(ref(anonSt(), objectPath(C1))));
    await assertFails(getDoc(doc(anonFs(), messagePath(C1))));
    await assertFails(
      uploadBytes(ref(anonSt(), objectPath(C1, MANIFEST)), blob(), {
        contentType: OCTET,
        customMetadata: { sd: A1 },
      }),
    );
  });
});

describe('nothing is deleted or rewritten from a client', () => {
  test('photos and moments are immutable: no delete, overwrite or edit', async () => {
    await storedMoment(C1, A, A1);
    await assertFails(deleteObject(ref(st(A), objectPath(C1))), 'delete own photo');
    await assertFails(deleteObject(ref(st(B), objectPath(C1))), "delete partner's photo");
    await assertFails(putPhoto(A, A1, C1), 'replay / overwrite');
    await assertFails(deleteDoc(doc(fs(A), messagePath(C1))), 'delete moment');
    await assertFails(deleteDoc(doc(fs(D), messagePath(C1))), 'outsider delete');
    await assertFails(
      updateDoc(doc(fs(A), messagePath(C1)), { ciphertext: Bytes.fromUint8Array(blob(10)) }),
      'edit moment',
    );
    await assertFails(putManifest(A, A1, C1), 'replayed message id');
  });

  test('nothing descriptive can ride along with a photo', async () => {
    for (const extra of [{ caption: 'beach' }, { name: 'IMG_0001.jpg' }, { gps: '15.5,73.8' }, { coupleId: COUPLE1 }]) {
      await assertFails(
        uploadBytes(ref(st(A), objectPath(C1)), blob(), {
          contentType: OCTET,
          customMetadata: { sd: A1, ...extra },
        }),
        JSON.stringify(extra),
      );
    }
    await assertFails(
      uploadBytes(ref(st(A), objectPath(C1)), blob(), {
        contentType: 'image/jpeg',
        customMetadata: { sd: A1 },
      }),
    );
    await assertFails(
      setDoc(doc(fs(A), messagePath(C1)), { ...message(A, A1), caption: 'beach' }),
      'plaintext caption field',
    );
  });
});
