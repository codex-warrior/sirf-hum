# Firebase Architecture

Status: **Boundaries established (Prompt 01). Device registry open
(Prompt 07): `users/{uid}/devices/{deviceId}` rules + activation Functions
(emulator-only until Blaze).**
Messaging (Prompt 10): `conversations/*` with keyPackages, commits,
Welcomes and messages; server-only `pairings`, `accountPartners` and the
`provisionConversation` primitive (emulator-only; no callable). See
[E2EE-MESSAGING-DESIGN](../security/E2EE-MESSAGING-DESIGN.md).

## Principle

Firebase is the application backend — **not** a trusted plaintext store for
private relationship content. Firestore and Storage hold metadata and
ciphertext. Security Rules and Cloud Functions enforce *who may access
ciphertext*; they do not provide confidentiality. Confidentiality comes from
end-to-end encryption ([E2EE-REQUIREMENTS](../security/E2EE-REQUIREMENTS.md)).

## Services and their purpose

Each service is used only for a documented purpose. Unlisted Firebase
products are not used without a Decision Log entry.

| Service | Purpose | Phase | Privacy notes |
| --- | --- | --- | --- |
| **Authentication** | Per-person account identity | Identity | Auth identifies a *person*, not a couple, and is not a device or cryptographic identity |
| **Cloud Firestore** | Primary database: accounts, couple membership, device registry, public key directory, content metadata, encrypted payloads | Identity onward | No plaintext private content |
| **Cloud Storage** | Encrypted media blobs | Moments | Ciphertext only; names/paths must not leak content |
| **Cloud Functions** | Trusted server logic: pairing invariants, LiveKit token minting, notification fan-out, scheduled cleanup, subscription verification | Identity onward | Never needs content keys |
| **Cloud Messaging (FCM)** | Wake-up / notification delivery | Messaging | Privacy-safe payloads (below) |
| **App Check** | Reduce abuse from non-genuine clients | Wired, not enforced (Prompt 02) | Defence in depth, not authorization, not encryption |
| **Security Rules** | Server-side authorization for Firestore/Storage | Every phase | Default deny; tested in emulator |
| **Crashlytics** | Crash diagnostics on Android/iOS | Wired (Prompt 02) | Not on web. Receives only sanitized `AppLogger` records; errors as `RedactedError(type)` (D-027) |
| **Hosting** | Serves the Flutter web app (target `app`) | Configured (Prompt 02) | Security headers set; CSP pending |
| **Remote Config** | Feature flags and kill switches | When needed | Never for security-critical decisions |

Not planned: Realtime Database, Firebase Analytics with default
auto-collection (pending [ANALYTICS-POLICY](../security/ANALYTICS-POLICY.md)),
Dynamic Links (deprecated).

## Data classification

Every field in every future schema is assigned one class. Schemas are
designed in the phase that introduces them.

| Class | Examples | Storage rule |
| --- | --- | --- |
| **Private content** | Message text, photos, videos, voice, letters, vault items, memory captions, plan details the couple considers private | **Ciphertext only** (`encryptedPayload` + `encryptionVersion`) |
| **Cryptographic metadata** | Public identity keys, device public keys, key versions, signatures, wrapped keys | Plaintext allowed (public material); integrity protected by signatures |
| **Relationship metadata** | Couple membership, pairing state, who is in a conversation | Plaintext, minimised, rules-protected; sensitive (reveals a relationship) |
| **Operational metadata** | Timestamps, delivery state, sizes, sender device ID, schema versions | Plaintext, minimised; consider padding/bucketing where it leaks content |
| **Account data** | Auth UID, contact identifiers used for sign-in | Minimised; never shared with partner by default |

Conceptual example (not a final schema):

```text
messages/{messageId}
  conversationId
  senderDeviceId
  encryptedPayload      // ciphertext — never "I love you ❤️"
  encryptionVersion
  createdAt
  deliveryState
```

## Security Rules policy

- `firebase/firestore.rules` and `firebase/storage.rules` are **default-deny**.
- Paths are opened only in the phase that needs them, **together with
  emulator tests** in `firebase/tests/` covering allowed *and* denied cases
  (other couple, ex-partner, revoked device, unauthenticated).
- Never weaken rules to make a feature work. Fix the model or move the
  operation into a Cloud Function.
- Couple membership is a necessary condition for access to couple data,
  never a sufficient one for access to a partner's *account* data.

## Device registry (Prompt 07)

Full design: [DEVICE-IDENTITY](../security/DEVICE-IDENTITY.md) (D-069,
D-070).

| Path | Client access | Server (Admin SDK) |
| --- | --- | --- |
| `users/{uid}/devices/{deviceId}` | Owner and, once provisioned, the partner (D-086): read. **No client write at all** (Prompt 09) | `registerDevice` creates `pending`; `activateDevice` (first device only), `approveDevice`, `recoverDevice` set `active` with signed evidence; `rejectDeviceApproval` sets `rejected`; cleanup sets `expired`; `revokeDevice` (signed, D-081) and `completeIdentityReset` set `revoked` |
| `deviceChallenges/{id}` | None | `issueDeviceChallenge` creates; consumed by the first attempt |
| `deviceApprovalRequests/{id}` | None | `requestDeviceApproval` / `proveDeviceEnrollment`; consumed by approval, rejection or recovery |
| `accountTrust/{uid}` | Owner and partner (D-086): read. No write | Bootstrap marker (`firstDeviceId`, `bootstrapOpen`), `trustEpoch` (D-083), `identityEpoch` and `reset` (D-082), recovery key **public** half with its registration evidence |
| `rateLimits/{uid}__{op}` | None | Per-account rate limits (D-077) |
| `deviceIdIndex/{deviceId}`, `deviceKeyIndex/{sha256}` | None | Global uniqueness of activated device IDs and keys, kept forever |

Callables:

- `registerDevice`, `issueDeviceChallenge`, `activateDevice`;
- `requestDeviceApproval`, `proveDeviceEnrollment`,
  `listDeviceApprovalRequests`, `approveDevice`, `rejectDeviceApproval`;
- `registerRecoveryKey`, `recoverDevice`;
- `revokeDevice` (D-081);
- `requestIdentityReset`, `cancelIdentityReset`, `completeIdentityReset` (D-082).

Plus the scheduled `cleanupExpiredDeviceRecords`. All run in
`asia-south1` with `enforceAppCheck: true` and category-only errors.
Design: [MULTI-DEVICE-TRUST](../security/MULTI-DEVICE-TRUST.md). Tests:

- `firebase/tests/devices.test.js` (rules);
- `functions/test/device_proof.test.mjs`, `functions/test/statements.test.mjs` (verifiers, golden vectors);
- `functions/test/hardening.test.mjs` (revocation/reset statements, v2 vectors, log guard);
- `functions/test/emulator/` (flows; `hardening.test.mjs`: revocation, reset, epoch, races, rate-limit boundaries).

## Private messaging (Prompt 10)

Full design: [E2EE-MESSAGING-DESIGN](../security/E2EE-MESSAGING-DESIGN.md)
(D-085–D-091). Firestore holds ciphertext, MLS handshake bytes and public
metadata only. Sending and receiving need **no Cloud Function** (they work
on Spark); only provisioning is server code.

| Path | Client access | Server |
| --- | --- | --- |
| `pairings/{id}` | None | Written by the future pairing phase (`status: 'accepted'`, both accounts) |
| `accountPartners/{uid}` | Owner: read | `provisionConversation` writes `partnerAccountId`, `conversationId` |
| `conversations/{id}` | Members: read. Update **only** `epoch` → `epoch + 1`, in the same batch as the new `commits/{epoch}` | `provisionConversation` creates it: `members`, `state`, `epoch: 0`, versions, ciphersuite |
| `.../keyPackages/{deviceId}` | Members: read. A member writes/deletes only for its own **active** device | — |
| `.../commits/{epoch}` | Members: read. **Create-only, one per epoch** (first wins), by a member's active device, at the current epoch, with the epoch move | — |
| `.../welcomes/{device}_{epoch}` | Members: read. Create-only, only beside their own commit in the same batch | — |
| `.../messages/{messageId}` | Members: read. **Create-only**: exact fields (no plaintext), current epoch, sender's own active device, ciphertext ≤ 32 KiB, `serverTime == request.time`. No update or delete | — |

Clients write commits and messages in **transactions** (never the offline
write queue). Rules authorize access to ciphertext per account; MLS decides
which devices hold keys (E2EE-MESSAGING-DESIGN §9). Retention, server-side
deletion and FCM wake-ups are not implemented yet (Prompt 11 and later).

Tests: `firebase/tests/messaging.test.js` (own `demo-` project, so parallel
test files cannot interfere), `functions/test/emulator/conversation.test.mjs`.

## Cloud Functions policy

- TypeScript, strict mode, in `functions/`. Region `asia-south1` (D-016),
  `maxInstances` guardrail. Each instance verifies at cold start that
  `SH_ENV` (from `functions/.env.<alias>`) matches its project.
- Functions validate every input, check membership server-side, and are
  idempotent where retried.
- Secrets via Functions secret manager (`defineSecret`), never in code.
- No function ever receives content keys or plaintext private content.

## LiveKit integration

- Clients never hold LiveKit API secrets.
- A callable Cloud Function verifies the caller's auth + couple membership
  and mints a short-lived, room-scoped LiveKit token.
- Room names are opaque (no names or relationship info).
- Whether call media uses LiveKit's E2EE (insertable streams / frame
  encryption) with keys from the Sirf Hum key system is decided in the
  calls phase; until verified, calls must not be described as E2EE.

## Notifications

Push payloads are processed by Google/Apple/browser push services, which
are **outside** the trust boundary.

- Payloads carry no private content. Preferred: *"You have a new message"*,
  not *"Rahul: I miss you ❤️"*.
- Data messages carry only opaque IDs for deep-linking (`/together`,
  `/moments/...`). Any richer preview must be decrypted **on device**
  (e.g. iOS Notification Service Extension / Android data message) and is a
  separate reviewed decision.
- Must support: preferences per category, quiet hours, batching/collapse
  keys, delivery handling, and token cleanup on device revocation.

## Emulators and local development

- `firebase.json` configures Auth, Firestore, Storage, Functions emulators.
- Rules tests use the `demo-sirf-hum` project ID (the `demo-` prefix
  guarantees no real project is touched).
- `.firebaserc` defines `development` / `staging` / `production` aliases and
  deliberately **no default** (D-024).

## Provisioning status (Prompt 02)

| | sirf-hum-dev | sirf-hum-staging | sirf-hum-prod |
| --- | --- | --- | --- |
| Project + Android/iOS/Web apps | Created | Created | Created |
| Firestore `(default)`, Native, `asia-south1` | Created | Created | Created (delete protection on) |
| Firestore rules | Deny-all deployed from repo | Firebase default (deny-all) | Firebase default (deny-all) |
| APIs: Firestore, App Check, Identity Toolkit, Crashlytics, FCM | Enabled | Enabled | Enabled |
| Auth sign-in providers | None (D-029) | None | None |
| Cloud Storage bucket | **Blocked: needs Blaze** | **Blocked** | **Blocked** |
| Cloud Functions | **Blocked: needs Blaze** (device activation written and emulator-tested, Prompt 07) | **Blocked** | **Blocked** |
| Hosting default site | Exists, nothing deployed | Exists | Exists |

Reproduce with `tool/provision_firebase.sh <env>`.

## Known Windows issue

`firebase emulators:exec` on Windows can leave the Firestore emulator Java
process running after tests finish, holding port 8080. Stop it before the
next run.
