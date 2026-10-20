/**
 * Per-account, fixed-window rate limits (D-077).
 *
 * Keys are the caller's own account plus an operation, so a limit never
 * reveals anything about another account (no enumeration oracle): every
 * caller sees the same `rate_limited` category, and counters live in the
 * server-only `rateLimits` collection. Firestore transactions keep counts
 * exact under concurrency.
 */
import { type Firestore, Timestamp } from 'firebase-admin/firestore';
import { Collections, DeviceError } from './common';

export interface Limit {
  readonly max: number;
  readonly windowMs: number;
}

const HOUR = 60 * 60 * 1000;

/** Documented in DEVICE-IDENTITY §15 ("Rate limits"). */
export const LIMITS = {
  /** Registering pending devices. */
  register: { max: 5, windowMs: HOUR },
  /** Activation / recovery-registration challenges. */
  challenge: { max: 10, windowMs: HOUR },
  /** Approval requests opened by new devices. */
  approvalRequest: { max: 5, windowMs: HOUR },
  /** Failed proofs, approvals or recovery signatures (any kind). */
  verificationFailure: { max: 5, windowMs: HOUR },
  /** Recovery-key attempts. */
  recovery: { max: 3, windowMs: 24 * HOUR },
  /** Signed revocations. */
  revocation: { max: 10, windowMs: HOUR },
  /** Identity reset requests and completions (D-082). */
  identityReset: { max: 3, windowMs: 7 * 24 * HOUR },
  /** Push token challenges (Prompt 11, D-098): start-ups and rotations. */
  pushToken: { max: 20, windowMs: HOUR },
  /** MLS commit challenges (Prompt 17B, D-127): group creation, adds, removals, updates. */
  commit: { max: 60, windowMs: HOUR },
  /** Pairing step challenges (Prompt 12, D-103): every create/accept/confirm/reject/cancel. */
  pairing: { max: 30, windowMs: HOUR },
  /** Pairing invitations created. */
  pairingInvitation: { max: 10, windowMs: 24 * HOUR },
  /** Invitation tokens that did not redeem (unknown, used, expired, own). */
  pairingRedeemFailure: { max: 10, windowMs: HOUR },
} as const satisfies Record<string, Limit>;

export type LimitName = keyof typeof LIMITS;

const ref = (db: Firestore, accountId: string, name: LimitName) =>
  db.collection(Collections.rateLimits).doc(`${accountId}__${name}`);

/** Counts one use; throws `rate_limited` once the window's budget is spent. */
export async function consume(db: Firestore, accountId: string, name: LimitName, now: Date): Promise<void> {
  const limit: Limit = LIMITS[name];
  const allowed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref(db, accountId, name));
    const start = snap.get('windowStart') as unknown;
    const inWindow = start instanceof Timestamp && now.getTime() - start.toMillis() < limit.windowMs;
    const count = inWindow ? Number(snap.get('count') ?? 0) : 0;
    if (count >= limit.max) return false;
    tx.set(ref(db, accountId, name), {
      windowStart: inWindow ? start : Timestamp.fromDate(now),
      count: count + 1,
    });
    return true;
  });
  if (!allowed) throw new DeviceError('rate_limited');
}

/** Throws `rate_limited` if the budget is already spent, without counting. */
export async function requireBudget(db: Firestore, accountId: string, name: LimitName, now: Date): Promise<void> {
  const limit: Limit = LIMITS[name];
  const snap = await ref(db, accountId, name).get();
  const start = snap.get('windowStart') as unknown;
  const inWindow = start instanceof Timestamp && now.getTime() - start.toMillis() < limit.windowMs;
  if (inWindow && Number(snap.get('count') ?? 0) >= limit.max) throw new DeviceError('rate_limited');
}
