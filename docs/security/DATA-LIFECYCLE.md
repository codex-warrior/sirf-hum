# Privacy and Data Lifecycle

Status: **Prompt 18, 2026-10-21.** What exists where, from creation to
deletion, as **implemented** (development; nothing deployed). Metadata
detail: [METADATA-EXPOSURE](audit/METADATA-EXPOSURE.md). No retention or
deletion policy exists yet (P2-8); this document does not invent one.

Legend: **P** = phone (sealed in the crypto core's account slot under a
Keystore-wrapped key, `noBackupFilesDir`, D-066, D-123) · **S** = server
(Firestore/Storage, ciphertext or metadata) · **F** = Firebase services
(Auth, FCM, Crashlytics, Cloud Logging).

## 1. Lifecycle by data type

| Data | Created | Where it lives | Who can read it | Ends |
| --- | --- | --- | --- | --- |
| Account | First sign-in (no provider yet, D-138) | F Auth: email, UID, sign-in times; S `users/{uid}` display name | The account; partner sees display name | Never today: **no account deletion** (P2-8) |
| Device registration | App install + registration | S `users/{uid}/devices/*`: certificate (public keys), status history, platform, approver lineage, revocation reason; P: private PIK and device key inside Rust | Server and account (public data only) | Records kept **forever** (revocation is a status; IDs/PIKs indexed forever, D-122) |
| Pairing | Invitation → acceptance → code confirmation | S `pairings/*`, `couples/*`, `accountPartners/*`: who, which devices, when, outcome | Server, the two accounts | Kept; couple `dissolved` on unpair, never reused |
| Messages | Compose | P: plaintext history sealed; S `messages/*`: MLS ciphertext (padded to 256 B), sender account+device, epoch, time | Couple's trusted devices (content); server (metadata) | "Delete for me" is local only; **server ciphertext retained** |
| Encrypted media | Photo chosen | P: picker temp copy (deleted after encryption; swept at start-up, D-141); S Storage object: STREAM ciphertext, exact size, uploader device; key inside MLS message | Couple's devices; server sees size/time | Retained; no server deletion |
| Moments | Save | Manifest as an MLS message (kind 3) + media objects | Couple's devices | Retained; no deletion/editing (D-116) |
| Future + Us | Notebook edit | MLS messages (kind 4: create/update/remove ops) | Couple's devices | "Remove" is an op in history, **not erasure** (D-119, E72) |
| Revocation | Signed by an active device | S device status `revoked` + signed evidence; MLS Remove; tokens and KeyPackages deleted | Server, account, partner devices (lineage) | Permanent |
| Unpairing | Purpose-8 proof (D-136) | S couple `dissolved`, conversations `closed`, partner records deleted | — | Irreversible; each phone keeps what it decrypted; server ciphertext retained, unreadable by clients |
| Identity reset | Request (session) → 7-day delay → complete | S `accountTrust` reset fields; all devices revoked; recovery key deleted; new identity epoch | Account; partner alerted (D-132) | Old records kept |
| Conversation recovery | Purpose-7 proof (D-135) | Old conversation `retired` (readable, never writable); new one created | Members | Old one retained |
| Push tokens | Signed registration (D-098) | S `pushTokens/*` (token ↔ device ↔ account); F FCM | Server, Google | Deleted by the device-status trigger on revocation and when stale (`fanout.ts`; triggers need deployment, Eventarc/Blaze); replaced on re-registration |
| Logs | Every callable/trigger | F Cloud Logging: event name + outcome category, counts; Google request logs (time, IP) | Project operators, Google | Cloud Logging default retention (not configured) |
| Crash reports | Staging/production builds | F Crashlytics: error **type** + stack only (no messages, no IDs, no custom keys) | Project operators | Crashlytics default retention |
| Analytics | — | **None** (ANALYTICS-POLICY) | — | — |
| Backups | — | Android OS backup and device transfer: **nothing** (D-123). Firestore: delete protection on, **no PITR, no scheduled backups** (production, Prompt 18 inspection) | — | — |
| Metadata | Every operation | S/F as METADATA-EXPOSURE | Server, Google | Not minimised or expired (P3-1) |

## 2. Server-side guarantees that do hold

- No plaintext private content reaches Firestore, Storage, Functions,
  logs, Crashlytics, analytics or push payloads (static guards and tests:
  TEST-MATRIX "Log leakage", "Notification leakage"; D-097 constant
  payloads).
- No server-side key: Functions hold no decryption key and no master key
  (PROMPT-17C-CLOSURE §8.5 greps; unchanged in Prompt 18).
- Closed conversations deny all client reads of contents and media
  (rules tests).

## 3. Documented limitations, classified

| # | Limitation | Classification | Evidence / reason |
| --- | --- | --- | --- |
| L1 | **EXIF (including location) reaches the partner's device inside the encryption** | **DEFERRED** (P2-9) | Stripping must happen before encryption without writing plaintext. Plaintext never crosses Dart: the core reads the picker's file. A correct strip therefore belongs in the Rust media sender (a JPEG/PNG/HEIC metadata filter on the plaintext stream), which widens the reviewed crypto core just before the review and changes the media path. Proposed design for after the review: a streaming segment filter (JPEG APP1–APP15/COM, PNG `eXIf`/`tEXt`/`zTXt`/`iTXt`/`tIME`, HEIC refused or re-encoded) with golden-file tests. The server never sees EXIF (it is encrypted). The UI must say location stays in the photo until then |
| L2 | **Server sees metadata: object sizes, timing, counts, sender device, relationship graph** | **ACCEPTED RISK** (P3-1, P3-2) | METADATA-EXPOSURE; message lengths hidden only to 256 B (D-126); media padding deferred (D-099) |
| L3 | **Photo-picker temporary plaintext copies** | **FIXED** (Prompt 18, D-141) for copies left by a killed process; residual: a copy exists between pick and the next start if the process dies, and no secure wipe | `picker_cache_sweeper_test.dart`; on-device `moments_test.dart`. App-private, excluded from backup (D-123); the original is in the gallery |
| L4 | **Removing a notebook item is not cryptographic erasure** | **ACCEPTED RISK** (by design, D-119, E72) | The "remove" op is itself a message; earlier ops stay in each device's history and on the server as ciphertext. The UI says so |
| L5 | **Server-side deletion and account deletion do not exist** | **BLOCKER** for public launch (P2-8; Google Play requires account deletion) | Order designed in AUTH-PRODUCTION-DECISION §8; needs a retention decision and Blaze to build and test |
| L6 | **Orphaned encrypted media can remain** (an upload whose message never sent; objects of closed conversations) | **DEFERRED** (P2-8) | Objects are ciphertext under keys only MLS members ever had; no reader after `closed` (rules). Clean-up needs a scheduled function (Blaze) and the retention decision |
| L7 | **Local rollback detection is not complete** | **DEFERRED** (P2-7, D-079) | Needs a server-anchored freshness design (a new trust input). Behaviour pinned by `documented_limit_a_restored_older_state_is_not_detected_until_refreshed`; precondition is control of the unlocked phone's private storage |
| L8 | **Revocation propagation has a window** | **DEFERRED** (P2-10) | Devices learn on the next sync; push wake-ups (D-097) narrow it but need deployment. MLS removal is immediate for new epochs once processed |
| L9 | **Server may withhold or delay messages** | **ACCEPTED RISK** (P3-3, E10) | Undetectable today; gap detection not designed |
| L10 | **Partner identity can remain stored locally after unpairing** | **ACCEPTED RISK** (P3-13) | The local D-128 anchor authorizes nothing server-side; re-pairing needs the full two-consent flow. Client clean-up belongs to the unpairing UI |
| L11 | Each phone keeps what it already decrypted after unpairing | **ACCEPTED RISK** (by design, D-136) | Cannot be recalled from another person's phone; stated plainly in product copy (prohibited claims, PROMPT-17C-CLOSURE §6) |
| L12 | Production Firestore has no PITR or scheduled backups | **DEFERRED** (launch gate P1-INF-4) | Backups of ciphertext are safe to enable but are a retention decision: they must expire with the deletion policy, or "deleted" data survives in backups |
| L13 | Logs and crash reports use provider default retention | **DEFERRED** (P2-8) | They hold no content; retention to be set with the policy |

## 4. What deletion will have to cover (input to P2-8)

Account records; device records (or their minimisation: platform and
revocation reason are not needed after revocation); push tokens; pairing
and couple records; conversation ciphertext and media objects of
dissolved couples; rate-limit and challenge records (challenges already
expire and are deleted by the scheduled `cleanup.ts`, which needs Cloud
Scheduler/Blaze); Auth user; Firestore backups and PITR windows;
Cloud Logging and Crashlytics retention. Each phone's sealed history is
deleted by uninstalling or removing the account slot (`removeSlot` deletes
the wrapped key first, which makes the sealed state unrecoverable).
