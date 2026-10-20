/**
 * Conversation recovery (Prompt 17C, D-135): retire a stalled conversation
 * and re-provision a new MLS group for the same couple.
 *
 * A trusted device can win `commits/{e}` with a commit the other devices
 * cannot process (D-127 stops only sessions without a device key). MLS has
 * no undo for an accepted epoch and the server never parses MLS, so the
 * sound way forward is a NEW conversation (= new MLS group ID) built by the
 * devices from verified lineage, exactly like a new couple's.
 *
 *   requestRecoveryChallenge  single-use nonce bound to (account, device,
 *                             conversation, epoch, account trust epoch)
 *   recoverConversation       verifies, in one transaction, the challenge,
 *                             the device (active NOW), the trust epoch
 *                             (unchanged), the conversation (active, current
 *                             for the couple, epoch unchanged), the couple
 *                             (active) and the device proof (purpose
 *                             `conversation_recovery` = 7) over:
 *
 *   SHA-256( "SirfHum-ConversationRecovery-v1" | u8 1 | nonce[32]
 *          | u32 len | account (UTF-8) | device id[16] | conversation id[16]
 *          | stalled epoch u64 BE | account trust epoch u64 BE )
 *
 * Then: old conversation `retired` (no more writes, still member-readable,
 * history untouched), new conversation (epoch 0, generation + 1,
 * predecessorId), both partner records pointed at it. No key, plaintext or
 * MLS state passes through here.
 */
import { createHash, randomBytes } from 'node:crypto';
import { FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
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
  trustRef,
  TTL,
} from '../device/common';
import { currentEpoch } from '../device/epoch';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from '../device/proof';
import { consume, requireBudget } from '../device/rateLimit';
import { type IssuedChallenge, recordFailure } from '../device/registration';
import {
  CIPHERSUITE,
  CONVERSATION_SCHEMA_VERSION,
  ConversationCollections,
  MESSAGE_PROTOCOL_VERSION,
  randomConversationId,
} from './provision';

export const RECOVERY_PURPOSE = 'conversation_recovery';
const CONTEXT = Buffer.from('SirfHum-ConversationRecovery-v1', 'ascii');

const u64 = (value: number): Buffer => {
  const out = Buffer.alloc(8);
  out.writeBigUInt64BE(BigInt(value), 0);
  return out;
};

/** The 32 bytes the device key signs (purpose `conversation_recovery`). */
export function recoveryAuthorizationChallenge(fields: {
  nonce: Buffer;
  accountId: string;
  deviceId: Buffer;
  conversationId: Buffer;
  epoch: number;
  trustEpoch: number;
}): Buffer {
  const { nonce, deviceId, conversationId, epoch, trustEpoch } = fields;
  if (nonce.length !== CHALLENGE_BYTES || deviceId.length !== 16 || conversationId.length !== 16) {
    throw new DeviceError('invalid_argument');
  }
  for (const v of [epoch, trustEpoch]) {
    if (!Number.isSafeInteger(v) || v < 0) throw new DeviceError('invalid_argument');
  }
  return createHash('sha256')
    .update(
      Buffer.concat([
        CONTEXT,
        Buffer.from([1]),
        nonce,
        lengthPrefixed(Buffer.from(fields.accountId, 'utf8')),
        deviceId,
        conversationId,
        u64(epoch),
        u64(trustEpoch),
      ]),
    )
    .digest();
}

function requireCount(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) throw new DeviceError('invalid_argument');
  return value;
}

const conversationRef = (db: Firestore, id: string) => db.collection(ConversationCollections.conversations).doc(id);
const partnerRef = (db: Firestore, account: string) => db.collection(ConversationCollections.accountPartners).doc(account);

export async function requestRecoveryChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const conversationId = requirePattern(args.conversationId, RECORD_ID_PATTERN);
  const epoch = requireCount(args.epoch);
  const trustEpoch = requireCount(args.trustEpoch);
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'conversationRecovery', now);

  const [device, conv, trust] = await Promise.all([
    deviceRef(db, accountId, deviceId).get(),
    conversationRef(db, conversationId).get(),
    trustRef(db, accountId).get(),
  ]);
  const members = conv.get('members') as unknown;
  if (!conv.exists || !Array.isArray(members) || !members.includes(accountId)) {
    throw new DeviceError('conversation_unavailable');
  }
  if (!device.exists) throw new DeviceError('device_not_found');
  if (device.get('status') !== 'active') throw new DeviceError('device_not_active');
  if (conv.get('state') !== 'active' || conv.get('epoch') !== epoch || currentEpoch(trust) !== trustEpoch) {
    throw new DeviceError('conversation_changed');
  }

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.challengeMs);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose: RECOVERY_PURPOSE,
    conversationId,
    epoch,
    trustEpoch,
    challenge,
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  return { challengeId, challenge: challenge.toString('base64'), expiresAtMillis: expiresAtUnix * 1000, expiresAtUnix };
}

export async function recoverConversation(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
  newConversationId: () => string = randomConversationId,
): Promise<{ conversationId: string }> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const conversationId = requirePattern(args.conversationId, RECORD_ID_PATTERN);
  const epoch = requireCount(args.epoch);
  const trustEpoch = requireCount(args.trustEpoch);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const proof = requireBytes(args.proof, PROOF_BYTES);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const successor = newConversationId();
  const result = await db.runTransaction(async (tx): Promise<DeviceFailure | { readonly successor: string }> => {
    const [challenge, device, conv, trust] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, deviceId)),
      tx.get(conversationRef(db, conversationId)),
      tx.get(trustRef(db, accountId)),
    ]);
    const members = conv.get('members') as unknown;
    const memberList = Array.isArray(members) ? members.filter((m): m is string => typeof m === 'string') : [];
    const coupleId = conv.get('coupleId') as unknown;
    // Every read before the first write (Firestore transactions).
    const partners = memberList.length === 2 ? await Promise.all(memberList.map((m) => tx.get(partnerRef(db, m)))) : [];
    const couple = typeof coupleId === 'string' ? await tx.get(db.collection('couples').doc(coupleId)) : null;
    const taken = await tx.get(conversationRef(db, successor));

    if (!challenge.exists) return 'challenge_invalid';
    tx.delete(challengeRef); // single-use whatever the outcome
    if (
      challenge.get('accountId') !== accountId ||
      challenge.get('deviceId') !== deviceId ||
      challenge.get('purpose') !== RECOVERY_PURPOSE ||
      challenge.get('conversationId') !== conversationId ||
      challenge.get('epoch') !== epoch ||
      challenge.get('trustEpoch') !== trustEpoch
    ) {
      return 'challenge_invalid';
    }
    const expiresAt = challenge.get('expiresAt') as unknown;
    if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'challenge_expired';
    if (!conv.exists || !memberList.includes(accountId)) return 'conversation_unavailable';
    if (!device.exists) return 'device_not_found';
    if (device.get('status') !== 'active') return 'device_not_active';
    try {
      const signed = recoveryAuthorizationChallenge({
        nonce: Buffer.from(challenge.get('challenge') as Uint8Array),
        accountId,
        deviceId: Buffer.from(deviceId, 'hex'),
        conversationId: Buffer.from(conversationId, 'hex'),
        epoch,
        trustEpoch,
      });
      const cert = verifyDeviceProof(ProofPurpose.conversationRecovery, accountId, Buffer.from(device.get('certificate') as Uint8Array), signed, proof);
      if (cert.deviceId.toString('hex') !== deviceId) return 'certificate_invalid';
    } catch (error) {
      if (error instanceof InvalidCertificateError) return 'certificate_invalid';
      if (error instanceof InvalidProofError) return 'proof_invalid';
      throw error;
    }
    // The state being recovered must be exactly the one that was signed,
    // and still the couple's current conversation (never an older one).
    const current =
      conv.get('state') === 'active' &&
      conv.get('epoch') === epoch &&
      currentEpoch(trust) === trustEpoch &&
      couple?.exists === true &&
      couple.get('status') === 'active' &&
      partners.length === 2 &&
      partners.every((p) => p.exists && p.get('conversationId') === conversationId);
    if (!current) return 'conversation_changed';
    if (taken.exists) throw new Error('conversation ID collision');

    const generation = Number(conv.get('generation') ?? 0) + 1;
    tx.create(conversationRef(db, successor), {
      schemaVersion: CONVERSATION_SCHEMA_VERSION,
      protocolVersion: MESSAGE_PROTOCOL_VERSION,
      ciphersuite: CIPHERSUITE,
      members: memberList,
      pairingId: conv.get('pairingId') as string,
      coupleId,
      state: 'active',
      epoch: 0,
      generation,
      predecessorId: conversationId,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(conversationRef(db, conversationId), {
      state: 'retired',
      successorId: successor,
      retiredAt: FieldValue.serverTimestamp(),
      retiredByDeviceId: deviceId,
    });
    for (const p of partners) tx.update(p.ref, { conversationId: successor });
    return { successor };
  });
  if (typeof result === 'object') return { conversationId: result.successor };
  const failure = result;
  if (failure === 'proof_invalid' || failure === 'certificate_invalid') await recordFailure(db, accountId, now);
  throw new DeviceError(failure);
}
