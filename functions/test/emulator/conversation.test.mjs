// Conversation provisioning against the Firestore emulator (Prompt 10,
// D-086). The pairing record is seeded with the Admin SDK: it stands in for
// the future pairing phase, which does not exist yet.
// Run: npm run test:emulator (needs Java + firebase-tools; builds first).
import assert from 'node:assert/strict';
import process from 'node:process';
import { URL } from 'node:url';
import { after, before, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import provisionModule from '../../lib/conversation/provision.js';
import { readFileSync } from 'node:fs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run through `npm run test:emulator`');

const { provisionConversation, ProvisionError } = provisionModule;

let app;
let db;
before(() => {
  app = initializeApp({ projectId: 'demo-sirf-hum' }, 'conversation-test');
  db = getFirestore(app);
});
after(() => deleteApp(app));

let n = 0;
const account = () => `cv${++n}x${Date.now()}`;

async function rejectsWith(promise, failure) {
  await assert.rejects(promise, (e) => {
    assert.ok(e instanceof ProvisionError, `expected ProvisionError(${failure}), got ${e}`);
    assert.equal(e.failure, failure);
    return true;
  });
}

async function pairing(data) {
  const id = `p${++n}x${Date.now()}`;
  await db.doc(`pairings/${id}`).set(data);
  return id;
}

describe('provisionConversation (D-086)', () => {
  test('is not reachable from clients: no callable is exported', () => {
    // Read the compiled entrypoint instead of importing it (importing would
    // initialize the Admin SDK and Functions params as a side effect).
    const source = readFileSync(new URL('../../lib/index.js', import.meta.url), 'utf8');
    const exported = [...source.matchAll(/exports\.(\w+)\s*=/g)].map((m) => m[1]);
    assert.ok(exported.includes('revokeDevice'), 'export scan works');
    for (const name of exported) {
      assert.ok(!/conversation|pairing|provision/i.test(name), `unexpected export ${name}`);
    }
    assert.ok(!source.includes('provisionConversation'), 'not wired into any function');
  });

  test('an accepted pairing yields one conversation with both members', async () => {
    const [a, b] = [account(), account()];
    const id = await pairing({ status: 'accepted', accounts: [b, a] });
    const result = await provisionConversation(db, id);
    assert.equal(result.created, true);
    assert.match(result.conversationId, /^[0-9a-f]{32}$/);
    const conv = (await db.doc(`conversations/${result.conversationId}`).get()).data();
    assert.deepEqual(conv.members, [a, b].sort());
    assert.equal(conv.epoch, 0);
    assert.equal(conv.state, 'active');
    assert.equal(conv.schemaVersion, 1);
    assert.equal(conv.protocolVersion, 1);
    assert.equal(conv.ciphersuite, 1);
    assert.deepEqual(
      Object.keys(conv).sort(),
      ['ciphersuite', 'createdAt', 'epoch', 'members', 'pairingId', 'protocolVersion', 'schemaVersion', 'state'],
      'no message data, keys or plaintext',
    );
    assert.equal((await db.doc(`accountPartners/${a}`).get()).get('partnerAccountId'), b);
    assert.equal((await db.doc(`accountPartners/${b}`).get()).get('partnerAccountId'), a);
    assert.equal((await db.doc(`pairings/${id}`).get()).get('conversationId'), result.conversationId);
  });

  test('is idempotent and safe under concurrency', async () => {
    const id = await pairing({ status: 'accepted', accounts: [account(), account()] });
    const results = await Promise.all([1, 2, 3].map(() => provisionConversation(db, id)));
    const ids = new Set(results.map((r) => r.conversationId));
    assert.equal(ids.size, 1);
    assert.equal(results.filter((r) => r.created).length, 1);
  });

  test('refuses anything but an accepted, valid pairing', async () => {
    await rejectsWith(provisionConversation(db, 'missing-pairing'), 'pairing_not_found');
    await rejectsWith(provisionConversation(db, 'bad/id'), 'pairing_invalid');
    for (const status of ['invited', 'declined', 'revoked', null]) {
      const id = await pairing({ status, accounts: [account(), account()] });
      await rejectsWith(provisionConversation(db, id), 'pairing_not_accepted');
    }
    const a = account();
    for (const accounts of [[a, a], [a], [a, account(), account()], [a, 'bad/uid'], 'x', null]) {
      const id = await pairing({ status: 'accepted', accounts });
      await rejectsWith(provisionConversation(db, id), 'pairing_invalid');
    }
  });

  test('one couple per account (V1)', async () => {
    const [a, b, c] = [account(), account(), account()];
    await provisionConversation(db, await pairing({ status: 'accepted', accounts: [a, b] }));
    await rejectsWith(provisionConversation(db, await pairing({ status: 'accepted', accounts: [a, c] })), 'already_paired');
  });

  test('a conversation ID collision fails instead of overwriting', async () => {
    const fixed = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await db.doc(`conversations/${fixed}`).set({ members: ['someone', 'else'] });
    const id = await pairing({ status: 'accepted', accounts: [account(), account()] });
    await assert.rejects(provisionConversation(db, id, () => fixed));
    assert.deepEqual((await db.doc(`conversations/${fixed}`).get()).get('members'), ['someone', 'else']);
  });
});
