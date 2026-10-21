// Content-free push payloads and push-token binding (Prompt 11, D-097,
// D-098): no plaintext, no identifiers, nothing logged. Runs against the
// compiled output (`npm run build` first).
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { URL } from 'node:url';
import { readdirSync, readFileSync } from 'node:fs';
import { describe, test } from 'node:test';
import payloadModule from '../lib/notification/payload.js';
import tokensModule from '../lib/notification/tokens.js';
import proofModule from '../lib/device/proof.js';
import { makeDevice, makeProof } from './support.mjs';

const { pushMessage, NOTIFICATION_BODY, NOTIFICATION_TITLE } = payloadModule;
const { tokenHash, requireToken } = tokensModule;
const { ProofPurpose, verifyDeviceProof } = proofModule;

const TOKEN = 'fcm-token:APA91b_example-0123456789';

/** Every string anywhere in a JSON-like value. */
function strings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => strings(v, out));
  else if (value && typeof value === 'object') Object.entries(value).forEach(([k, v]) => strings(v, strings(k, out)));
  return out;
}

describe('push payloads (D-097)', () => {
  test('a message wake-up is generic and constant apart from the token', () => {
    assert.deepEqual(pushMessage(TOKEN, 'message'), {
      token: TOKEN,
      data: { v: '1', k: 'm' },
      android: {
        priority: 'high',
        collapseKey: 'sh_m',
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          title: 'Sirf Hum',
          body: 'You have a new message',
          tag: 'sh',
          visibility: 'private',
        },
      },
    });
  });

  test('a sync wake-up is silent and data-only', () => {
    assert.deepEqual(pushMessage(TOKEN, 'sync'), {
      token: TOKEN,
      data: { v: '1', k: 's' },
      android: { priority: 'normal', collapseKey: 'sh_s', ttl: 60 * 60 * 1000 },
    });
  });

  test('a security alert is visible, generic and has its own slot (D-132)', () => {
    assert.deepEqual(pushMessage(TOKEN, 'alert'), {
      token: TOKEN,
      data: { v: '1', k: 'a' },
      android: {
        priority: 'high',
        collapseKey: 'sh_a',
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          title: 'Sirf Hum',
          body: 'Review a security change',
          tag: 'sh_a',
          visibility: 'private',
        },
      },
    });
  });

  test('no identifiers, topics, previews or other platforms ever appear', () => {
    for (const kind of ['message', 'sync', 'alert']) {
      const m = pushMessage(TOKEN, kind);
      assert.deepEqual(Object.keys(m).sort(), ['android', 'data', 'token']);
      for (const s of strings({ ...m, token: undefined })) {
        assert.doesNotMatch(s, /[0-9a-f]{32}/, 'no conversation, message, media or device ID');
        assert.doesNotMatch(s, /account|conversation|media|device|photo|❤/i);
        assert.ok(s.length <= 32, `short constant: ${s}`);
      }
    }
    // The visible text names no person and shows no content.
    assert.equal(NOTIFICATION_TITLE, 'Sirf Hum');
    assert.equal(NOTIFICATION_BODY, 'You have a new message');
  });
});

describe('push token binding (D-098)', () => {
  test('the challenge binds the exact token, or clearing', () => {
    assert.equal(tokenHash(TOKEN), tokenHash(TOKEN));
    assert.notEqual(tokenHash(TOKEN), tokenHash(`${TOKEN}x`));
    assert.notEqual(tokenHash(null), tokenHash('-'));
    assert.match(tokenHash(TOKEN), /^[0-9a-f]{64}$/);
    assert.ok(!tokenHash(TOKEN).includes(TOKEN));
  });

  test('tokens are validated before use', () => {
    assert.equal(requireToken(null), null);
    assert.equal(requireToken(TOKEN), TOKEN);
    for (const bad of ['', ' ', 'a b', 'x'.repeat(4097), 42, undefined, {}]) {
      assert.throws(() => requireToken(bad));
    }
  });

  test('a push-token proof is a separate signed domain', () => {
    assert.equal(ProofPurpose.pushToken, 3);
    const d = makeDevice(0x61, 0x62, '0f0e0d0c0b0a09080706050403020100');
    const challenge = Buffer.alloc(32, 0x33);
    const { signature } = makeProof({
      device: d.device,
      accountId: 'acct',
      deviceId: d.deviceId,
      certificate: d.certificate,
      challenge,
      purpose: ProofPurpose.pushToken,
    });
    assert.ok(verifyDeviceProof(ProofPurpose.pushToken, 'acct', d.certificate, challenge, signature));
    for (const other of [ProofPurpose.activation, ProofPurpose.enrollment]) {
      assert.throws(() => verifyDeviceProof(other, 'acct', d.certificate, challenge, signature));
    }
  });
});

describe('no content reaches Functions code or logs (static guard)', () => {
  const src = new URL('../src/', import.meta.url);
  const notification = readdirSync(new URL('notification/', src)).map((f) => `notification/${f}`);

  test('notification modules never log and never touch message content', () => {
    for (const file of notification) {
      const text = readFileSync(new URL(file, src), 'utf8');
      assert.doesNotMatch(text, /logger|console\./, `${file} logs`);
      assert.doesNotMatch(text, /\bciphertext\b|\.data\(\)/, `${file} reads documents whole`);
    }
  });

  test('the triggers read routing fields only and log counts only', () => {
    const index = readFileSync(new URL('index.ts', src), 'utf8');
    const triggers = index.slice(index.indexOf('notifications (Prompt 11)'));
    assert.doesNotMatch(triggers, /\.data\(\)|ciphertext'|\.get\('ciphertext/);
    const reads = [...triggers.matchAll(/\.get\('([A-Za-z]+)'\)/g)].map((m) => m[1]);
    // `reset`: the identity-reset status only (D-132), never the record.
    // `members`: who to wake when a couple is dissolved (D-136).
    assert.deepEqual([...new Set(reads)].sort(), ['members', 'reset', 'senderAccountId', 'senderDeviceId', 'status']);
    const logs = [...triggers.matchAll(/logger\.\w+\(([^;]*)\);/g)].map((m) => m[1]);
    assert.equal(logs.length, 5);
    for (const args of logs) assert.match(args, /^'push_fanout', \{ \.\.\.result \}$/);
  });
});
