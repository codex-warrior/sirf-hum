/**
 * Account trust epoch (D-083): a server-side counter that only ever grows.
 * Every trust change (activation, approval, recovery, revocation, recovery
 * key registration, identity reset request/cancel/completion) bumps it in
 * the same transaction and stamps it on the records it changes. Devices keep
 * the highest epoch they have seen (sealed, Rust core) and fail closed on an
 * older one, which detects stale or rolled-back server views. It does not
 * detect a rollback of a device's own files (D-079, still open).
 */
import type { DocumentReference, DocumentSnapshot, Transaction } from 'firebase-admin/firestore';

export function currentEpoch(trust: DocumentSnapshot): number {
  const value = trust.exists ? (trust.get('trustEpoch') as unknown) : 0;
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

/**
 * Writes epoch+1 to the account trust record (creating it with `create` when
 * it does not exist yet) and returns the new epoch. Call after all reads.
 */
export function bumpEpoch(
  tx: Transaction,
  trustRef: DocumentReference,
  trust: DocumentSnapshot,
  fields: Record<string, unknown> = {},
): number {
  const next = currentEpoch(trust) + 1;
  if (trust.exists) tx.update(trustRef, { ...fields, trustEpoch: next });
  else tx.create(trustRef, { ...fields, trustEpoch: next });
  return next;
}
