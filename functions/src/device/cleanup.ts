/**
 * Expiry of stale device-trust records (D-078).
 *
 * Expiry is server-authoritative and enforced lazily on every operation
 * (registration.ts / trust.ts treat an expired record as expired whether or
 * not this job has run). This job only tidies up:
 *   - pending devices past `expiresAt` → status `expired` (never deleted, so
 *     their IDs can never be reused; active/revoked records are untouched);
 *   - challenges and approval requests past `expiresAt` → deleted.
 * Idempotent: rerunning changes nothing more. Scheduling it needs Cloud
 * Scheduler, i.e. the Blaze plan (D-025); until then it runs in tests only.
 */
import { type Firestore, Timestamp } from 'firebase-admin/firestore';
import { Collections } from './common';

export interface CleanupResult {
  readonly expiredDevices: number;
  readonly deletedChallenges: number;
  readonly deletedRequests: number;
}

const PAGE = 200;

async function deleteExpired(db: Firestore, collection: string, now: Timestamp): Promise<number> {
  let total = 0;
  for (;;) {
    const page = await db.collection(collection).where('expiresAt', '<=', now).limit(PAGE).get();
    if (page.empty) return total;
    const batch = db.batch();
    page.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    total += page.size;
  }
}

export async function cleanupExpired(db: Firestore, now: Date): Promise<CleanupResult> {
  const at = Timestamp.fromDate(now);
  let expiredDevices = 0;
  for (;;) {
    const page = await db
      .collectionGroup(Collections.devices)
      .where('status', '==', 'pending')
      .where('expiresAt', '<=', at)
      .limit(PAGE)
      .get();
    if (page.empty) break;
    for (const doc of page.docs) {
      // Re-check inside a transaction: never touch a device that was
      // activated or revoked since the query ran.
      const changed = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        const expiresAt = fresh.get('expiresAt') as unknown;
        if (fresh.get('status') !== 'pending' || !(expiresAt instanceof Timestamp) || expiresAt.toMillis() > now.getTime()) {
          return false;
        }
        tx.update(doc.ref, { status: 'expired' });
        return true;
      });
      if (changed) expiredDevices += 1;
    }
  }
  return {
    expiredDevices,
    deletedChallenges: await deleteExpired(db, Collections.challenges, at),
    deletedRequests: await deleteExpired(db, Collections.approvalRequests, at),
  };
}
