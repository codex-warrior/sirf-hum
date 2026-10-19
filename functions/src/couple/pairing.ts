/**
 * Pairing two accounts into a couple (Prompt 12, D-100–D-105).
 * docs/security/COUPLE-AND-PAIRING.md.
 *
 *   requestPairingChallenge   an ACTIVE device asks to perform one step; the
 *                             single-use challenge is bound to the step and
 *                             its subject (nothing, the token, or the pairing)
 *   createPairingInvitation   inviter → `pending`; returns a 128-bit token
 *                             once (only its hash is stored)
 *   acceptPairingInvitation   invitee redeems the token → `claimed`, bound to
 *                             the invitee's account and device
 *   confirmPairing            inviter confirms that account → `accepted`; the
 *                             couple, its conversation and both partner
 *                             records are created in the same transaction
 *   rejectPairing             inviter refuses the claimant → `rejected`
 *   cancelPairing             a participant withdraws → `cancelled`
 *   getPairingState           the caller's own state (no secrets)
 *
 * Every step is signed by the device key of an active device (proof purpose
 * `pairing` = 4, D-070 format), so a Firebase session or password alone can
 * neither pair nor un-pair anyone (D-102). The authenticated account comes
 * only from the verified auth context; clients never supply account IDs,
 * couple IDs, statuses or timestamps. Both consents are explicit: the
 * invitee's (accept) and the inviter's, for that specific account (confirm),
 * so an intercepted link cannot pair a stranger silently.
 *
 * Fail closed: a pending identity reset, a changed identity epoch (D-082), a
 * bound device that is no longer active, or a participant paired elsewhere
 * invalidates the pairing. All race-sensitive transitions are single
 * Firestore transactions over the pairing, both accounts' locks, partner
 * records, trust records and devices. Pure logic over an injected Firestore
 * and clock (emulator-tested); callable wrappers live in ../index.ts. Errors
 * carry categories only; tokens, codes and IDs are never logged.
 */
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { type DocumentSnapshot, FieldValue, type Firestore, Timestamp, type Transaction } from 'firebase-admin/firestore';
import { ConversationCollections, randomConversationId, writeCoupleConversation } from '../conversation/provision';
import { InvalidCertificateError } from '../device/certificate';
import {
  ACCOUNT_ID_PATTERN,
  Collections,
  DEVICE_ID_PATTERN,
  DeviceError,
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
import { CHALLENGE_BYTES, InvalidProofError, PROOF_BYTES, ProofPurpose, verifyDeviceProof } from '../device/proof';
import { consume, requireBudget } from '../device/rateLimit';
import { type IssuedChallenge, recordFailure } from '../device/registration';
import {
  assertTransition,
  COUPLE_SCHEMA_VERSION,
  CoupleCollections,
  PAIRING_ACTIONS,
  PAIRING_SCHEMA_VERSION,
  type PairingAction,
  PairingError,
  type PairingStatus,
  PairingTTL,
} from './state';

export const PAIRING_CHALLENGE_PURPOSE = 'pairing';
const TOKEN_BYTES = 16;
/** 16 random bytes, base64url without padding. */
export const TOKEN_PATTERN = /^[A-Za-z0-9_-]{22}$/;

/** What the server stores and looks up: never the token itself. */
export function invitationTokenHash(token: string): string {
  return createHash('sha256').update(`SirfHum-PairingToken-v1|${token}`).digest('hex');
}

/** What a step challenge is bound to (server-side, like the push token hash). */
export function stepBinding(action: PairingAction, subject: string): string {
  return createHash('sha256').update(`SirfHum-PairingStep-v1|${action}|${subject}`).digest('hex');
}

const pairingRef = (db: Firestore, id: string) => db.collection(CoupleCollections.pairings).doc(id);
const lockRef = (db: Firestore, accountId: string) => db.collection(CoupleCollections.pairingLocks).doc(accountId);
const partnerRef = (db: Firestore, accountId: string) =>
  db.collection(ConversationCollections.accountPartners).doc(accountId);
const profileRef = (db: Firestore, accountId: string) => db.collection(CoupleCollections.users).doc(accountId);

type Failure = DeviceError | PairingError;

interface SignedStep {
  readonly deviceId: string;
  readonly challengeId: string;
  readonly proof: Buffer;
}

function signedStep(args: Record<string, unknown>): SignedStep {
  return {
    deviceId: requirePattern(args.deviceId, DEVICE_ID_PATTERN),
    challengeId: requirePattern(args.challengeId, RECORD_ID_PATTERN),
    proof: requireBytes(args.proof, PROOF_BYTES),
  };
}

function subjectOf(action: PairingAction, args: Record<string, unknown>): string {
  switch (action) {
    case 'create':
      return '';
    case 'accept':
      return invitationTokenHash(requirePattern(args.token, TOKEN_PATTERN));
    case 'confirm':
    case 'reject':
    case 'cancel':
      return requirePattern(args.pairingId, RECORD_ID_PATTERN);
  }
}

const isActive = (device: DocumentSnapshot | null): boolean => device?.exists === true && device.get('status') === 'active';

const resetPending = (trust: DocumentSnapshot): boolean =>
  (trust.get('reset') as { status?: unknown } | undefined)?.status === 'pending';

/** D-082: bumped by every completed identity reset. Absent means 0. */
function identityEpoch(trust: DocumentSnapshot): number {
  const value = trust.exists ? (trust.get('identityEpoch') as unknown) : 0;
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

const validAccount = (value: unknown): string | null =>
  typeof value === 'string' && ACCOUNT_ID_PATTERN.test(value) ? value : null;

const validDevice = (value: unknown): string | null =>
  typeof value === 'string' && DEVICE_ID_PATTERN.test(value) ? value : null;

function displayName(profile: DocumentSnapshot | null): string | null {
  const value = profile?.exists === true ? (profile.get('displayName') as unknown) : undefined;
  return typeof value === 'string' ? value : null;
}

/**
 * `live` while open and before its deadline (server clock only); `expired`
 * when open but past it; `ended` in any terminal state.
 */
export function liveness(pairing: DocumentSnapshot, now: Date): 'live' | 'expired' | 'ended' {
  const status = pairing.get('status') as unknown;
  if (status !== 'pending' && status !== 'claimed') return 'ended';
  const deadline = pairing.get(status === 'pending' ? 'expiresAt' : 'confirmExpiresAt') as unknown;
  return deadline instanceof Timestamp && deadline.toMillis() > now.getTime() ? 'live' : 'expired';
}

/** Moves an open pairing to a terminal state; the secrets go with it. */
function end(tx: Transaction, pairing: DocumentSnapshot, to: PairingStatus, reason: string, fields: Record<string, unknown> = {}) {
  assertTransition(pairing.get('status'), to);
  tx.update(pairing.ref, {
    ...fields,
    status: to,
    endReason: reason,
    endedAt: FieldValue.serverTimestamp(),
    tokenHash: FieldValue.delete(),
    confirmationCode: FieldValue.delete(),
  });
}

/** Deletes an account's lock only if it still points at this pairing. */
function release(tx: Transaction, lock: DocumentSnapshot | null, pairingId: string) {
  if (lock?.exists === true && lock.get('pairingId') === pairingId) tx.delete(lock.ref);
}

/** The pairing an account's lock points at, if any (locks are hints, checked against it). */
async function lockedPairing(tx: Transaction, db: Firestore, lock: DocumentSnapshot): Promise<DocumentSnapshot | null> {
  const id = lock.exists ? (lock.get('pairingId') as unknown) : undefined;
  if (typeof id !== 'string' || !RECORD_ID_PATTERN.test(id)) return null;
  const snap = await tx.get(pairingRef(db, id));
  return snap.exists ? snap : null;
}

/** Challenge, device and signature for one step, all against stored state. */
function stepFailure(
  challenge: DocumentSnapshot,
  device: DocumentSnapshot,
  accountId: string,
  step: SignedStep,
  action: PairingAction,
  binding: string,
  now: Date,
): DeviceError | null {
  if (
    challenge.get('accountId') !== accountId ||
    challenge.get('deviceId') !== step.deviceId ||
    challenge.get('purpose') !== PAIRING_CHALLENGE_PURPOSE ||
    challenge.get('action') !== action ||
    challenge.get('binding') !== binding
  ) {
    return new DeviceError('challenge_invalid');
  }
  const expiresAt = challenge.get('expiresAt') as unknown;
  if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= now.getTime()) return new DeviceError('challenge_expired');
  if (!device.exists) return new DeviceError('device_not_found');
  if (device.get('status') !== 'active') return new DeviceError('device_not_active');
  try {
    const cert = verifyDeviceProof(
      ProofPurpose.pairing,
      accountId,
      Buffer.from(device.get('certificate') as Uint8Array),
      Buffer.from(challenge.get('challenge') as Uint8Array),
      step.proof,
    );
    if (cert.deviceId.toString('hex') !== step.deviceId) return new DeviceError('certificate_invalid');
  } catch (error) {
    if (error instanceof InvalidCertificateError) return new DeviceError('certificate_invalid');
    if (error instanceof InvalidProofError) return new DeviceError('proof_invalid');
    throw error;
  }
  return null;
}

async function raise(db: Firestore, accountId: string, failure: Failure, now: Date): Promise<never> {
  if (failure instanceof DeviceError && (failure.failure === 'proof_invalid' || failure.failure === 'certificate_invalid')) {
    await recordFailure(db, accountId, now);
  }
  if (failure instanceof PairingError && failure.failure === 'invitation_invalid') {
    try {
      await consume(db, accountId, 'pairingRedeemFailure', now);
    } catch (error) {
      if (!(error instanceof DeviceError)) throw error;
    }
  }
  throw failure;
}

// ------------------------------------------------------------------ steps

export async function requestPairingChallenge(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<IssuedChallenge> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const deviceId = requirePattern(args.deviceId, DEVICE_ID_PATTERN);
  const action = args.action;
  if (typeof action !== 'string' || !(PAIRING_ACTIONS as readonly string[]).includes(action)) {
    throw new DeviceError('invalid_argument');
  }
  const binding = stepBinding(action as PairingAction, subjectOf(action as PairingAction, args));
  await requireBudget(db, accountId, 'verificationFailure', now);
  if (action === 'accept') await requireBudget(db, accountId, 'pairingRedeemFailure', now);
  await consume(db, accountId, 'pairing', now);

  const device = await deviceRef(db, accountId, deviceId).get();
  if (!device.exists) throw new DeviceError('device_not_found');
  if (device.get('status') !== 'active') throw new DeviceError('device_not_active');

  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(CHALLENGE_BYTES);
  const expiresAtUnix = toUnixSeconds(now.getTime() + TTL.challengeMs);
  await db.collection(Collections.challenges).doc(challengeId).create({
    accountId,
    deviceId,
    purpose: PAIRING_CHALLENGE_PURPOSE,
    action,
    binding,
    challenge,
    expiresAt: Timestamp.fromMillis(expiresAtUnix * 1000),
  });
  return { challengeId, challenge: challenge.toString('base64'), expiresAtMillis: expiresAtUnix * 1000, expiresAtUnix };
}

export interface CreatedInvitation {
  readonly pairingId: string;
  /** Shown to the inviter once (link / QR); the server keeps only its hash. */
  readonly token: string;
  readonly expiresAtMillis: number;
}

export async function createPairingInvitation(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<CreatedInvitation> {
  const accountId = requireAccount(uid);
  const step = signedStep(input(data));
  await requireBudget(db, accountId, 'verificationFailure', now);
  await consume(db, accountId, 'pairingInvitation', now);

  const token = randomBytes(TOKEN_BYTES).toString('base64url');
  const pairingId = randomBytes(16).toString('hex');
  const expiresAt = Timestamp.fromMillis(now.getTime() + PairingTTL.invitationMs);
  const challengeRef = db.collection(Collections.challenges).doc(step.challengeId);
  const failure = await db.runTransaction(async (tx): Promise<Failure | null> => {
    const [challenge, device, lock, partner, trust] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, step.deviceId)),
      tx.get(lockRef(db, accountId)),
      tx.get(partnerRef(db, accountId)),
      tx.get(trustRef(db, accountId)),
    ]);
    const open = await lockedPairing(tx, db, lock);
    if (!challenge.exists) return new DeviceError('challenge_invalid');
    tx.delete(challengeRef); // single-use whatever the outcome
    const stepFail = stepFailure(challenge, device, accountId, step, 'create', stepBinding('create', ''), now);
    if (stepFail !== null) return stepFail;
    if (partner.exists) return new PairingError('already_paired');
    if (resetPending(trust)) return new PairingError('identity_reset_pending');
    if (open !== null) {
      const state = liveness(open, now);
      // One open pairing per account: cancel it first (explicit, no silent replace).
      if (state === 'live') return new PairingError('pairing_in_progress');
      if (state === 'expired') end(tx, open, 'expired', 'expired');
    }
    tx.create(pairingRef(db, pairingId), {
      schemaVersion: PAIRING_SCHEMA_VERSION,
      status: 'pending',
      inviterAccountId: accountId,
      inviterDeviceId: step.deviceId,
      inviterIdentityEpoch: identityEpoch(trust),
      tokenHash: invitationTokenHash(token),
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
    });
    tx.set(lock.ref, { pairingId, role: 'inviter' });
    return null;
  });
  if (failure !== null) await raise(db, accountId, failure, now);
  return { pairingId, token, expiresAtMillis: expiresAt.toMillis() };
}

export interface AcceptedInvitation {
  readonly pairingId: string;
  /** Six digits both people compare before the inviter confirms. */
  readonly confirmationCode: string;
  readonly partnerDisplayName: string | null;
  readonly confirmExpiresAtMillis: number;
}

export async function acceptPairingInvitation(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
): Promise<AcceptedInvitation> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const step = signedStep(args);
  const hash = invitationTokenHash(requirePattern(args.token, TOKEN_PATTERN));
  await requireBudget(db, accountId, 'verificationFailure', now);
  await requireBudget(db, accountId, 'pairingRedeemFailure', now);

  const confirmationCode = String(randomInt(0, 1_000_000)).padStart(6, '0');
  const confirmExpiresAt = Timestamp.fromMillis(now.getTime() + PairingTTL.confirmationMs);
  const challengeRef = db.collection(Collections.challenges).doc(step.challengeId);
  const result = await db.runTransaction(async (tx): Promise<Failure | AcceptedInvitation> => {
    const [challenge, device, lock, partner, trust, found] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, step.deviceId)),
      tx.get(lockRef(db, accountId)),
      tx.get(partnerRef(db, accountId)),
      tx.get(trustRef(db, accountId)),
      tx.get(db.collection(CoupleCollections.pairings).where('tokenHash', '==', hash).limit(1)),
    ]);
    const invitation = found.empty ? null : found.docs[0];
    const inviter = validAccount(invitation?.get('inviterAccountId'));
    const inviterDeviceId = validDevice(invitation?.get('inviterDeviceId'));
    const own = await lockedPairing(tx, db, lock);
    const inviterSide =
      inviter === null || inviterDeviceId === null
        ? null
        : await Promise.all([
            tx.get(partnerRef(db, inviter)),
            tx.get(trustRef(db, inviter)),
            tx.get(deviceRef(db, inviter, inviterDeviceId)),
            tx.get(profileRef(db, inviter)),
          ]);

    if (!challenge.exists) return new DeviceError('challenge_invalid');
    tx.delete(challengeRef);
    const stepFail = stepFailure(challenge, device, accountId, step, 'accept', stepBinding('accept', hash), now);
    if (stepFail !== null) return stepFail;
    if (partner.exists) return new PairingError('already_paired');
    if (resetPending(trust)) return new PairingError('identity_reset_pending');

    // From here on every token problem is the same `invitation_invalid`:
    // unknown, used, expired, cancelled, own, or an inviter that cannot pair.
    if (invitation === null || inviter === null || inviterSide === null) return new PairingError('invitation_invalid');
    const state = liveness(invitation, now);
    if (state === 'expired') {
      end(tx, invitation, 'expired', 'expired');
      return new PairingError('invitation_invalid');
    }
    if (state !== 'live' || invitation.get('status') !== 'pending' || inviter === accountId) {
      return new PairingError('invitation_invalid');
    }
    const [inviterPartner, inviterTrust, inviterDevice, inviterProfile] = inviterSide;
    const inviterChange = inviterPartner.exists
      ? 'inviter_paired'
      : resetPending(inviterTrust) || identityEpoch(inviterTrust) !== invitation.get('inviterIdentityEpoch')
        ? 'inviter_identity_changed'
        : !isActive(inviterDevice)
          ? 'inviter_device_inactive'
          : null;
    if (inviterChange !== null) {
      end(tx, invitation, 'invalidated', inviterChange);
      return new PairingError('invitation_invalid');
    }

    if (own !== null) {
      const ownState = liveness(own, now);
      if (ownState === 'live') {
        // The invitee's own unredeemed invitation gives way; anything that
        // already involves another person does not.
        if (own.get('status') !== 'pending' || own.get('inviterAccountId') !== accountId) {
          return new PairingError('pairing_in_progress');
        }
        end(tx, own, 'cancelled', 'superseded');
      } else if (ownState === 'expired') {
        end(tx, own, 'expired', 'expired');
      }
    }

    assertTransition(invitation.get('status'), 'claimed');
    tx.update(invitation.ref, {
      status: 'claimed',
      inviteeAccountId: accountId,
      inviteeDeviceId: step.deviceId,
      inviteeIdentityEpoch: identityEpoch(trust),
      claimedAt: FieldValue.serverTimestamp(),
      confirmExpiresAt,
      confirmationCode,
      tokenHash: FieldValue.delete(), // single use: the token never matches again
    });
    tx.set(lock.ref, { pairingId: invitation.id, role: 'invitee' });
    return {
      pairingId: invitation.id,
      confirmationCode,
      partnerDisplayName: displayName(inviterProfile),
      confirmExpiresAtMillis: confirmExpiresAt.toMillis(),
    };
  });
  if (result instanceof Error) return raise(db, accountId, result, now);
  return result;
}

export interface ConfirmedPairing {
  readonly coupleId: string;
  readonly conversationId: string;
}

export async function confirmPairing(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
  newConversationId: () => string = randomConversationId,
): Promise<ConfirmedPairing> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const step = signedStep(args);
  const pairingId = requirePattern(args.pairingId, RECORD_ID_PATTERN);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const coupleId = randomBytes(16).toString('hex');
  const challengeRef = db.collection(Collections.challenges).doc(step.challengeId);
  const result = await db.runTransaction(async (tx): Promise<Failure | ConfirmedPairing> => {
    const [challenge, device, pairing] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, step.deviceId)),
      tx.get(pairingRef(db, pairingId)),
    ]);
    const isInviter = pairing.exists && pairing.get('inviterAccountId') === accountId;
    const invitee = isInviter ? validAccount(pairing.get('inviteeAccountId')) : null;
    const creatorId = validDevice(pairing.get('inviterDeviceId'));
    const inviteeDeviceId = validDevice(pairing.get('inviteeDeviceId'));
    const inviterLock = isInviter ? await tx.get(lockRef(db, accountId)) : null;
    const sides =
      invitee === null || creatorId === null || inviteeDeviceId === null
        ? null
        : await Promise.all([
            tx.get(lockRef(db, invitee)),
            tx.get(partnerRef(db, accountId)),
            tx.get(partnerRef(db, invitee)),
            tx.get(trustRef(db, accountId)),
            tx.get(trustRef(db, invitee)),
            tx.get(deviceRef(db, accountId, creatorId)),
            tx.get(deviceRef(db, invitee, inviteeDeviceId)),
          ]);

    if (!challenge.exists) return new DeviceError('challenge_invalid');
    tx.delete(challengeRef);
    const stepFail = stepFailure(challenge, device, accountId, step, 'confirm', stepBinding('confirm', pairingId), now);
    if (stepFail !== null) return stepFail;
    if (!isInviter) return new PairingError('pairing_not_found');
    if (pairing.get('status') === 'accepted') {
      // A retry after a lost acknowledgement: same couple, nothing new.
      const existingCouple = pairing.get('coupleId') as unknown;
      const existingConversation = pairing.get('conversationId') as unknown;
      if (typeof existingCouple === 'string' && typeof existingConversation === 'string') {
        return { coupleId: existingCouple, conversationId: existingConversation };
      }
      return new PairingError('pairing_not_open');
    }
    const inviteeLock = sides?.[0] ?? null;
    const state = liveness(pairing, now);
    if (state === 'expired') {
      end(tx, pairing, 'expired', 'expired');
      release(tx, inviterLock, pairingId);
      release(tx, inviteeLock, pairingId);
      return new PairingError('pairing_expired');
    }
    if (state !== 'live' || pairing.get('status') !== 'claimed' || sides === null || invitee === null) {
      return new PairingError('pairing_not_open');
    }
    const [, inviterPartner, inviteePartner, inviterTrust, inviteeTrust, creatorDevice, inviteeDevice] = sides;
    const invalidate = (reason: string, failure: PairingError): PairingError => {
      end(tx, pairing, 'invalidated', reason);
      release(tx, inviterLock, pairingId);
      release(tx, inviteeLock, pairingId);
      return failure;
    };
    if (inviterPartner.exists || inviteePartner.exists) return invalidate('already_paired', new PairingError('already_paired'));
    const trustChange =
      resetPending(inviterTrust) || identityEpoch(inviterTrust) !== pairing.get('inviterIdentityEpoch')
        ? 'inviter_identity_changed'
        : resetPending(inviteeTrust) || identityEpoch(inviteeTrust) !== pairing.get('inviteeIdentityEpoch')
          ? 'invitee_identity_changed'
          : !isActive(creatorDevice)
            ? 'inviter_device_inactive'
            : !isActive(inviteeDevice)
              ? 'invitee_device_inactive'
              : inviterLock?.get('pairingId') !== pairingId || inviteeLock?.get('pairingId') !== pairingId
                ? 'lock_mismatch'
                : null;
    if (trustChange !== null) return invalidate(trustChange, new PairingError('pairing_invalidated'));

    const members = [accountId, invitee].sort() as [string, string];
    const conversationId = writeCoupleConversation(tx, db, { pairingId, members, coupleId }, newConversationId);
    tx.create(db.collection(CoupleCollections.couples).doc(coupleId), {
      schemaVersion: COUPLE_SCHEMA_VERSION,
      members,
      status: 'active',
      pairingId,
      createdAt: FieldValue.serverTimestamp(),
    });
    assertTransition(pairing.get('status'), 'accepted');
    tx.update(pairing.ref, {
      status: 'accepted',
      // `accounts` is the Prompt 10 provisioning contract (D-086).
      accounts: [accountId, invitee],
      acceptedAt: FieldValue.serverTimestamp(),
      confirmedByDeviceId: step.deviceId,
      coupleId,
      conversationId,
      confirmationCode: FieldValue.delete(),
    });
    release(tx, inviterLock, pairingId);
    release(tx, inviteeLock, pairingId);
    return { coupleId, conversationId };
  });
  if (result instanceof Error) return raise(db, accountId, result, now);
  return result;
}

/** `reject` (inviter, claimed) or `cancel` (inviter: open; invitee: claimed). */
async function endByParticipant(
  db: Firestore,
  uid: string | undefined,
  data: unknown,
  now: Date,
  action: 'reject' | 'cancel',
): Promise<void> {
  const accountId = requireAccount(uid);
  const args = input(data);
  const step = signedStep(args);
  const pairingId = requirePattern(args.pairingId, RECORD_ID_PATTERN);
  await requireBudget(db, accountId, 'verificationFailure', now);

  const challengeRef = db.collection(Collections.challenges).doc(step.challengeId);
  const failure = await db.runTransaction(async (tx): Promise<Failure | null> => {
    const [challenge, device, pairing] = await Promise.all([
      tx.get(challengeRef),
      tx.get(deviceRef(db, accountId, step.deviceId)),
      tx.get(pairingRef(db, pairingId)),
    ]);
    const inviter = pairing.exists ? validAccount(pairing.get('inviterAccountId')) : null;
    const invitee = pairing.exists ? validAccount(pairing.get('inviteeAccountId')) : null;
    const role = inviter === accountId ? 'inviter' : invitee === accountId ? 'invitee' : null;
    const [inviterLock, inviteeLock] =
      role === null || inviter === null
        ? [null, null]
        : await Promise.all([tx.get(lockRef(db, inviter)), invitee === null ? null : tx.get(lockRef(db, invitee))]);

    if (!challenge.exists) return new DeviceError('challenge_invalid');
    tx.delete(challengeRef);
    const stepFail = stepFailure(challenge, device, accountId, step, action, stepBinding(action, pairingId), now);
    if (stepFail !== null) return stepFail;
    if (role === null) return new PairingError('pairing_not_found');

    const target: PairingStatus = action === 'reject' ? 'rejected' : 'cancelled';
    const reason = action === 'reject' ? 'rejected_by_inviter' : `cancelled_by_${role}`;
    if (pairing.get('status') === target && pairing.get('endReason') === reason) return null; // idempotent retry
    const state = liveness(pairing, now);
    if (state === 'expired') {
      end(tx, pairing, 'expired', 'expired');
      release(tx, inviterLock, pairingId);
      release(tx, inviteeLock, pairingId);
      return new PairingError('pairing_expired');
    }
    if (state !== 'live') return new PairingError('pairing_not_open');
    if (action === 'reject' && (role !== 'inviter' || pairing.get('status') !== 'claimed')) {
      return new PairingError('pairing_not_open');
    }
    end(tx, pairing, target, reason, { endedByDeviceId: step.deviceId });
    release(tx, inviterLock, pairingId);
    release(tx, inviteeLock, pairingId);
    return null;
  });
  if (failure !== null) await raise(db, accountId, failure, now);
}

export const rejectPairing = (db: Firestore, uid: string | undefined, data: unknown, now: Date) =>
  endByParticipant(db, uid, data, now, 'reject');

export const cancelPairing = (db: Firestore, uid: string | undefined, data: unknown, now: Date) =>
  endByParticipant(db, uid, data, now, 'cancel');

export type PairingState =
  | { readonly state: 'none' }
  | { readonly state: 'paired'; readonly coupleId: string | null; readonly conversationId: string | null }
  | { readonly state: 'invited'; readonly pairingId: string; readonly expiresAtMillis: number }
  | {
      readonly state: 'awaiting_confirmation';
      readonly role: 'inviter' | 'invitee';
      readonly pairingId: string;
      readonly confirmationCode: string;
      readonly partnerDisplayName: string | null;
      readonly expiresAtMillis: number;
    };

/**
 * The caller's own pairing state: a read, no proof, no writes. It reveals
 * only the caller's own pairing and, once someone accepted, the other
 * participant's display name; never tokens, account IDs or device IDs.
 */
export async function getPairingState(db: Firestore, uid: string | undefined, now: Date): Promise<PairingState> {
  const accountId = requireAccount(uid);
  const partner = await partnerRef(db, accountId).get();
  if (partner.exists) {
    const coupleId = partner.get('coupleId') as unknown;
    const conversationId = partner.get('conversationId') as unknown;
    return {
      state: 'paired',
      coupleId: typeof coupleId === 'string' ? coupleId : null,
      conversationId: typeof conversationId === 'string' ? conversationId : null,
    };
  }
  const lock = await lockRef(db, accountId).get();
  const id = lock.exists ? (lock.get('pairingId') as unknown) : undefined;
  if (typeof id !== 'string' || !RECORD_ID_PATTERN.test(id)) return { state: 'none' };
  const pairing = await pairingRef(db, id).get();
  if (!pairing.exists || liveness(pairing, now) !== 'live') return { state: 'none' };
  const role =
    pairing.get('inviterAccountId') === accountId ? 'inviter' : pairing.get('inviteeAccountId') === accountId ? 'invitee' : null;
  if (role === null) return { state: 'none' };
  if (pairing.get('status') === 'pending') {
    return { state: 'invited', pairingId: id, expiresAtMillis: (pairing.get('expiresAt') as Timestamp).toMillis() };
  }
  const other = validAccount(pairing.get(role === 'inviter' ? 'inviteeAccountId' : 'inviterAccountId'));
  const code = pairing.get('confirmationCode') as unknown;
  if (typeof code !== 'string') return { state: 'none' };
  const profile = other === null ? null : await profileRef(db, other).get();
  return {
    state: 'awaiting_confirmation',
    role,
    pairingId: id,
    confirmationCode: code,
    partnerDisplayName: displayName(profile),
    expiresAtMillis: (pairing.get('confirmExpiresAt') as Timestamp).toMillis(),
  };
}
