/**
 * Conversation provisioning (D-086). docs/security/E2EE-MESSAGING-DESIGN.md §3.
 *
 * A SERVER-INTERNAL primitive, deliberately NOT exported as a callable:
 * conversations exist only for a couple the server has authorized. The
 * future pairing phase writes `pairings/{pairingId}` with
 * `status: 'accepted'` once both accounts have consented, then calls this.
 * Nothing in the product creates pairings yet, so no client can reach it.
 *
 * It writes, in one transaction:
 * - `conversations/{conversationId}`: members, versions, `epoch: 0`, state;
 * - `accountPartners/{uid}` for both accounts (partner directory reads);
 * - `conversationId` on the pairing (idempotency: a second call returns it).
 *
 * The conversation ID is 16 random bytes (the MLS group ID). No message
 * data, keys or plaintext ever pass through here.
 */
import { randomBytes } from 'node:crypto';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { ACCOUNT_ID_PATTERN } from '../device/common';

export const CONVERSATION_SCHEMA_VERSION = 1;
/** Sirf Hum message protocol (AAD + payload format, D-089). */
export const MESSAGE_PROTOCOL_VERSION = 1;
/** MLS ciphersuite 0x0001 (D-042). */
export const CIPHERSUITE = 1;
export const PAIRING_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export const ConversationCollections = {
  pairings: 'pairings',
  conversations: 'conversations',
  accountPartners: 'accountPartners',
} as const;

export type ProvisionFailure = 'pairing_not_found' | 'pairing_not_accepted' | 'pairing_invalid' | 'already_paired';

export class ProvisionError extends Error {
  constructor(readonly failure: ProvisionFailure) {
    super(failure);
  }
}

export interface ProvisionedConversation {
  conversationId: string;
  created: boolean;
}

export async function provisionConversation(db: Firestore, pairingId: string, newId: () => string = randomConversationId): Promise<ProvisionedConversation> {
  if (!PAIRING_ID_PATTERN.test(pairingId)) throw new ProvisionError('pairing_invalid');
  const pairingRef = db.collection(ConversationCollections.pairings).doc(pairingId);
  return db.runTransaction(async (tx) => {
    const pairing = await tx.get(pairingRef);
    if (!pairing.exists) throw new ProvisionError('pairing_not_found');
    if (pairing.get('status') !== 'accepted') throw new ProvisionError('pairing_not_accepted');
    const existing = pairing.get('conversationId') as unknown;
    if (typeof existing === 'string') return { conversationId: existing, created: false };

    const accounts = pairing.get('accounts') as unknown;
    if (
      !Array.isArray(accounts) ||
      accounts.length !== 2 ||
      !accounts.every((a): a is string => typeof a === 'string' && ACCOUNT_ID_PATTERN.test(a)) ||
      accounts[0] === accounts[1]
    ) {
      throw new ProvisionError('pairing_invalid');
    }
    const members = [...accounts].sort();
    const partnerRefs = members.map((a) => db.collection(ConversationCollections.accountPartners).doc(a));
    const partners = await Promise.all(partnerRefs.map((r) => tx.get(r)));
    // V1: one couple per account. An account already in a couple cannot be
    // provisioned into another (unpairing, which would retire it, is deferred).
    if (partners.some((p) => p.exists)) throw new ProvisionError('already_paired');

    const conversationId = newId();
    tx.create(db.collection(ConversationCollections.conversations).doc(conversationId), {
      schemaVersion: CONVERSATION_SCHEMA_VERSION,
      protocolVersion: MESSAGE_PROTOCOL_VERSION,
      ciphersuite: CIPHERSUITE,
      members,
      pairingId,
      state: 'active',
      epoch: 0,
      createdAt: FieldValue.serverTimestamp(),
    });
    members.forEach((account, i) => {
      tx.create(partnerRefs[i], {
        schemaVersion: CONVERSATION_SCHEMA_VERSION,
        partnerAccountId: members[1 - i],
        conversationId,
      });
    });
    tx.update(pairingRef, { conversationId });
    return { conversationId, created: true };
  });
}

/** 16 random bytes, lower-case hex: the conversation ID and MLS group ID. */
export function randomConversationId(): string {
  return randomBytes(16).toString('hex');
}
