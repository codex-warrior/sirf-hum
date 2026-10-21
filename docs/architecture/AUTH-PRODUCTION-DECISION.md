# Production Authentication Decision

Status: **Accepted by the owner (D-138), 2026-10-21. Built for Android in
Prompt 19 (D-148); staging configuration in progress; production not
configured. Amended by D-150 (owner request, 2026-10-21): "Continue with
Google" is the primary provider and email link the fallback; see §11.**
Follows D-029 (no provider before the identity
phase; intended baseline "email link or email/password") and D-107
(session observation only; sign-in method open).

> Authentication answers *which account is this*. It never answers *which
> device may hold keys*: device trust stays with person keys (PIKs), device
> certificates and device-key proofs (D-070, D-081, D-127). Nothing in this
> decision changes that.

## 1. Decision

| | |
| --- | --- |
| **Selected provider** | Firebase Authentication **email link (passwordless)** |
| Not offered in V1 | Email/password, phone (SMS), Google/other social sign-in, anonymous accounts |
| Required project settings | Email-enumeration protection **on**; authorized domains limited to the app's Hosting domain(s); link domain = the production Hosting domain (`app.sirfhum.com` when attached) |
| Client | `sendSignInLinkToEmail` with `ActionCodeSettings(handleCodeInApp: true, androidPackageName: com.sirfhum.app, linkDomain: <hosting domain>)`; the email is kept locally (not in logs) until the link returns; a link opened on another device asks for the email again |
| Accounts | One Firebase UID per email; the UID names the account in server records and is bound into device proofs **as the account**, never as a key or cryptographic identity (D-100) |

## 2. Why this provider

| Option | Assessment |
| --- | --- |
| **Email link** | No password to reuse, stuff, phish or leak. Account control = control of the mailbox, which is already true of any email/password account through password reset. One path instead of two. Within D-029's baseline. **Selected** |
| Email/password | Adds a second credential (the password) with its own reuse and phishing risks and a reset flow that still falls back to email: strictly more attack surface for the same root of trust |
| Phone (SMS) | Cost per SMS, SIM-swap and SMS-pumping fraud, and a phone number is more identifying than an email (D-029). Rejected |
| Google sign-in | Strong and convenient on Android, but outside D-029's baseline ("social only if justified") and ties the account to a Google identity. Reconsider only with a written justification |
| Anonymous | No recovery; accounts would be created by anyone with the public API key. Rejected |

## 3. What a compromised account can and cannot do

The architecture assumes the password/mailbox **will** sometimes be
compromised (THREAT-MODEL T6, E42):

| An attacker with the account session can | Cannot |
| --- | --- |
| See the account's metadata (device list, couple, conversation IDs, sizes, times: METADATA-EXPOSURE) | Read any message, photo, moment or notebook entry (MLS; no device key) |
| Register a **pending** device | Activate it: activation needs an existing trusted device's signed approval or the recovery key (D-070, D-076) |
| Request an identity reset | Complete it for 7 days; every trusted device is alerted and can cancel (D-082, D-132); a completed reset yields a **new, unverified** identity that the partner must re-verify (D-128) |
| Read ciphertext the account may read | Commit, recover, unpair, approve, reject, revoke or register push tokens: each needs a device-key proof (purposes 1–8) |

So the auth provider bounds metadata exposure and availability, not
confidentiality. That is why "the authentication system must not become
the device trust system" is a design invariant, enforced by the static and
emulator tests listed in [TEST-MATRIX](../security/audit/TEST-MATRIX.md)
("password-only session" cases for every device-bound callable).

## 4. Account recovery implications

- Lost mailbox access = lost account access; Sirf Hum adds no support
  back door (a support reset would be a password-only takeover path).
- Lost **phone** with mailbox access: sign in on the new phone; it is a
  pending device until approved by another trusted device or the recovery
  key, otherwise an identity reset (7 days, new identity, partner
  re-verifies). History on the lost phone is not recoverable by design
  (no escrow, RECOVERY-AND-REVOCATION).
- The recovery key is device-trust recovery, not account recovery; it is
  never entered on web (WEB-SECURITY).

## 5. Session security

- Firebase ID tokens: 1 hour, refreshed by a long-lived refresh token in
  app-private storage (Android: excluded from backup, D-123). On web, the
  Firebase JS SDK persists the session in IndexedDB (account features only,
  no private content, D-046).
- Sign-out clears the session (D-107) and every account-scoped controller
  (tests: `account A → sign out → account B …`).
- Sensitive operations never rely on token freshness: they need a device
  proof. Revoking refresh tokens server-side (Admin SDK) is the response to
  a suspected session theft; it is an owner/operator action today.

## 6. Abuse and rate limiting

- Email-link sends are limited by Firebase per project and per address
  (Firebase quotas; not configurable to zero). With **App Check** enforced
  on Authentication (Identity Toolkit) the sends come only from genuine
  builds (APP-CHECK-PRODUCTION, step 9).
- Email-enumeration protection makes "does this email have an account?"
  unanswerable through the sign-in API.
- Everything after sign-in is rate-limited per account in Functions
  (DEVICE-IDENTITY §15, `rateLimit.ts`).
- Residual: an attacker can make Firebase send sign-in emails to a victim
  (annoyance, phishing pretext). Mitigated by quotas and App Check; the
  email template must say "if you didn't ask, ignore this".

## 7. Privacy implications

- Firebase Auth stores the email address and sign-in times (global
  service, D-016: not region-pinned). No phone number, no name from a
  social provider.
- The email is never logged (`AppLogger` redacts strings) and never shown
  to the partner (the partner sees the display name only).
- Sending email goes through Firebase's mail infrastructure (Google).

## 8. Account deletion implications

Account deletion is **not built** (P2-8; Google Play requires it before
public launch). The required order, so deletion never leaves a dangling
trust or couple state:

1. Device proof from an active device (no password-only deletion, the same
   reasoning as D-136).
2. Unpair if paired (D-136 transaction).
3. Revoke all devices and delete push tokens; delete the recovery key
   record.
4. Delete server records the account owns (profile, devices, trust state,
   rate limits); the couple's retained ciphertext follows the retention
   decision (P2-8).
5. Delete the Firebase Auth user **last** (Admin SDK), so a failure leaves
   a consistent, signed-in state to retry from.

A device that cannot produce a proof (all phones lost) needs an identity
reset first; that delay is deliberate.

## 9. Attack scenarios

| Scenario | Outcome |
| --- | --- |
| Phished / guessed credentials | Not applicable (no password). Mailbox phishing: as §3 |
| Mailbox takeover | As §3: metadata, pending devices, a delayed and alerted reset; no content |
| Stolen session token (malware, web IndexedDB) | As §3 |
| Intercepted sign-in link | Signs in as the account (= session, §3). Links are single-use and expire; the email must match the one entered on that device |
| Link opened on an attacker's device | Needs the email typed again; still only an account session |
| Email enumeration | Blocked by enumeration protection |
| Mass account creation (public API key) | App Check on Auth + quotas; accounts without trusted devices hold nothing |
| SIM swap | Not applicable (no phone auth) |
| Firebase/Google insider issues a token | Account session only; no device key (T3) |

## 10. Manual steps (owner; none performed)

In each project, staging before production:

1. Firebase console → **Authentication → Get started** (initializes
   Identity Toolkit configuration; production currently answers
   `CONFIGURATION_NOT_FOUND`).
2. Sign-in method → **Email/Password** provider → enable **Email link
   (passwordless sign-in)** only; leave "Email/Password" (password) **off**. **Correction (Prompt 19, D-149):** the password method cannot be turned off on Firebase Auth while email link is on; callables therefore require `email_verified`, and the app offers no password path.
3. Settings → **User actions → Email enumeration protection: on**.
4. Settings → **Authorized domains**: only the Hosting domain(s) of that
   project (remove `localhost` in production).
5. Templates: sign-in email text in the app's voice, including "if you
   didn't ask for this, ignore it"; sender domain verified.
6. After APP-CHECK-PRODUCTION steps 1–8: enforce App Check for
   Authentication.

Code (a later, authorized prompt): the sign-in screen, link handling
(Android App Links on the Hosting domain), the "open on another device"
path, tests including account switch during the link round-trip.

## 11. Status

P1-7 stays **open** until production Auth is configured and both
providers are tested on a production-signed phone. Built: email link
(D-148) and Google (D-150) on Android. Staging Auth is configured for
email link only (no Google provider yet). Development and production Auth
are not initialized (verified 2026-10-21: `CONFIGURATION_NOT_FOUND`).

## 12. Google sign-in (D-150)

Owner request (2026-10-21): **Continue with Google** first, **Continue
with Email** (this document's email link) as the fallback, in every
environment. §2's "reconsider only with a written justification" is met by
D-150: Google is what most Android users already have on the phone, it
adds no password, and it changes nothing in §3: a Google session is still
only an account session.

| | |
| --- | --- |
| Flow | `google_sign_in` 7.2.0 (Credential Manager) → Google **ID token** for the project's Web OAuth client → `signInWithCredential(GoogleAuthProvider.credential(idToken))`. No access token, no scopes, nothing stored, no token to our backend, no client secret in any client |
| New vs existing | Firebase decides; the app treats both the same (only a `new_account` boolean is logged) |
| Same email, two providers | One account per email (staging verified: `allowDuplicateEmails` unset). Google for an address Firebase trusts Google for → same UID. Otherwise `account-exists-with-different-credential` → "Continue with Email"; the app **never links** accounts. Email link to a Google address → same UID |
| Unverified | Signed out at once; callables refuse it anyway (D-149) |
| Privacy (§7 addition) | Firebase Auth keeps the Google account's name and photo URL on the Auth user record. Sirf Hum never reads them (the couple sees the display name the user types) |
| Compromised Google account | Same as a compromised mailbox (§3, §9): metadata and a pending device, never content |

### Console steps per project (owner; staging first, then production)

Only the console can do these: enabling Google creates the Web OAuth
client **and its secret**, which stays inside Firebase and must never be
copied into the repository.

1. (Production and development only) **Authentication → Get started**.
2. **Authentication → Sign-in method → Add new provider → Google →
   Enable**; choose the project support email; Save.
3. **Project settings → Your apps → that project's Android app only**
   (`com.sirfhum.app.staging` / `com.sirfhum.app`) → **Add fingerprint** →
   the **SHA-1** of that environment's signing key (staging: from the
   Staging beta build job summary; production: from the production upload
   key, later also Play's app-signing key). Never add a staging fingerprint
   to production or the reverse.
4. Production only: §10 steps 2–5 (email link, enumeration protection,
   authorized domains, templates).
5. Then `node tool/generate_env_config.mjs <env>` regenerates the config,
   now with `SH_GOOGLE_SERVER_CLIENT_ID`, and the environment's
   `SH_ENV_CONFIG_JSON` GitHub secret is updated from it.
