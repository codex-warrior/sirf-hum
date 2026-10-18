/**
 * Shared vocabulary for the device trust Functions (D-069, D-075–D-079).
 * Data model: docs/security/DEVICE-IDENTITY.md §4 and §15.
 */
import type { DocumentReference, Firestore } from 'firebase-admin/firestore';

export const DEVICE_SCHEMA_VERSION = 1;
export const ACCOUNT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
export const DEVICE_ID_PATTERN = /^[0-9a-f]{32}$/;
export const RECORD_ID_PATTERN = /^[0-9a-f]{32}$/;
export const PLATFORMS = ['android', 'ios'] as const;

/** Server-authoritative lifetimes (D-078). */
export const TTL = {
  /** Activation / recovery-registration challenge. */
  challengeMs: 5 * 60 * 1000,
  /** Approval request: the user has this long to approve on a trusted device. */
  approvalRequestMs: 10 * 60 * 1000,
  /** A registered device that is never activated expires after this. */
  pendingDeviceMs: 7 * 24 * 60 * 60 * 1000,
  /** Identity reset takes effect only after this public, cancellable delay (D-082). */
  identityResetDelayMs: 7 * 24 * 60 * 60 * 1000,
} as const;

/** At most this many pending devices per account at a time. */
export const MAX_PENDING_DEVICES = 3;

export const Collections = {
  users: 'users',
  devices: 'devices',
  accountTrust: 'accountTrust',
  challenges: 'deviceChallenges',
  approvalRequests: 'deviceApprovalRequests',
  deviceIdIndex: 'deviceIdIndex',
  deviceKeyIndex: 'deviceKeyIndex',
  rateLimits: 'rateLimits',
} as const;

/** Device lifecycle (DEVICE-IDENTITY §3). `revoked`, `rejected`, `expired` are terminal. */
export type DeviceStatus = 'pending' | 'active' | 'revoked' | 'rejected' | 'expired';

/** Safe, stable failure categories (never data). Mapped to HttpsError codes. */
export type DeviceFailure =
  | 'invalid_argument'
  | 'unauthenticated'
  | 'device_not_found'
  | 'device_not_pending'
  | 'device_expired'
  | 'challenge_invalid'
  | 'challenge_expired'
  | 'proof_invalid'
  | 'certificate_invalid'
  | 'duplicate_device'
  | 'too_many_pending'
  | 'approval_required'
  | 'request_invalid'
  | 'request_expired'
  | 'approver_not_trusted'
  | 'approval_invalid'
  | 'recovery_unavailable'
  | 'recovery_invalid'
  | 'revocation_invalid'
  | 'reset_unavailable'
  | 'reset_not_ready'
  | 'rate_limited';

export class DeviceError extends Error {
  constructor(readonly failure: DeviceFailure) {
    super(failure);
  }
}

export function requireAccount(uid: string | undefined): string {
  if (uid === undefined) throw new DeviceError('unauthenticated');
  if (!ACCOUNT_ID_PATTERN.test(uid)) throw new DeviceError('invalid_argument');
  return uid;
}

export function requirePattern(value: unknown, pattern: RegExp): string {
  if (typeof value !== 'string' || !pattern.test(value)) throw new DeviceError('invalid_argument');
  return value;
}

/** Strict base64 of an exact byte length (bounded before decoding). */
export function requireBytes(value: unknown, length: number): Buffer {
  if (typeof value !== 'string' || value.length > Math.ceil(length / 3) * 4 + 4) {
    throw new DeviceError('invalid_argument');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length !== length || bytes.toString('base64') !== value) {
    throw new DeviceError('invalid_argument');
  }
  return bytes;
}

/** Strict base64 of 1..max bytes. */
export function requireBytesUpTo(value: unknown, max: number): Buffer {
  if (typeof value !== 'string' || value.length > Math.ceil(max / 3) * 4) {
    throw new DeviceError('invalid_argument');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length === 0 || bytes.length > max || bytes.toString('base64') !== value) {
    throw new DeviceError('invalid_argument');
  }
  return bytes;
}

export function input(data: unknown): Record<string, unknown> {
  return data !== null && typeof data === 'object' ? (data as Record<string, unknown>) : {};
}

export const deviceRef = (db: Firestore, accountId: string, deviceId: string): DocumentReference =>
  db.collection(Collections.users).doc(accountId).collection(Collections.devices).doc(deviceId);

export const trustRef = (db: Firestore, accountId: string): DocumentReference =>
  db.collection(Collections.accountTrust).doc(accountId);

/** Whole seconds, so signed expiry values round-trip exactly. */
export const toUnixSeconds = (millis: number): number => Math.floor(millis / 1000);
