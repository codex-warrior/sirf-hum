/**
 * Pairing and couple vocabulary (Prompt 12, D-100–D-105).
 * docs/security/COUPLE-AND-PAIRING.md §4 (state machine) and §5 (schema).
 *
 * The transition table is the single authority for pairing status changes:
 * every server write that changes `status` goes through `assertTransition`,
 * and clients cannot write pairings at all (rules deny).
 */

export const PAIRING_SCHEMA_VERSION = 1;
export const COUPLE_SCHEMA_VERSION = 1;

/** Server-authoritative lifetimes. Clients only display them. */
export const PairingTTL = {
  /** An unredeemed invitation (Prompt 04 default: 24 h). */
  invitationMs: 24 * 60 * 60 * 1000,
  /** After the invitee accepts, the inviter has this long to confirm. */
  confirmationMs: 24 * 60 * 60 * 1000,
} as const;

export const CoupleCollections = {
  pairings: 'pairings',
  /** Server-only: the one open pairing an account takes part in. */
  pairingLocks: 'pairingLocks',
  couples: 'couples',
  /** Account profiles live on the account document `users/{uid}`. */
  users: 'users',
} as const;

/**
 * `pending`     invitation created, token outstanding
 * `claimed`     the invitee accepted with the token; bound to that account
 *               and device; awaiting the inviter's confirmation
 * `accepted`    the inviter confirmed; couple and conversation exist
 * `rejected`    the inviter refused the account that claimed it
 * `cancelled`   withdrawn by a participant, or superseded
 * `expired`     past its server-side deadline
 * `invalidated` a participant's trust changed (identity reset, device no
 *               longer active, already paired elsewhere): fail closed
 */
export type PairingStatus = 'pending' | 'claimed' | 'accepted' | 'rejected' | 'cancelled' | 'expired' | 'invalidated';

export const PAIRING_STATUSES: readonly PairingStatus[] = [
  'pending',
  'claimed',
  'accepted',
  'rejected',
  'cancelled',
  'expired',
  'invalidated',
];

/** Every allowed move. Anything absent is invalid; terminal states have none. */
export const TRANSITIONS: Readonly<Record<PairingStatus, readonly PairingStatus[]>> = {
  pending: ['claimed', 'cancelled', 'expired', 'invalidated'],
  claimed: ['accepted', 'rejected', 'cancelled', 'expired', 'invalidated'],
  accepted: [],
  rejected: [],
  cancelled: [],
  expired: [],
  invalidated: [],
};

export const OPEN_STATUSES: readonly PairingStatus[] = ['pending', 'claimed'];

export class IllegalTransitionError extends Error {
  constructor() {
    super('illegal_transition');
  }
}

export function isPairingStatus(value: unknown): value is PairingStatus {
  return typeof value === 'string' && (PAIRING_STATUSES as readonly string[]).includes(value);
}

/** Throws (an internal error, never a client category) on an invalid move. */
export function assertTransition(from: unknown, to: PairingStatus): void {
  if (!isPairingStatus(from) || !TRANSITIONS[from].includes(to)) throw new IllegalTransitionError();
}

/** The steps a device signs (each bound to its subject by the challenge). */
export const PAIRING_ACTIONS = ['create', 'accept', 'confirm', 'reject', 'cancel'] as const;
export type PairingAction = (typeof PAIRING_ACTIONS)[number];

/** Couple lifecycle. V1 implements `active` only; dissolution is deferred (D-105). */
export type CoupleStatus = 'active';

/** Safe, stable failure categories (never data). Mapped to HttpsError codes. */
export type PairingFailure =
  /** The token does not redeem, for whatever reason (uniform: no oracle). */
  | 'invitation_invalid'
  /** No such pairing, or the caller is not its participant (uniform). */
  | 'pairing_not_found'
  /** The pairing is in a state where this step is not allowed. */
  | 'pairing_not_open'
  | 'pairing_expired'
  /** A participant's trust changed during pairing; start again. */
  | 'pairing_invalidated'
  /** The account already takes part in another open pairing. */
  | 'pairing_in_progress'
  | 'already_paired'
  /** The account has a pending identity reset (D-082): no pairing. */
  | 'identity_reset_pending';

export class PairingError extends Error {
  constructor(readonly failure: PairingFailure) {
    super(failure);
  }
}
