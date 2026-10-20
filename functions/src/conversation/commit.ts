/**
 * Device-bound MLS commit submission (Prompt 17B, D-127; finding P17-05).
 *
 * Before D-127 clients wrote `commits/{epoch}`, the epoch move and the
 * Welcomes themselves, and the rules could only check the ACCOUNT. Any
 * Firebase session of either member (a password alone) could therefore win
 * an epoch with bytes no device can process and stall the conversation.
 * Now the rules deny those writes and only this module performs them, after
 * verifying a proof by the device key of an `active` device of the caller.
 *
 *   requestCommitChallenge   single-use 32-byte nonce bound to (account,
 *                            device, conversation, fromEpoch), 5 minutes
 *   submitMlsCommit          verifies, in one transaction (callable name;
 *                            module function submitConversationCommit): the challenge,
 *                            the device (active NOW, member account), the
 *                            conversation (active, epoch == fromEpoch, no
 *                            commit yet: first commit wins, D-088), and the
 *                            device proof (purpose `commit` = 5, D-070
 *                            format) over the derived challenge below; then
 *                            writes the commit, the epoch move and Welcomes
 *
 * Derived challenge (what the device key signs; mirrored by
 * lib/security/messaging/commit_authorization.dart, golden vector
 * test/vectors/commit_authorization_v1.json):
 *
 *   SHA-256( "SirfHum-CommitAuthorization-v1" | u8 1 | nonce[32]
 *          | u32 len | account (UTF-8) | device id[16] | conversation id[16]
 *          | fromEpoch u64 BE | toEpoch u64 BE | protocol u16 BE
 *          | SHA-256(commit)[32]
 *          | SHA-256( u32 n | n × (target device id[16] | SHA-256(welcome)[32]) ) )
 *
 * So the signature binds account, device, conversation, both epochs,
 * protocol version, purpose (inside the proof) and the exact commit and
 * Welcome bytes, and it is usable once. The server never parses or
 * decrypts MLS: it hashes opaque bytes. Every device still validates the
 * winning commit itself (D-088).
 */
import { createHash, randomBytes } from 'node:crypto';
import { FieldValue, type Firestore, Timestamp } from 'firebase-admin/firestore';
import { InvalidCertificateError } from '../device/certificate';
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
  requireBytesUpTo,
  requirePattern,
  toUnixSeconds,
  TTL,
} from '../device/common';
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from '../device/proof';
import { consume, requireBudget } from '../device/rateLimit';
import { type IssuedChallenge, recordFailure } from '../device/registration';
import { lengthPrefixed } from '../device/certificate';
import { ConversationCollections, MESSAGE_PROTOCOL_VERSION } from './provision';

export const COMMIT_PURPOSE = 'commit';
const CONTEXT = Buffer.from('SirfHum-CommitAuthorization-v1', 'ascii');
const FORMAT_VERSION = 1;
/** Same bounds as the former rules (D-088): MLS handshake bytes, opaque. */
export const MAX_COMMIT_BYTES = 131072;
export const MAX_WELCOME_BYTES = 131072;
/** A couple has at most 16 member devices (Rust MAX_GROUP_MEMBERS). */
export const MAX_WELCOMES = 15;

const sha256 = (bytes: Buffer): Buffer => createHash('sha256').update(bytes).digest();

const u64 = (value: number): Buffer => {
  const out = Buffer.alloc(8);
  out.writeBigUInt64BE(BigInt(value), 0);
  return out;
};

export interface WelcomeInput {
  readonly targetDeviceId: Buffer;
  readonly welcome: Buffer;
}

/** The 32 bytes the device key signs (purpose `commit`). */
export function commitAuthorizationChallenge(fields: {
  nonce: Buffer;
  accountId: string;
  deviceId: Buffer;
  conversationId: Buffer;
  fromEpoch: number;
  protocolVersion: number;
  commit: Buffer;
  welcomes: readonly WelcomeInput[];
}): Buffer {
  const { nonce, deviceId, conversationId, fromEpoch } = fields;
  if (nonce.length !== CHALLENGE_BYTES || deviceId.length !== 16 || conversationId.length !== 16) {
    throw new DeviceError('invalid_argument');
  }
  if (!Number.isSafeInteger(fromEpoch) || fromEpoch < 0) throw new DeviceError('invalid_argument');
  const count = Buffer.alloc(4);
  count.writeUInt32BE(fields.welcomes.length, 0);
  const welcomes = sha256(
    Buffer.concat([count, ...fields.welcomes.flatMap((w) => [w.targetDeviceId, sha256(w.welcome)])]),
  );
  const protocol = Buffer.alloc(2);
  protocol.writeUInt16BE(fields.protocolVersion, 0);
  return sha256(
    Buffer.concat([
      CONTEXT,
      Buffer.from([FORMAT_VERSION]),
      nonce,
      lengthPrefixed(Buffer.from(fields.accountId, 'utf8')),
      deviceId,
      conversationId,
      u64(fromEpoch),
      u64(fromEpoch + 1),
      protocol,
      sha256(fields.commit),
      welcomes,
    ]),
  );
}

const conversationRef = (db: Firestore, id: string) =>
  db.collection(ConversationCollections.conversations).doc(id);

function requireEpoch(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) throw new DeviceError('invalid_argument');
  return value;
}

/** Membership and state of the conversation, uniform for unknown ones. */
function conversationFailure(conv: FirebaseFirestore.DocumentSnapshot, accountId: string): DeviceFailure | null {
  const members = conv.get('members') as unknown;
  if (!conv.exists || !Array.isArray(members) || !members.includes(accountId) || conv.get('state') !== 'active') {
    return 'conversation_unavailable';
  }
  return null;
}

export async function requestCommitChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const conversationId = requirePattern(args.conversationId, RECORD_ID_PATTERN);
  const fromEpoch = requireEpoch(args.fromEpoch);
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'commit', now);

  const [device, conv] = await Promise.all([deviceRef(db, accountId, deviceId).get(), conversationRef(db, conversationId).get()]);
  const convFailure = conversationFailure(conv, accountId);
  if (convFailure !== null) throw new DeviceError(convFailure);
  if (!device.exists) throw new DeviceError('device_not_found');
  if (device.get('status') !== 'active') throw new DeviceError('device_not_active');
  // A challenge for an epoch that has moved could never succeed.
  if (conv.get('epoch') !== fromEpoch) throw new DeviceError('commit_conflict');

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.challengeMs);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose: COMMIT_PURPOSE,
    conversationId,
    fromEpoch,
    challenge,
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  return { challengeId, challenge: challenge.toString('base64'), expiresAtMillis: expiresAtUnix * 1000, expiresAtUnix };
}

function welcomesOf(value: unknown): WelcomeInput[] {
  if (!Array.isArray(value) || value.length > MAX_WELCOMES) throw new DeviceError('invalid_argument');
  const seen = new Set<string>();
  return value.map((w: unknown) => {
    const item = input(w);
    const target = requirePattern(item.targetDeviceId, DEVICE_ID_PATTERN);
    if (seen.has(target)) throw new DeviceError('invalid_argument');
    seen.add(target);
    return { targetDeviceId: Buffer.from(target, 'hex'), welcome: requireBytesUpTo(item.welcome, MAX_WELCOME_BYTES) };
  });
}

export async function submitConversationCommit(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<{ epoch: number }> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const conversationId = requirePattern(args.conversationId, RECORD_ID_PATTERN);
  const fromEpoch = requireEpoch(args.fromEpoch);
  const challengeId = requirePattern(args.challengeId, RECORD_ID_PATTERN);
  const proof = requireBytes(args.proof, PROOF_BYTES);
  const commit = requireBytesUpTo(args.commit, MAX_COMMIT_BYTES);
  const welcomes = welcomesOf(args.welcomes);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(challengeId);
  const convRef = conversationRef(db, conversationId);
  const commitRef = convRef.collection('commits').doc(String(fromEpoch));
  const failure = await db.runTransaction(async (tx): Promise<DeviceFailure | null> => {
    const [challenge, device, conv, existing] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, deviceId)),
      tx.get(convRef),
      tx.get(commitRef),
    ]);
    if (!challenge.exists) return 'challenge_invalid';
    tx.delete(challengeRef); // single-use whatever the outcome
    if (
      challenge.get('accountId') !== accountId ||
      challenge.get('deviceId') !== deviceId ||
      challenge.get('purpose') !== COMMIT_PURPOSE ||
      challenge.get('conversationId') !== conversationId ||
      challenge.get('fromEpoch') !== fromEpoch
    ) {
      return 'challenge_invalid';
    }
    const expiresAt = challenge.get('expiresAt') as unknown;
    if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return 'challenge_expired';
    const convFailure = conversationFailure(conv, accountId);
    if (convFailure !== null) return convFailure;
    if (!device.exists) return 'device_not_found';
    if (device.get('status') !== 'active') return 'device_not_active';
    try {
      const signed = commitAuthorizationChallenge({
        nonce: Buffer.from(challenge.get('challenge') as Uint8Array),
        accountId,
        deviceId: Buffer.from(deviceId, 'hex'),
        conversationId: Buffer.from(conversationId, 'hex'),
        fromEpoch,
        protocolVersion: MESSAGE_PROTOCOL_VERSION,
        commit,
        welcomes,
      });
      const cert = verifyDeviceProof(ProofPurpose.commit, accountId, Buffer.from(device.get('certificate') as Uint8Array), signed, proof);
      if (cert.deviceId.toString('hex') !== deviceId) return 'certificate_invalid';
    } catch (error) {
      if (error instanceof InvalidCertificateError) return 'certificate_invalid';
      if (error instanceof InvalidProofError) return 'proof_invalid';
      throw error;
    }
    // First commit wins (D-088): the epoch must not have moved and no
    // commit may exist for it. Checked after the proof so a loser with a
    // valid proof learns `commit_conflict`, never a verification failure.
    if (conv.get('epoch') !== fromEpoch || existing.exists) return 'commit_conflict';
    tx.create(commitRef, {
      schemaVersion: 1,
      epoch: fromEpoch,
      senderAccountId: accountId,
      senderDeviceId: deviceId,
      commit,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(convRef, { epoch: fromEpoch + 1 });
    for (const w of welcomes) {
      const target = w.targetDeviceId.toString('hex');
      tx.create(convRef.collection('welcomes').doc(`${target}_${fromEpoch}`), {
        schemaVersion: 1,
        epoch: fromEpoch,
        targetDeviceId: target,
        senderAccountId: accountId,
        senderDeviceId: deviceId,
        welcome: w.welcome,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return null;
  });
  if (failure !== null) {
    if (failure === 'proof_invalid' || failure === 'certificate_invalid') await recordFailure(db, accountId, now);
    throw new DeviceError(failure);
  }
  return { epoch: fromEpoch + 1 };
}
