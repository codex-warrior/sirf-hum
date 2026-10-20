/**
 * Notification fan-out (Prompt 11, D-097, D-098). Pure logic over an
 * injected Firestore, sender and clock; the triggers in ../index.ts wire it.
 *
 * The server decides WHO gets a content-free wake-up from routing metadata
 * it already holds (conversation members, device statuses, sender IDs). It
 * never reads message bodies, keys or plaintext: handlers receive only the
 * routing fields they need. Only devices `active` at send time are targeted,
 * so a revoked, pending or reset device's leftover token is never used.
 * Results are counts only.
 */
import { type DocumentReference, type Firestore, Timestamp } from 'firebase-admin/firestore';
import type { TokenMessage } from 'firebase-admin/messaging';
import { Collections } from '../device/common';
import { type PushKind, pushMessage } from './payload';
import { pushTokenRef } from './tokens';

/** A token not refreshed for this long is stale: skipped and deleted. */
export const STALE_TOKEN_MS = 60 * 24 * 60 * 60 * 1000;

/** Per-message delivery outcome, from FCM error codes only. */
export type SendResult = 'ok' | 'unregistered' | 'failed';

/** Port to FCM (`getMessaging().sendEach` in production, a fake in tests). */
export type PushSender = (messages: TokenMessage[]) => Promise<SendResult[]>;

export interface FanoutResult {
  readonly kind: PushKind | 'none';
  readonly sent: number;
  readonly failed: number;
  readonly removed: number;
}

interface Target {
  readonly kind: PushKind;
  readonly token: string;
  readonly ref: DocumentReference;
}

interface Collected {
  readonly targets: Target[];
  readonly stale: DocumentReference[];
}

/** The active devices of `accountId` (minus `excludeDeviceId`) that hold a fresh token. */
async function collect(
  db: Firestore,
  accountId: string,
  kind: PushKind,
  excludeDeviceId: string | null,
  now: Date,
  into: Collected,
): Promise<void> {
  const active = await db
    .collection(Collections.users)
    .doc(accountId)
    .collection(Collections.devices)
    .where('status', '==', 'active')
    .get();
  const ids = active.docs.map((d) => d.id).filter((id) => id !== excludeDeviceId);
  const refs = ids.map((id) => pushTokenRef(db, id));
  const tokens = refs.length === 0 ? [] : await db.getAll(...refs);
  for (const snap of tokens) {
    if (!snap.exists) continue;
    const token = snap.get('token') as unknown;
    const updatedAt = snap.get('updatedAt') as unknown;
    // A document claiming another account is never used (defence in depth:
    // only registerPushToken writes these).
    if (snap.get('accountId') !== accountId || typeof token !== 'string') {
      into.stale.push(snap.ref);
      continue;
    }
    if (!(updatedAt instanceof Timestamp) || now.getTime() - updatedAt.toMillis() > STALE_TOKEN_MS) {
      into.stale.push(snap.ref);
      continue;
    }
    into.targets.push({ kind, token, ref: snap.ref });
  }
}

async function deliver(db: Firestore, send: PushSender, collected: Collected, kind: PushKind | 'none'): Promise<FanoutResult> {
  const { targets, stale } = collected;
  const results = targets.length === 0 ? [] : await send(targets.map((t) => pushMessage(t.token, t.kind)));
  const dead = [...stale];
  let sent = 0;
  let failed = 0;
  results.forEach((r, i) => {
    if (r === 'ok') sent += 1;
    else failed += 1;
    if (r === 'unregistered') dead.push(targets[i].ref);
  });
  await Promise.all(dead.map((ref) => ref.delete()));
  return { kind, sent, failed, removed: dead.length };
}

const members = async (db: Firestore, conversationId: string): Promise<string[]> => {
  const conv = await db.collection('conversations').doc(conversationId).get();
  const list = conv.get('members') as unknown;
  return Array.isArray(list) ? list.filter((m): m is string => typeof m === 'string') : [];
};

/**
 * A message document was created: the partner's active devices get the
 * generic visible notification; the sender's own other devices a silent
 * sync. Only `senderAccountId` and `senderDeviceId` are read.
 */
export async function onMessageCreated(
  db: Firestore,
  send: PushSender,
  conversationId: string,
  senderAccountId: string,
  senderDeviceId: string,
  now: Date,
): Promise<FanoutResult> {
  const collected: Collected = { targets: [], stale: [] };
  for (const account of await members(db, conversationId)) {
    const own = account === senderAccountId;
    await collect(db, account, own ? 'sync' : 'message', own ? senderDeviceId : null, now, collected);
  }
  return deliver(db, send, collected, 'message');
}

/** A commit was accepted: every other active device syncs (silent). */
export async function onCommitCreated(
  db: Firestore,
  send: PushSender,
  conversationId: string,
  senderDeviceId: string,
  now: Date,
): Promise<FanoutResult> {
  const collected: Collected = { targets: [], stale: [] };
  for (const account of await members(db, conversationId)) {
    await collect(db, account, 'sync', senderDeviceId, now, collected);
  }
  return deliver(db, send, collected, 'sync');
}

const resetStatus = (reset: unknown): unknown =>
  reset !== null && typeof reset === 'object' ? (reset as { status?: unknown }).status : undefined;

/**
 * The account trust record changed (Prompt 17B, D-132). Only the identity
 * reset's status is read; nothing else of the record.
 *
 * - Reset requested: every ACTIVE device of the account gets a visible,
 *   generic security alert, so the person can cancel a reset they did not
 *   ask for (a password thief's) from any trusted phone (D-082).
 * - Reset completed: the partner's active devices get the alert, because
 *   the partner now has a new identity to verify (D-128). The account's own
 *   devices were all revoked by the reset and hold no tokens.
 * - Reset cancelled: the account's active devices sync silently.
 */
export async function onTrustChanged(
  db: Firestore,
  send: PushSender,
  accountId: string,
  beforeReset: unknown,
  afterReset: unknown,
  now: Date,
): Promise<FanoutResult> {
  const was = resetStatus(beforeReset);
  const is = resetStatus(afterReset);
  const collected: Collected = { targets: [], stale: [] };
  if (is === 'pending' && was !== 'pending') {
    await collect(db, accountId, 'alert', null, now, collected);
    return deliver(db, send, collected, 'alert');
  }
  if (was === 'pending' && is === 'completed') {
    const partner = (await db.collection('accountPartners').doc(accountId).get()).get('partnerAccountId') as unknown;
    if (typeof partner === 'string') await collect(db, partner, 'alert', null, now, collected);
    return deliver(db, send, collected, 'alert');
  }
  if (was === 'pending' && is === undefined) {
    await collect(db, accountId, 'sync', null, now, collected);
    return deliver(db, send, collected, 'sync');
  }
  return { kind: 'none', sent: 0, failed: 0, removed: 0 };
}

/**
 * A device record changed. Leaving `active` (revoked, identity reset)
 * deletes its token at once. A revocation also wakes the remaining active
 * devices of the account and of its partner, so they refresh lineage and
 * remove the device from MLS without waiting for the next app resume.
 */
export async function onDeviceStatusChanged(
  db: Firestore,
  send: PushSender,
  accountId: string,
  deviceId: string,
  before: unknown,
  after: unknown,
  now: Date,
): Promise<FanoutResult> {
  if (after === 'active' || before === after) return { kind: 'none', sent: 0, failed: 0, removed: 0 };
  const collected: Collected = { targets: [], stale: [] };
  const own = await pushTokenRef(db, deviceId).get();
  if (own.exists) collected.stale.push(own.ref);
  if (after !== 'revoked') return deliver(db, send, collected, 'none');
  const partner = (await db.collection('accountPartners').doc(accountId).get()).get('partnerAccountId') as unknown;
  for (const account of [accountId, ...(typeof partner === 'string' ? [partner] : [])]) {
    await collect(db, account, 'sync', deviceId, now, collected);
  }
  return deliver(db, send, collected, 'sync');
}
