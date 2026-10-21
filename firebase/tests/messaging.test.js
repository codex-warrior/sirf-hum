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
  // ACCOUNT, never the device. For MESSAGES the rules still check only that
  // the claimed sender is an active device of the caller's account, so a
  // session left on revoked device A2 may write as active A1; MLS refuses
  // it on receipt (D-089), so that is noise, not a confidentiality issue.
  // COMMITS were the sharp edge (P17-05): filler bytes used to win the
  // epoch and stall every device. Since Prompt 17B (D-127) commits are
  // server-only behind a device-key proof, so this half has flipped.
  test('documented limit: messages are authorized per account; commits no longer are', async () => {
    await provision();
    await assertSucceeds(sendAs(A, { senderDeviceId: A1 }), 'any session of A may claim A1 for a message');
    // commitDoc's `commit` is bytes(500): filler, not an MLS commit.
    await assertFails(commitBatch(A, { commit: { senderDeviceId: A1 } }), 'a session alone cannot move the epoch');
  });

  test('6. a closed conversation accepts nothing', async () => {
    await provision({ state: 'closed' });
    await assertFails(sendAs(A));
  });

  // Prompt 17C. Unpairing (D-136) closes the conversation: its contents
  // become unreadable for both former partners, while the document still
  // tells their devices it closed. Recovery (D-135) retires it: the couple
  // still reads its own history, but nothing new can be written.
  test('closed (unpaired): contents unreadable, document readable, nothing writable', async () => {
    await provision({ state: 'closed' });
    await seed(`${conv()}/messages/${MID}`, { ...message(), serverTime: Timestamp.now() });
    await seed(`${conv()}/commits/1`, { ...commitDoc(), createdAt: Timestamp.now() });
    await seed(`${conv()}/welcomes/${B1}_1`, { ...welcomeDoc(), createdAt: Timestamp.now() });
    await seed(`${conv()}/keyPackages/${A1}`, { schemaVersion: 1, accountId: A, deviceId: A1, keyPackage: bytes(100), updatedAt: Timestamp.now() });
    for (const who of [A, B]) {
      await assertSucceeds(getDoc(doc(asUser(who), conv())), 'learns it closed');
      for (const sub of [`messages/${MID}`, 'commits/1', `welcomes/${B1}_1`, `keyPackages/${A1}`]) {
        await assertFails(getDoc(doc(asUser(who), `${conv()}/${sub}`)), `${who} ${sub}`);
      }
    }
    await assertFails(getDocs(collection(asUser(A), `${conv()}/messages`)));
    await assertFails(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`), { schemaVersion: 1, accountId: A, deviceId: A1, keyPackage: bytes(100), updatedAt: serverTimestamp() }));
  });

  test('retired (recovered): the couple still reads its history; nothing new is written', async () => {
    await provision({ state: 'retired' });
    await seed(`${conv()}/messages/${MID}`, { ...message(), serverTime: Timestamp.now() });
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/messages/${MID}`)));
    await assertFails(sendAs(A, {}, MID2));
    await assertFails(setDoc(doc(asUser(A), `${conv()}/keyPackages/${A1}`), { schemaVersion: 1, accountId: A, deviceId: A1, keyPackage: bytes(100), updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(asUser(X), `${conv()}/messages/${MID}`)));
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

// Since Prompt 17B (D-127) only submitConversationCommit writes commits,
// Welcomes and the epoch, after verifying a device-key proof
// (functions/test/emulator/commit.test.mjs). Every client write that the
// D-088 rules used to accept is now refused, whatever its shape.
describe('commits, Welcomes and the epoch are server-only (D-127)', () => {
  test('no client batch can commit an epoch, even a well-formed one from an active device', async () => {
    await provision({ epoch: 1 });
    await assertFails(commitBatch(A, { epoch: 1 }), 'well-formed, active device, current epoch');
    await assertFails(commitBatch(B, { epoch: 1, commit: { senderDeviceId: B1 } }), 'the partner');
    await assertFails(commitBatch(A, { epoch: 1, welcomes: [{ targetDeviceId: B1 }] }), 'with Welcomes');
    await assertFails(commitBatch(A, { epoch: 1, bump: false }), 'commit alone');
    await assertFails(commitBatch(A, { commit: { senderDeviceId: A2 } }), 'revoked device');
    await assertFails(commitBatch(X, { commit: { senderDeviceId: X1 } }), 'outsider');
    await assertFails(updateDoc(doc(asUser(A), conv()), { epoch: 2 }), 'epoch alone');
    await assertFails(setDoc(doc(asUser(A), `${conv()}/welcomes/${B1}_1`), welcomeDoc()), 'Welcome alone');
    const after = await getDoc(doc(asUser(B), conv()));
    if (after.data().epoch !== 1) throw new Error('epoch moved');
  });

  test('server-written commits and Welcomes are member-readable and immutable', async () => {
    await provision({ epoch: 2 });
    await seed(`${conv()}/commits/1`, { ...commitDoc(), createdAt: Timestamp.now() });
    await seed(`${conv()}/welcomes/${B1}_1`, { ...welcomeDoc(), createdAt: Timestamp.now() });
    const ref = doc(asUser(A), `${conv()}/commits/1`);
    await assertFails(updateDoc(ref, { commit: bytes(500, 7) }));
    await assertFails(deleteDoc(ref));
    await assertFails(deleteDoc(doc(asUser(B), `${conv()}/welcomes/${B1}_1`)));
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/commits/1`)));
    await assertSucceeds(getDoc(doc(asUser(B), `${conv()}/welcomes/${B1}_1`)));
    await assertFails(getDoc(doc(asUser(X), `${conv()}/commits/1`)));
    await assertFails(getDoc(doc(asUser(X), `${conv()}/welcomes/${B1}_1`)));
    // Messages follow the server's epoch: old refused, current accepted.
    await assertFails(sendAs(B, { senderDeviceId: B1, epoch: 1 }));
    await assertSucceeds(sendAs(B, { senderDeviceId: B1, epoch: 2 }));
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
