// Storage rules for encrypted media objects (Prompt 11,
// docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md §4, D-095). Rules authorize
// access to CIPHERTEXT; they never see plaintext or keys. Every allowed
// case has denied neighbours. Cross-service reads use the Firestore
// emulator, seeded with what provisioning and device activation write.
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import {
  deleteObject,
  getBytes,
  getMetadata,
  listAll,
  ref,
  updateMetadata,
  uploadBytes,
} from 'firebase/storage';

const readRules = (file) => readFileSync(new URL(`../../${file}`, import.meta.url), 'utf8');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    // Cross-service rules read the Firestore of the emulators' own project
    // (a separate demo project would make every allowed case fail, so the
    // denials would pass vacuously). This file therefore runs after the
    // parallel ones (package.json), never alongside devices.test.js.
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

const A = 'mediaAccountA';
const B = 'mediaAccountB';
const X = 'mediaAccountX'; // outsider
const C = 'aaaa0000aaaa0000aaaa0000aaaa0000';
const CLOSED = 'cccc0000cccc0000cccc0000cccc0000';
const OTHER = 'bbbb0000bbbb0000bbbb0000bbbb0000';
const A1 = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const A2 = 'a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2'; // revoked
const A3 = 'a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3'; // pending
const B1 = 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1';
const X1 = 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1';
const M = '0123456789abcdef0123456789abcdef';
const MAX = 67125273;

const OCTET = 'application/octet-stream';
const meta = (sd, extra = {}) => ({ contentType: OCTET, customMetadata: { sd, ...extra } });
const path = (c = C, m = M) => `conversations/${c}/media/${m}`;
const asUser = (uid) => env.authenticatedContext(uid).storage();
const anonymous = () => env.unauthenticatedContext().storage();
const bytes = (n = 64) => new Uint8Array(n).fill(7);

async function seed(docPath, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), docPath), data));
}

async function put(storage, objectPath, data, metadata) {
  return uploadBytes(ref(storage, objectPath), data, metadata);
}

/** An object uploaded by A1 (as if through the rules). */
async function stored(c = C, m = M) {
  await env.withSecurityRulesDisabled((ctx) => put(ctx.storage(), path(c, m), bytes(), meta(A1)));
}

beforeEach(async () => {
  const conversation = (state, members = [A, B]) => ({
    schemaVersion: 1,
    protocolVersion: 1,
    ciphersuite: 1,
    members,
    pairingId: 'p-media',
    state,
    epoch: 1,
    createdAt: Timestamp.now(),
  });
  await seed(`conversations/${C}`, conversation('active'));
  await seed(`conversations/${CLOSED}`, conversation('closed'));
  await seed(`conversations/${OTHER}`, conversation('active', [B, X]));
  for (const [account, device, status] of [
    [A, A1, 'active'],
    [A, A2, 'revoked'],
    [A, A3, 'pending'],
    [B, B1, 'active'],
    [X, X1, 'active'],
  ]) {
    await seed(`users/${account}/devices/${device}`, { schemaVersion: 1, status });
  }
});

describe('creating a ciphertext object', () => {
  test('a member writing as its own active device may create it', async () => {
    await assertSucceeds(put(asUser(A), path(), bytes(), meta(A1)));
  });

  test('objects are create-only: no overwrite (duplicate upload) and no metadata change', async () => {
    await stored();
    await assertFails(put(asUser(A), path(), bytes(), meta(A1)));
    await assertFails(put(asUser(B), path(), bytes(), meta(B1)));
    await assertFails(updateMetadata(ref(asUser(A), path()), { customMetadata: { sd: B1 } }));
    await assertFails(updateMetadata(ref(asUser(A), path()), { contentType: 'image/jpeg' }));
  });

  test('outsiders, other accounts and anonymous callers cannot write', async () => {
    await assertFails(put(asUser(X), path(), bytes(), meta(X1)), 'not a member');
    await assertFails(put(anonymous(), path(), bytes(), meta(A1)), 'unauthenticated');
    await assertFails(put(asUser(B), path(), bytes(), meta(A1)), "another account's device");
    await assertFails(put(asUser(A), path(OTHER), bytes(), meta(A1)), 'cross-conversation');
  });

  test('revoked, pending and unknown devices cannot write', async () => {
    await assertFails(put(asUser(A), path(), bytes(), meta(A2)), 'revoked');
    await assertFails(put(asUser(A), path(), bytes(), meta(A3)), 'pending');
    await assertFails(put(asUser(A), path(), bytes(), meta('dddddddddddddddddddddddddddddddd')), 'unknown');
  });

  test('closed conversations accept nothing new', async () => {
    await assertFails(put(asUser(A), path(CLOSED), bytes(), meta(A1)));
  });

  test('content type and metadata are fixed: nothing descriptive leaks', async () => {
    await assertFails(put(asUser(A), path(), bytes(), { contentType: 'image/jpeg', customMetadata: { sd: A1 } }));
    await assertFails(put(asUser(A), path(), bytes(), meta(A1, { name: 'beach.jpg' })), 'filename');
    await assertFails(put(asUser(A), path(), bytes(), meta(A1, { caption: 'x' })), 'caption');
    await assertFails(put(asUser(A), path(), bytes(), { contentType: OCTET }), 'no device');
    await assertFails(put(asUser(A), path(), bytes(), meta('A1')), 'malformed device id');
  });

  test('size bounds and opaque paths', async () => {
    await assertFails(put(asUser(A), path(), new Uint8Array(0), meta(A1)), 'empty');
    await assertFails(put(asUser(A), path(C, 'photo.jpg'), bytes(), meta(A1)), 'non-opaque media id');
    await assertFails(put(asUser(A), path(C, M.toUpperCase()), bytes(), meta(A1)));
    await assertFails(put(asUser(A), `conversations/${C}/media/${M}/x`, bytes(), meta(A1)));
    // The upper bound is the format maximum (64 MiB + overhead), checked
    // without uploading 64 MiB: one byte over at a small scale is covered
    // by the rule's exact constant.
    const rules = readRules('storage.rules');
    if (!rules.includes(`request.resource.size <= ${MAX}`)) throw new Error('size cap changed');
  });
});

describe('reading a ciphertext object', () => {
  test('members of the conversation can fetch bytes and metadata', async () => {
    await stored();
    await assertSucceeds(getBytes(ref(asUser(A), path())));
    await assertSucceeds(getBytes(ref(asUser(B), path())));
    await assertSucceeds(getMetadata(ref(asUser(B), path())));
  });

  test('outsiders, anonymous callers and other conversations cannot', async () => {
    await stored();
    await stored(OTHER);
    await assertFails(getBytes(ref(asUser(X), path())), 'not a member');
    await assertFails(getMetadata(ref(asUser(X), path())));
    await assertFails(getBytes(ref(anonymous(), path())), 'public');
    await assertFails(getBytes(ref(asUser(A), path(OTHER))), 'cross-account');
  });

  test('nobody can list or delete objects', async () => {
    await stored();
    await assertFails(listAll(ref(asUser(A), `conversations/${C}/media`)));
    await assertFails(deleteObject(ref(asUser(A), path())));
    await assertFails(deleteObject(ref(asUser(B), path())));
  });

  test('everything outside the media path stays denied', async () => {
    await assertFails(put(asUser(A), `conversations/${C}/other/${M}`, bytes(), meta(A1)));
    await assertFails(put(asUser(A), `media/${M}`, bytes(), meta(A1)));
    await assertFails(getBytes(ref(asUser(A), `users/${A}/avatar`)));
  });
});
