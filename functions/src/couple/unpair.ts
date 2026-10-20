/**
 * Secure unpairing (Prompt 17C, D-136; supersedes D-134).
 *
 * Either partner may end the couple **unilaterally** — an abusive partner
 * must not be able to hold someone in the relationship — but only from one
 * of their own ACTIVE devices: a Firebase session or password alone can
 * never destroy the couple's trust relationship.
 *
 *   requestUnpairChallenge   single-use nonce bound to (account, device,
 *                            couple)
 *   unpairCouple             verifies, in one transaction, the challenge,
 *                            the device (active NOW), the couple (active,
 *                            the caller a member, the caller's partner
 *                            record naming it) and the device proof
 *                            (purpose `unpair` = 8) over:
 *
 *   SHA-256( "SirfHum-Unpair-v1" | u8 1 | nonce[32] | u32 len | account
 *          | device id[16] | couple id[16] )
 *
 * Then: couple `dissolved` (never reused), every conversation of the couple
 * `closed` (no reads or writes by clients), both `accountPartners` records
 * deleted (partner reads end). Irreversible; re-pairing is a new couple
 * through the full two-consent flow. Each phone keeps what it already
 * decrypted; the server keeps ciphertext it can never read.
 */
import { createHash, randomBytes } from 'node:crypto';
import { FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { ConversationCollections } from '../conversation/provision';
import { InvalidCertificateError, lengthPrefixed } from '../device/certificate';
import {
  Collections,
  DEVICE_ID_PATTERN,
  DeviceError,
  type DeviceFailure,
  deviceRef,
  input,
  RECORD_ID_PATTERN,
  requireAccount,
  requireBytes,
  requirePattern,
  toUnixSeconds,
  TTL,
} from '../device/common';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from '../device/proof';
import { consume, requireBudget } from '../device/rateLimit';
import { type IssuedChallenge, recordFailure } from '../device/registration';
import { CoupleCollections } from './state';

export const UNPAIR_PURPOSE = 'unpair';
const CONTEXT = Buffer.from('SirfHum-Unpair-v1', 'ascii');

/** The 32 bytes the device key signs (purpose `unpair`). */
export function unpairAuthorizationChallenge(fields: {
  nonce: Buffer;
  accountId: string;
  deviceId: Buffer;
  coupleId: Buffer;
}): Buffer {
  const { nonce, deviceId, coupleId } = fields;
  if (nonce.length !== CHALLENGE_BYTES || deviceId.length !== 16 || coupleId.length !== 16) {
    throw new DeviceError('invalid_argument');
  }
  return createHash('sha256')
    .update(
      Buffer.concat([CONTEXT, Buffer.from([1]), nonce, lengthPrefixed(Buffer.from(fields.accountId, 'utf8')), deviceId, coupleId]),
    )
    .digest();
}

const coupleRef = (db: Firestore, id: string) => db.collection(CoupleCollections.couples).doc(id);
const partnerRef = (db: Firestore, account: string) => db.collection(ConversationCollections.accountPartners).doc(account);

/** The caller's couple, if active and theirs; one category otherwise (no probing). */
function coupleFailure(couple: FirebaseFirestore.DocumentSnapshot | null, accountId: string): DeviceFailure | null {
  const members = couple?.get('members') as unknown;
  if (couple?.exists !== true || !Array.isArray(members) || !members.includes(accountId) || couple.get('status') !== 'active') {
    return 'couple_unavailable';
  }
  return null;
}

/** Upper bound on the predecessor walk (recovery is rate limited, D-135). */
const MAX_LINEAGE_STEPS = 64;

/**
 * Every conversation of the couple, each read IN the transaction.
 *
 * A collection query inside the transaction would lock the whole
 * `conversations` range (and the emulator fails such contended transactions
 * with INVALID_ARGUMENT rather than ABORTED). So the IDs are listed outside
 * it, and completeness comes from point reads instead: a conversation
 * created after the listing can only be a recovery successor (D-135), which
 * always becomes the partners' current conversation; walking its
 * `predecessorId` chain back to a listed one covers every successor in
 * between. A recovery committing concurrently writes the partner records
 * this transaction read, so it forces a retry, which lists again.
 */
/** The couple's conversation IDs, read outside the transaction. */
export type ConversationLister = (db: Firestore, coupleId: string) => Promise<string[]>;

const listCoupleConversations: ConversationLister = async (db, coupleId) =>
  (await db.collection(ConversationCollections.conversations).where('coupleId', '==', coupleId).select().get()).docs.map(
    (d) => d.id,
  );

async function coupleConversations(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  coupleId: string,
  partners: FirebaseFirestore.DocumentSnapshot[],
  list: ConversationLister,
): Promise<FirebaseFirestore.DocumentSnapshot[]> {
  const conversations = db.collection(ConversationCollections.conversations);
  const ids = new Set(await list(db, coupleId));
  const found = new Map<string, FirebaseFirestore.DocumentSnapshot>();
  const pending = new Set<string>(ids);
  for (const p of partners) {
    const current = p.get('conversationId') as unknown;
    if (p.get('coupleId') === coupleId && typeof current === 'string') pending.add(current);
  }
  for (let steps = 0; pending.size > 0 && steps < MAX_LINEAGE_STEPS + ids.size; steps += 1) {
    const [id] = pending;
    pending.delete(id);
    if (found.has(id)) continue;
    const doc = await tx.get(conversations.doc(id));
    if (!doc.exists || doc.get('coupleId') !== coupleId) continue;
    found.set(id, doc);
    const predecessor = doc.get('predecessorId') as unknown;
    if (typeof predecessor === 'string' && !found.has(predecessor)) pending.add(predecessor);
  }
  // Fail closed: never dissolve with a conversation of the couple unread
  // (the transaction aborts and nothing is written).
  if (pending.size > 0) throw new Error('conversation lineage exceeds the walk bound');
  return [...found.values()];
}

export async function requestUnpairChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const coupleId = requirePattern(args.coupleId, RECORD_ID_PATTERN);
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'unpair', now);

  const [device, couple] = await Promise.all([deviceRef(db, accountId, deviceId).get(), coupleRef(db, coupleId).get()]);
  const failure = coupleFailure(couple, accountId);
  if (failure !== null) throw new DeviceError(failure);
  if (!device.exists) throw new DeviceError('device_not_found');
  if (device.get('status') !== 'active') throw new DeviceError('device_not_active');

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.challengeMs);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose: UNPAIR_PURPOSE,
    coupleId,
    challenge,
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  return { challengeId, challenge: challenge.toString('base64'), expiresAtMillis: expiresAtUnix * 1000, expiresAtUnix };
}

export async function unpairCouple(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
  list: ConversationLister = listCoupleConversations,
): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const coupleId = requirePattern(args.coupleId, RECORD_ID_PATTERN);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const proof = requireBytes(args.proof, PROOF_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const [challenge, device, couple] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, deviceId)),
      tx.get(coupleRef(db, coupleId)),
    ]);
    const members = couple.get('members') as unknown;
    const memberList = Array.isArray(members) ? members.filter((m): m is string => typeof m === 'string') : [];
    // Every read before the first write (Firestore transactions).
    const partners = memberList.length === 2 ? await Promise.all(memberList.map((m) => tx.get(partnerRef(db, m)))) : [];
    const conversations = couple.exists ? await coupleConversations(db, tx, coupleId, partners, list) : [];

    if (!challenge.exists) return 'challenge_invalid';
    tx.delete(challengeRef); // single-use whatever the outcome
    if (
      challenge.get('accountId') !== accountId ||
      challenge.get('deviceId') !== deviceId ||
      challenge.get('purpose') !== UNPAIR_PURPOSE ||
      challenge.get('coupleId') !== coupleId
    ) {
      return 'challenge_invalid';
    }
    const expiresAt = challenge.get('expiresAt') as unknown;
    if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'challenge_expired';
    const coupleState = coupleFailure(couple, accountId);
    if (coupleState !== null) return coupleState;
    if (!device.exists) return 'device_not_found';
    if (device.get('status') !== 'active') return 'device_not_active';
    try {
      const signed = unpairAuthorizationChallenge({
        nonce: Buffer.from(challenge.get('challenge') as Uint8Array),
        accountId,
        deviceId: Buffer.from(deviceId, 'hex'),
        coupleId: Buffer.from(coupleId, 'hex'),
      });
      const cert = verifyDeviceProof(ProofPurpose.unpair, accountId, Buffer.from(device.get('certificate') as Uint8Array), signed, proof);
      if (cert.deviceId.toString('hex') !== deviceId) return 'certificate_invalid';
    } catch (error) {
      if (error instanceof InvalidCertificateError) return 'certificate_invalid';
      if (error instanceof InvalidProofError) return 'proof_invalid';
      throw error;
    }

    tx.update(couple.ref, { status: 'dissolved', dissolvedAt: FieldValue.serverTimestamp(), dissolvedByDeviceId: deviceId });
    for (const c of conversations) {
      if (c.get('state') !== 'closed') tx.update(c.ref, { state: 'closed', closedAt: FieldValue.serverTimestamp() });
    }
    // Partner reads end at once; only records that still name this couple.
    for (const p of partners) if (p.exists && p.get('coupleId') === coupleId) tx.delete(p.ref);
    return null;
  });
  if (failure !== null) {
    if (failure === 'proof_invalid' || failure === 'certificate_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
}
