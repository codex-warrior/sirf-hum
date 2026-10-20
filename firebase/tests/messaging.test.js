// Messaging rules (Prompt 10, docs/security/E2EE-MESSAGING-DESIGN.md §5–§6,
// D-086, D-088, D-089). Firebase authorizes access to ciphertext per
// account; it never decides cryptographic validity. Every allowed case has
// denied neighbours.
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
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const readRules = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

let env;
before(async () => {
  // Own demo project: node --test runs files in parallel, and clearing or
  // seeding partner records must not leak into the device-rule tests.
  env = await initializeTestEnvironment({
    projectId: 'demo-sirf-hum-messaging',
    firestore: { rules: readRules('firestore.rules') },
  });
});
afterEach(() => env.clearFirestore());
after(() => env.cleanup());

const A = 'accountA';
const B = 'accountB';
const X = 'accountX'; // outsider
const C = 'c0ffee00c0ffee00c0ffee00c0ffee00';
const OTHER_C = 'deadbeefdeadbeefdeadbeefdeadbeef';
const A1 = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const A2 = 'a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2';
const B1 = 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1';
const X1 = 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1';
const MID = '0123456789abcdef0123456789abcdef';
const MID2 = 'fedcba9876543210fedcba9876543210';

const asUser = (uid) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();
const bytes = (n, fill = 1) => Bytes.fromUint8Array(new Uint8Array(n).fill(fill));
const conv = (c = C) => `conversations/${c}`;

async function seed(path, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
}

/** What provisionConversation writes (server, Admin SDK). */
async function provision({ epoch = 1, state = 'active', c = C, members = [A, B] } = {}) {
  await seed(conv(c), {
    schemaVersion: 1,
    protocolVersion: 1,
    ciphersuite: 1,
    members,
    pairingId: 'p1',
    state,
    epoch,
    createdAt: Timestamp.now(),
  });
  await seed(`accountPartners/${A}`, { schemaVersion: 1, partnerAccountId: B, conversationId: c });
  await seed(`accountPartners/${B}`, { schemaVersion: 1, partnerAccountId: A, conversationId: c });
  for (const [account, device, status] of [
    [A, A1, 'active'],
    [A, A2, 'revoked'],
    [B, B1, 'active'],
    [B, 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2', 'pending'],
    [X, X1, 'active'],
  ]) {
    await seed(`users/${account}/devices/${device}`, { schemaVersion: 1, status, certificate: bytes(185) });
  }
  await seed(`accountTrust/${A}`, { trustEpoch: 3, bootstrapOpen: false, firstDeviceId: A1 });
}

const message = (overrides = {}) => ({
  schemaVersion: 1,
  protocolVersion: 1,
  senderAccountId: A,
  senderDeviceId: A1,
  epoch: 1,
  ciphertext: bytes(300),
  serverTime: serverTimestamp(),
  ...overrides,
});

const sendAs = (uid, overrides = {}, id = MID, c = C) =>
  setDoc(doc(asUser(uid), `${conv(c)}/messages/${id}`), message({ senderAccountId: uid, ...overrides }));

const commitDoc = (overrides = {}) => ({
  schemaVersion: 1,
  epoch: 1,
  senderAccountId: A,
  senderDeviceId: A1,
  commit: bytes(500),
  createdAt: serverTimestamp(),
  ...overrides,
});

const welcomeDoc = (overrides = {}) => ({
  schemaVersion: 1,
  epoch: 1,
  targetDeviceId: B1,
  senderAccountId: A,
  senderDeviceId: A1,
  welcome: bytes(800),
  createdAt: serverTimestamp(),
  ...overrides,
});

/** The batch a client writes to win epoch `epoch` (D-088). */
function commitBatch(uid, { epoch = 1, commit = {}, welcomes = [], bumpTo = epoch + 1, bump = true } = {}) {
  const db = asUser(uid);
  const batch = writeBatch(db);
  batch.set(doc(db, `${conv()}/commits/${epoch}`), commitDoc({ epoch, senderAccountId: uid, ...commit }));
  if (bump) batch.update(doc(db, conv()), { epoch: bumpTo });
  for (const w of welcomes) {
    const data = welcomeDoc({ epoch, senderAccountId: uid, ...w });
    batch.set(doc(db, `${conv()}/welcomes/${data.targetDeviceId}_${data.epoch}`), data);
  }
  return batch.commit();
}

// --------------------------------------------------------------- authority

describe('conversation authority (D-086)', () => {
  test('clients cannot create a conversation or declare membership', async () => {
    const fake = {
      schemaVersion: 1,
      protocolVersion: 1,
      ciphersuite: 1,
      members: [A, B],
      pairingId: 'p1',
      state: 'active',
      epoch: 0,
      createdAt: serverTimestamp(),
    };
    await assertFails(setDoc(doc(asUser(A), conv()), fake));
    await assertFails(setDoc(doc(asUser(A), 'pairings/p1'), { status: 'accepted', accounts: [A, B] }));
    await assertFails(setDoc(doc(asUser(A), `accountPartners/${A}`), { partnerAccountId: B }));
  });

  test('members read; outsiders and anonymous cannot', async () => {
    await provision();
    await assertSucceeds(getDoc(doc(asUser(A), conv())));
    await assertSucceeds(getDoc(doc(asUser(B), conv())));
    await assertFails(getDoc(doc(asUser(X), conv())));
    await assertFails(getDoc(doc(anonymous(), conv())));
    await assertFails(getDoc(doc(asUser(A), conv(OTHER_C))));
  });

  test('membership, state and server metadata are not client-writable', async () => {
    await provision();
    for (const change of [
      { members: [A, X] },
      { members: [A, B, X] },
      { state: 'closed' },
      { pairingId: 'p2' },
      { epoch: 7 },
      { epoch: 2, members: [A, X] },
    ]) {
      await assertFails(updateDoc(doc(asUser(A), conv()), change));
    }
    await assertFails(updateDoc(doc(asUser(X), conv()), { members: [X, B] }));
    await assertFails(deleteDoc(doc(asUser(A), conv())));
  });

  test('pairings and partner records are server-only; partners read only their own', async () => {
    await provision();
    await seed('pairings/p1', { status: 'accepted', accounts: [A, B] });
    await assertFails(getDoc(doc(asUser(A), 'pairings/p1')));
    await assertSucceeds(getDoc(doc(asUser(A), `accountPartners/${A}`)));
    await assertFails(getDoc(doc(asUser(A), `accountPartners/${B}`)));
    await assertFails(updateDoc(doc(asUser(A), `accountPartners/${A}`), { partnerAccountId: X }));
  });

  test("partners read each other's public device directory; outsiders cannot", async () => {
    await provision();
    await assertSucceeds(getDocs(collection(asUser(B), `users/${A}/devices`)));
    await assertSucceeds(getDoc(doc(asUser(B), `accountTrust/${A}`)));
    await assertFails(getDocs(collection(asUser(X), `users/${A}/devices`)));
    await assertFails(getDoc(doc(asUser(X), `accountTrust/${A}`)));
    await assertFails(getDocs(collection(asUser(A), `users/${X}/devices`)));
    await assertFails(updateDoc(doc(asUser(B), `users/${A}/devices/${A1}`), { status: 'revoked' }));
  });
});

// ---------------------------------------------------------------- messages

describe('messages (D-089)', () => {
  test('a member sends ciphertext from an active device at the current epoch', async () => {
    await provision();
    await assertSucceeds(sendAs(A));
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/messages/${MID}`)));
    await assertSucceeds(
      getDocs(query(collection(asUser(B), `${conv()}/messages`), where('epoch', '==', 1))),
    );
  });

  test('1. an account outside the conversation can neither read nor write', async () => {
    await provision();
    await assertFails(sendAs(X, { senderDeviceId: X1 }));
    await seed(`${conv()}/messages/${MID}`, { ...message(), serverTime: Timestamp.now() });
    await assertFails(getDoc(doc(asUser(X), `${conv()}/messages/${MID}`)));
    await assertFails(getDocs(collection(asUser(X), `${conv()}/messages`)));
    await assertFails(getDocs(collection(anonymous(), `${conv()}/messages`)));
  });

  test('2–5. wrong account, revoked, pending or fake sender devices are refused', async () => {
    await provision();
    await assertFails(sendAs(A, { senderAccountId: B }), 'wrong account claimed');
    await assertFails(sendAs(A, { senderDeviceId: B1 }), "another account's device");
    await assertFails(sendAs(A, { senderDeviceId: A2 }), 'revoked device');
    await assertFails(sendAs(B, { senderDeviceId: 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2' }), 'pending device');
    await assertFails(sendAs(A, { senderDeviceId: 'abababababababababababababababab' }), 'unknown device');
    await assertFails(sendAs(A, { senderDeviceId: 'not-hex' }), 'malformed device id');
  });

  // Prompt 17 review (THREAT-MODEL E77): Firebase Auth identifies the
  // ACCOUNT, never the device. The rules check that the claimed sender is
  // an active device of the caller's account, but cannot tell which of the
  // account's sessions is calling: a session left on revoked device A2 may
  // write as active A1. MLS is what refuses it (receivers compare the
  // envelope's device with the authenticated MLS sender, D-089, and reject
  // a revoked credential), so this is availability, not confidentiality.
  // If device-bound authorization arrives, this test must flip.
  test('documented limit: rules authorize accounts, not devices', async () => {
    await provision();
    // Indistinguishable from A1's own session: both are just "accountA".
    await assertSucceeds(sendAs(A, { senderDeviceId: A1 }), 'any session of A may claim A1');
    await assertSucceeds(commitBatch(A, { commit: { senderDeviceId: A1 } }), 'including an epoch commit');
  });

  test('6. a closed conversation accepts nothing', async () => {
    await provision({ state: 'closed' });
    await assertFails(sendAs(A));
  });

  test('7–9. ciphertext, sender, ID, epoch and conversation cannot be edited', async () => {
    await provision();
    await assertSucceeds(sendAs(A));
    const ref = doc(asUser(A), `${conv()}/messages/${MID}`);
    for (const change of [
      { ciphertext: bytes(300, 2) },
      { senderDeviceId: B1 },
      { senderAccountId: B },
      { epoch: 2 },
      { schemaVersion: 2 },
    ]) {
      await assertFails(updateDoc(ref, change));
    }
    // Overwriting (a replayed or rewritten create on the same ID).
    await assertFails(sendAs(A));
    await assertFails(sendAs(A, { ciphertext: bytes(300, 9) }));
    // "Moving" to another conversation means writing it there as a member
    // of that conversation; A is not a member of OTHER_C.
    await provision({ c: OTHER_C, members: [B, X] });
    await assertFails(sendAs(A, {}, MID, OTHER_C));
  });

  test('10. nobody can delete a message (not even its sender)', async () => {
    await provision();
    await assertSucceeds(sendAs(A));
    await assertFails(deleteDoc(doc(asUser(A), `${conv()}/messages/${MID}`)));
    await assertFails(deleteDoc(doc(asUser(B), `${conv()}/messages/${MID}`)));
  });

  test('11. server-owned fields: the server time cannot be forged', async () => {
    await provision();
    await assertFails(sendAs(A, { serverTime: Timestamp.fromMillis(0) }));
    await assertFails(sendAs(A, { serverTime: Timestamp.fromMillis(Date.now() + 3_600_000) }));
  });

  test('12. a stale epoch (old write replayed after a commit) is refused', async () => {
    await provision({ epoch: 3 });
    await assertFails(sendAs(A, { epoch: 2 }));
    await assertFails(sendAs(A, { epoch: 4 }), 'future epoch');
    await assertSucceeds(sendAs(A, { epoch: 3 }));
  });

  test('13. plaintext or any extra field is refused', async () => {
    await provision();
    for (const extra of [
      { text: 'I love you ❤️' },
      { preview: 'hi' },
      { body: bytes(10) },
      { senderName: 'Riya' },
      { clientTime: Timestamp.now() },
    ]) {
      await assertFails(sendAs(A, extra));
    }
  });

  test('14. malformed envelopes are refused', async () => {
    await provision();
    const cases = [
      { schemaVersion: 2 },
      { protocolVersion: 0 },
      { epoch: '1' },
      { epoch: 0 },
      { ciphertext: 'not bytes' },
      { ciphertext: bytes(0) },
      { ciphertext: bytes(32769) },
    ];
    for (const c of cases) await assertFails(sendAs(A, c));
    const missing = message();
    delete missing.ciphertext;
    await assertFails(setDoc(doc(asUser(A), `${conv()}/messages/${MID}`), missing));
    await assertFails(sendAs(A, {}, 'NOT-A-HEX-ID'));
    await assertFails(sendAs(A, {}, MID.toUpperCase()));
    await assertSucceeds(sendAs(A, { ciphertext: bytes(32768) }, MID2));
  });
});

// ----------------------------------------------------------------- commits

describe('commits: first commit wins (D-088)', () => {
  test('a member commits the current epoch atomically with the epoch bump', async () => {
    await provision({ epoch: 1 });
    await assertSucceeds(commitBatch(A, { epoch: 1 }));
    const after = await getDoc(doc(asUser(B), conv()));
    if (after.data().epoch !== 2) throw new Error('epoch not advanced');
    // Messages at the old epoch are now refused; the new one is accepted.
    await assertFails(sendAs(B, { senderDeviceId: B1, epoch: 1 }));
    await assertSucceeds(sendAs(B, { senderDeviceId: B1, epoch: 2 }));
  });

  test('a second commit for the same epoch loses', async () => {
    await provision({ epoch: 1 });
    await assertSucceeds(commitBatch(A, { epoch: 1 }));
    await assertFails(commitBatch(B, { epoch: 1, commit: { senderDeviceId: B1 } }));
    // ...and cannot be squeezed in without a bump either.
    await assertFails(commitBatch(B, { epoch: 1, commit: { senderDeviceId: B1 }, bump: false }));
  });

  test('forged commits are refused', async () => {
    await provision({ epoch: 1 });
    await assertFails(commitBatch(A, { epoch: 1, bump: false }), 'no epoch bump');
    await assertFails(commitBatch(A, { epoch: 1, bumpTo: 3 }), 'skips an epoch');
    await assertFails(commitBatch(A, { epoch: 0, bumpTo: 2 }), 'stale epoch');
    await assertFails(commitBatch(A, { epoch: 2, bumpTo: 2 }), 'future epoch');
    await assertFails(commitBatch(A, { commit: { senderDeviceId: A2 } }), 'revoked device');
    await assertFails(commitBatch(A, { commit: { senderDeviceId: B1 } }), "another account's device");
    await assertFails(commitBatch(A, { commit: { senderAccountId: B } }), 'forged account');
    await assertFails(commitBatch(A, { commit: { commit: bytes(131073) } }), 'oversized');
    await assertFails(commitBatch(A, { commit: { plaintext: 'x' } }), 'extra field');
    await assertFails(commitBatch(X, { commit: { senderDeviceId: X1 } }), 'outsider');
    // An epoch bump without any commit.
    await assertFails(updateDoc(doc(asUser(A), conv()), { epoch: 2 }));
  });

  test('commits are immutable once accepted', async () => {
    await provision({ epoch: 1 });
    await assertSucceeds(commitBatch(A, { epoch: 1 }));
    const ref = doc(asUser(A), `${conv()}/commits/1`);
    await assertFails(updateDoc(ref, { commit: bytes(500, 7) }));
    await assertFails(deleteDoc(ref));
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/commits/1`)));
    await assertFails(getDoc(doc(asUser(X), `${conv()}/commits/1`)));
  });
});

describe('welcomes', () => {
  test('only beside their own accepted commit', async () => {
    await provision({ epoch: 1 });
    await assertSucceeds(commitBatch(A, { epoch: 1, welcomes: [{ targetDeviceId: B1 }, { targetDeviceId: X1 }] }));
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/welcomes/${B1}_1`)));
    // Alone, later, or for another epoch: refused.
    const lone = welcomeDoc({ epoch: 2, targetDeviceId: B1 });
    await assertFails(setDoc(doc(asUser(A), `${conv()}/welcomes/${B1}_2`), lone));
    await assertFails(setDoc(doc(asUser(A), `${conv()}/welcomes/${B1}_1`), welcomeDoc()));
    await assertFails(getDoc(doc(asUser(X), `${conv()}/welcomes/${B1}_1`)));
  });

  test("a welcome must name its commit's sender and the right document ID", async () => {
    await provision({ epoch: 1 });
    await assertFails(commitBatch(A, { epoch: 1, welcomes: [{ senderDeviceId: 'abababababababababababababababab' }] }));
    const db = asUser(A);
    const batch = writeBatch(db);
    batch.set(doc(db, `${conv()}/commits/1`), commitDoc());
    batch.update(doc(db, conv()), { epoch: 2 });
    batch.set(doc(db, `${conv()}/welcomes/${B1}_9`), welcomeDoc());
    await assertFails(batch.commit());
  });
});

describe('key packages', () => {
  test('a member publishes for its own active device only', async () => {
    await provision();
    const kp = (overrides = {}) => ({
      schemaVersion: 1,
      accountId: A,
      deviceId: A1,
      keyPackage: bytes(400),
      updatedAt: serverTimestamp(),
      ...overrides,
    });
    await assertSucceeds(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`), kp()));
    await assertSucceeds(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`), kp({ keyPackage: bytes(400, 2) })));
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/keyPackages/${A1}`)));
    await assertFails(getDoc(doc(asUser(X), `${conv()}/keyPackages/${A1}`)));
    await assertFails(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A2}`), kp({ deviceId: A2 })), 'revoked');
    await assertFails(setDoc(doc(asUser(A), `${conv()}/keyPackages/${B1}`), kp({ deviceId: B1 })), "B's device");
    await assertFails(
      setDoc(doc(asUser(B), `${conv()}/keyPackages/${A1}`), kp({ accountId: B })),
      "overwrite A's key package",
    );
    await assertFails(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`), kp({ keyPackage: bytes(16385) })));
    await assertFails(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`), kp({ extra: 1 })));
    await assertFails(deleteDoc(doc(asUser(B), `${conv()}/keyPackages/${A1}`)));
    await assertSucceeds(deleteDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`)));
  });
});
