/**
 * Which account a callable request may act for (D-138, D-149, D-150).
 *
 * Sign-in is Google or email link; both yield a verified email for real
 * users, and neither grants anything beyond naming the account: the
 * provider is deliberately not read here or anywhere else (device trust is
 * device-key proofs). But
 * Firebase Auth cannot offer email links without the Email/Password
 * provider, so anyone with the public API key can still create a
 * *password* account for an address they do not control. Such an account
 * is unverified until the address's owner signs in by link (Firebase then
 * removes the password and revokes the old sessions; verified on staging,
 * Prompt 19). Refusing unverified accounts here means that, in the
 * meantime, it cannot register or activate a first device, register a
 * recovery key, pair or do anything else that would outlive its session.
 */
export interface CallableAuth {
  uid: string;
  token: { email_verified?: boolean };
}

/** The uid to act for, or undefined (domain code answers `unauthenticated`). */
export function verifiedUid(auth: CallableAuth | undefined): string | undefined {
  return auth?.token.email_verified === true ? auth.uid : undefined;
}
