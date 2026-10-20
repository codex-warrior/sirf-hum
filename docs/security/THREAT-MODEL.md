# Threat Model

Status: **Foundation (Prompt 01); E2EE analysis added (Prompt 04); crypto-core threats added (Prompt 06); device identity added (Prompt 07, scenario table in [DEVICE-IDENTITY §9](DEVICE-IDENTITY.md#9-compromised-device-and-server-assumptions)); encrypted media and notifications added (Prompt 11, E35–E46, [E2EE-MEDIA-AND-NOTIFICATIONS](E2EE-MEDIA-AND-NOTIFICATIONS.md)); couple and pairing added (Prompt 12, E47–E60, [COUPLE-AND-PAIRING](COUPLE-AND-PAIRING.md)); moments (Prompt 15, E61–E68); Future and Us (Prompt 16, E69–E76, [FUTURE-AND-US-ARCHITECTURE](../architecture/FUTURE-AND-US-ARCHITECTURE.md)).** A living document. Each phase that adds
data, endpoints or devices must update it. Not every threat can be
eliminated; the goal is that each one is *explicit*.

## Sensitive assets

| Asset | Sensitivity | Notes |
| --- | --- | --- |
| Messages, letters, private memories | Critical | Core intimate content |
| Photos, videos, voice recordings | Critical | Includes thumbnails and captions |
| Cryptographic keys (identity, device, content) | Critical | Compromise exposes content |
| Account credentials / auth tokens | High | Account takeover |
| Device identities | High | Impersonation of a device |
| Relationship information (who is paired with whom) | High | Itself revealing; risk in hostile environments |
| Presence information (online, in a call, location-like signals) | High | Enables stalking/monitoring |
| Operational metadata (timestamps, sizes, frequency) | Medium | Can reveal patterns |

## Trust boundaries

```text
[Person] ⇄ [Device: app + OS keystore]  ══ TB1: device / network ══  [Firebase: Auth · Firestore · Storage · Functions]
                                                                         ║ TB3: Google infrastructure & operators
[Partner's device] ═══════ TB2: between partners ═══════                 ║
                                                                      [FCM / APNs / Web Push]  [LiveKit]  TB4: third parties
```

- **TB1 Device ↔ network/server:** everything past the device is untrusted for private content.
- **TB2 Partner ↔ partner:** partners are trusted with *shared* content they
  receive, not with each other's accounts, devices or private settings.
- **TB3 Operator:** Sirf Hum staff and Google infrastructure are untrusted for content.
- **TB4 Third parties:** push services, LiveKit, crash/analytics vendors see only what we send.

## Attack surfaces

Client app (all platforms) · web origin (XSS, extensions) · Firebase Auth
flows (sign-in, recovery) · Firestore/Storage via Security Rules · callable
and HTTP Cloud Functions · LiveKit token endpoint and rooms · push payloads ·
pairing/invite flow · device-linking flow · local storage, caches, OS backups ·
logs and crash reports · CI/CD and developer credentials · third-party SDKs.

## Threat actors

| # | Actor | Example attacks | Planned mitigations | Residual risk |
| --- | --- | --- | --- | --- |
| T1 | **Compromised server** (Functions code, config) | Read data, serve malicious keys | E2EE: server never has content keys; key changes signed by identity keys; partner verification | Server can withhold/delay data, observe metadata, attempt key substitution if users don't verify |
| T2 | **Compromised database** | Dump Firestore/Storage | Ciphertext only for private content; minimised metadata | Metadata and relationship graph exposed |
| T3 | **Malicious administrator** | Browse user data, alter rules | E2EE; least-privilege IAM; audit logs; rules in source control with tests | Admin can disrupt service, view metadata |
| T4 | **Compromised device** (malware, root) | Read decrypted content, steal keys | OS keystore, app lock (future), minimal plaintext caching | Largely unmitigable: an owned endpoint sees what the user sees |
| T5 | **Stolen device** | Open app, read history | Rely on OS lock; optional app lock; remote device revocation; keys in hardware keystore | Unlocked stolen phone exposes content until revoked |
| T6 | **Compromised account** (phished credentials, SIM swap) | Sign in on attacker device | New device requires approval from an existing device / identity key; partner notified of new device; strong auth options | If recovery bypasses device approval, attacker gains future content — recovery design is critical |
| T7 | **Revoked / old device** | Continue reading after removal | Server-side revocation in rules; key rotation on revocation; FCM token removal | Content already on that device remains readable |
| T8 | **Man-in-the-middle** | Intercept/alter traffic, substitute keys | TLS; E2EE with authenticated key exchange; key-change warnings; optional verification | Users who never verify trust the key directory on first use |
| T9 | **Malicious third party** (other users, bots) | Enumerate users, spam invites, abuse endpoints | Default-deny rules, App Check (wired Prompt 02; enforcement pending rollout), rate limits, invite codes that expire, no public profiles; no Auth provider enabled before the identity phase | Determined attackers with genuine devices |
| T10 | **Abusive partner** | Monitoring presence/location, coercing access, refusing to unpair, using shared history as leverage | No partner access to the other's account/devices; either person can unpair; presence controls; no hidden tracking; considered "safety" design per feature | Coercion with physical device access cannot be solved technically; content already shared can be retained |
| T11 | **Notification leakage** | Lock-screen previews, push-provider visibility | Content-free payloads; on-device decryption only if ever enabled; per-category preferences | Notification *timing* still visible to push providers and onlookers |
| T12 | **Cloud-storage compromise** | Download media blobs | Client-side encrypted media with per-file keys; opaque object paths | File sizes and counts visible |

**Environment confusion** (a test build or deploy touching production): separate projects, no default CLI project, runtime and Functions environment guards, gated deploys (docs/architecture/ENVIRONMENTS.md).

Additional cross-cutting threats: supply-chain compromise of dependencies
(pin versions, review new SDKs, CI secret scanning); developer credential
leakage (no secrets in repo, separate prod access); logging/crash-report
leakage (`AppLogger` enforces typed fields and redacts raw strings; Crashlytics receives error types only); OS cloud backups of local databases
(exclude or encrypt local stores).

## E2EE threat analysis (Prompt 04)

Against the recommended design in [E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md):
MLS couple group of devices, Person Identity Keys (PIK), web v1 without
private content. "Not implemented" applies to every mitigation below.

**What E2EE cannot protect against:**
- a compromised endpoint (malware, a malicious OS, a modified app) sees
  plaintext while the user reads it;
- a recipient can always copy what they can read;
- metadata (who, when, how often, how big, from where) remains visible to
  the server and Google;
- a malicious *code update* is a compromised endpoint.

| # | Threat | Security objective | Mitigations | Residual risk | Assumptions |
| --- | --- | --- | --- | --- | --- |
| E1 | Compromised Firebase project | Server can't read content or impersonate devices | MLS ciphertext only; PIK-signed device certificates validated by every device; partner verification; key-change warnings | Metadata exposure; denial of service; withholding/reordering messages; tricking unverified (TOFU) pairs at first contact | Users verify or heed key-change warnings |
| E2 | Database / Storage leak | Leak reveals no content | Ciphertext only; opaque IDs; padded sizes; no plaintext thumbnails | Relationship graph, timing, sizes | Crypto primitives sound |
| E3 | Malicious administrator | Same as E1 | Same as E1; least-privilege IAM; WIF deploys; audit logs | Same as E1; an admin could ship malicious **web** code (hence web v1 has no private content) | Mobile binaries are store-signed and not replaceable by an admin alone |
| E4 | Compromised Cloud Function | Function can't decrypt or add members | Functions never hold keys; membership changes require Commits signed by member devices with valid certificates | Can disrupt invites/fan-out; can leak metadata | — |
| E5 | Man-in-the-middle | No interception or key substitution | TLS; end-to-end authenticated MLS; out-of-band PIK verification | First-contact TOFU if users never verify | — |
| E6 | Stolen unlocked device | Limit exposure; enable remote cut-off | OS lock; optional app lock (auth-bound key); remote Remove from another device | Content readable until removal is synced; previously displayed content | Owner notices and revokes |
| E7 | Compromised user account (Firebase) | Account takeover ≠ content access | New devices need PIK certification (existing device or recovery key); partner sees key changes | Metadata access; social engineering of the partner | Recovery key kept secret |
| E8 | Malicious / compromised partner device | Limit to what that partner legitimately sees | Partner can only read shared content; can't add devices for you (needs your PIK); roster changes visible; instant unpair | Partner can copy shared content; a compromised partner device leaks shared content until revoked | — |
| E9 | Revoked / obsolete device | No future content | MLS Remove → new epoch (spike-verified online/offline); server denies; tokens/KeyPackages deleted; Updates for PCS | Already-decrypted content stays | Remove commit reaches the group |
| E10 | Replay, reorder, duplication | Accept each message once, authentically | MLS generation keys deleted after use (spike-verified replay rejection); `clientMessageId` dedupe; per-epoch commit ordering | Message *withholding* by the server is undetectable without extra mechanisms (gap detection **UNRESOLVED**). **Prompt 05 finding:** in both OpenMLS and mls-rs a *rejected* forged copy consumes the message key, so an injector (server or member) can make one genuine message undecryptable (DoS); mitigated by checkpoint + rollback on rejection (tested) | — |
| E11 | Push notification leakage | No content to push providers or lock screens | Data-only, content-free payloads; generic local text; previews off | Notification timing reveals activity | — |
| E12 | Metadata exposure | Minimize | Opaque IDs, padding, short retention, minimal AAD | Inherent: timing, sizes (bucketed), device counts, pairing | — |
| E13 | Account recovery abuse | Recovery can't be hijacked | No escrow; recovery key required; new-device notifications to all devices and the partner; re-auth | Stolen recovery key + account = takeover | User stores the key safely |
| E14 | Malicious application update | Detect/limit | Store signing; reproducible builds (future); minimal dependencies in the crypto core; protected CI/deploy | A malicious signed update is a compromised endpoint: E2EE can't stop it | Store accounts and signing keys protected (ACCOUNT-OWNERSHIP) |
| E15 | Compromised browser | — | Web v1: no private content | Account/settings session exposure | — |
| E16 | Malicious browser extension | — | Web v1: no private content | Same | — |
| E17 | XSS / browser storage compromise | — | Web v1: no private content; CSP/Trusted Types before any future web E2EE | Same | — |
| E18 | Loss of all trusted devices | Honest outcome | Recovery key (opt-in); otherwise new identity, visible to the partner | Without recovery, history is lost; this must be stated plainly | — |
| E20 | Malicious MLS input (server, network or member): oversized, malformed, forged, replayed, from outsiders | Reject without crashing, exhausting memory or damaging valid state | Size limits before parsing; OpenMLS validation; checkpoint/rollback on every rejection; panics caught at the ABI; boundary credential validation on every receiver (Prompt 06, tested) | Parser bugs in OpenMLS within the limits (three 2026 advisories fixed in 0.9.1; RustSec monitored by `cargo audit`) | OpenMLS 0.9.1 parsers behave within limits |
| E21 | Local crypto-state theft or tampering (backup extraction, file edit, record swap) | Files reveal nothing; tampering is detected | XChaCha20-Poly1305-sealed records with name/kind-bound AAD; fail closed on any mismatch; app-private directory | The store key comes from the platform key store (Android Keystore-wrapped / iOS `ThisDeviceOnly` Keychain, Prompt 07); a process-level attacker on a rooted/jailbroken device can still use it while the app runs | Platform keystore protects the store key at rest |
| E22 | Local rollback: an older copy of the whole state directory is restored | Old state can't be resurrected to reuse keys | None yet: no monotonic counter or hardware binding. Restored state cannot regain *server* trust (status server-side; IDs/keys indexed forever) | Open (D-079, MULTI-DEVICE-TRUST §10). An attacker with file access could restore an older epoch's state. The trust epoch (D-083) makes a device refuse an *older server view* than it has seen, but rolls back with the files. MLS removal still blocks reading new epochs (tested: restored pre-removal state cannot decrypt) | — |
| E24 | Password/account compromise used to add a device | Account access ≠ device trust | Proof of possession activates only an account's first device, once ever; later devices need an approval statement signed by an active device's PIK or the recovery key; comparison code on both screens; rate limits (Prompt 08, D-075) | The attacker can register pending devices (cap 3), request a delayed identity reset that any trusted device can cancel (D-082), and try to trick the owner into approving; the code comparison is the defence. A password alone can no longer revoke devices (D-081) | Owner compares codes; a trusted device cancels unwanted resets |
| E25 | Lost / stolen / compromised device keeps acting | Revocation is enforced server-side | A trusted device signs the revocation (D-081, verified against stored certificates, evidence kept); revoked devices cannot approve, revoke, cancel a reset, register recovery keys or use approvals signed before revocation (checked at submission); offline devices cannot create trust on reconnect | Content already on the device stays readable there; revocation does not wipe remotely; no cascade to devices it approved earlier (lineage recorded); **only device stolen and no recovery key:** nothing can sign its revocation and its holder could cancel an identity reset (D-081 residual) | Owner keeps a recovery key or a second device |
| E26 | Replayed, forwarded, stale or forged approvals and recovery statements | Each authorization counts once, for one device, one account, before it expires | Domain-separated statements binding account, both identities, single-use challenge, expiry and version; requests consumed on first use; shared failure budget (D-075–D-077) | Rate limits are per account, not global | — |
| E27 | Loss of the recovery key or of every trusted device | Honest outcome | Single-use recovery key (public half only on the server); recovery restores device trust, never history | Without devices or key: a delayed (7-day), cancellable identity reset to a NEW identity that partners must re-verify (D-082); history is never recoverable; reset notifications are not built yet | User keeps the key safe |
| E28 | Malicious server adds or hides devices in an account's device list | A device trusts only what signed evidence proves | Lineage verified on device in Rust from the partner-verified root (D-084); client fails closed if the server lists an active device the chain does not prove; server trust epoch refused if it goes backwards (D-083) | The server can withhold revocations or new links (omission) and controls ordering; the root's identity rests on partner verification (D-064) | Partner verifies the root PIK |
| E29 | Forged, replayed or cross-protocol revocation or reset-cancel statements | Each counts once, for one device, one account | Domain-separated v1 statements binding account, both certificates, reason, single-use challenge bound to the signer, expiry; golden vectors across TS/Rust/Dart (D-081, D-082) | — | — |
| E30 | Revoked device re-mints a trusted identity with its retained PIK | A revoked device gains nothing | Trust unit is the exact certificate; each PIK pinned to one device ID; revoking a device revokes its PIK permanently; lineage only from an anchored root (D-085, Prompt 10, tested) | The server controls the ordering of statements in a lineage (E28) | Partner verifies the root PIK |
| E31 | Server moves, relabels or rewrites a message (other conversation, message ID, sender device/account, epoch, version) | Detected on receipt | Routing fields in MLS AAD built by Rust and compared with the envelope inside the rollback transaction; MLS group ID = conversation ID; sender account checked against the verified lineage (D-089, tested) | The server can still drop or delay messages (E10) | — |
| E32 | Concurrent or forged commits fork the conversation | One agreed epoch sequence | Staged commits (D-087); create-only `commits/{epoch}` written with the epoch move (D-088); every device validates the winning commit and fails closed (`stateDiverged`) if it cannot | A winning but invalid commit stalls the conversation until re-provisioning (deferred) | — |
| E33 | Revoked device keeps receiving new messages | No new content after the sender learns of the revocation | Senders refuse to encrypt to a roster with an untrusted device; Remove commit; rules refuse its writes (Prompt 10) | Firebase reads are per account: until the Remove, a revoked device with its account's session can decrypt messages from devices that have not refreshed lineage yet. Since Prompt 11 a revocation sends a silent wake-up to the remaining devices (D-098), so once deployed (Blaze) the window shrinks from the next app resume to push latency | Peers refresh lineage on resume and on the sync wake-up |
| E34 | Plaintext at rest through message history | History unreadable off-device; no plaintext files | Sealed records (kind 5) under the slot's platform store key, atomic with MLS state, no plaintext fallback; name-bound AAD stops record swaps (D-090, tested) | Rooted device while the app runs (E21); restored old files not detected (E22) | — |
| E35 | Malicious storage access: dump or read Cloud Storage objects (operator, leaked credentials, rules bug) | Objects reveal no content | Objects are client-side STREAM/XChaCha20-Poly1305 ciphertext under per-object keys that never reach the server (D-093, D-094). Rules allow `get` to conversation members only, with no `list` and no public or anonymous access (D-095) | Object count, exact sizes, timing, uploading device | Tests: `media_storage.test.js` (outsider, anonymous and cross-conversation reads denied); `native/tests/media.rs` `no_plaintext_reaches_disk_through_send_or_open` |
| E36 | Malicious storage modification: overwrite, edit, truncate or extend an object | Detected before any plaintext is released | Create-only rules (no update or delete). Authenticated SHA-256 object digest in the signed `media_ref`, checked first. Per-chunk AEAD plus the STREAM last-block flag. Fail closed with no partial plaintext; the client purges its cache and downloads once more | Denial of service (object unusable) | Tests: `media.rs` (tamper, truncate, extend, swap); `media.rs` unit tests of the STREAM layer alone, hash bypassed; `media_service_test.dart` |
| E37 | Media ciphertext substitution: the server serves another object (same or other conversation) for a reference | Rejected | Authenticated object digest; the AAD binds conversation, media ID, sender device, class and length | DoS | Tests: `another_objects_ciphertext_is_never_accepted`, `objects_are_bound_to_their_conversation`, the service substitution test |
| E38 | Media key substitution or injection: the server or Dart supplies a different key, or forges a reference | Impossible for the server; Dart cannot forge one | Keys exist only inside MLS ciphertext (authenticated sender, D-089). Only Rust builds kind-2 payloads (`send_message` refuses them). Dart sees a key-free view (D-094) | A malicious *member* can send its own broken reference (DoS of its own message) | Tests: `dart_cannot_send_a_media_reference_itself`; view golden vectors (Rust and Dart); `media_native_test.dart` |
| E39 | Cross-conversation or cross-sender replay of media (an object re-referenced elsewhere, or the partner's media re-attributed) | Rejected | Conversation ID and sender device in the AAD, taken from the authenticated delivering message. MLS replay protection and history dedupe cover the reference itself | — | Tests: conversation binding; re-attribution (sender AAD) unit test; `a_replayed_media_message_is_a_duplicate_and_still_opens` |
| E40 | Notification plaintext leakage through FCM, the lock screen or logs | No private content reaches FCM or logs | Constant payloads (`{v, k}` plus generic text) with no IDs, topics or previews. Triggers read routing fields only and log counts only (D-097) | Notification timing is visible to Google and to onlookers; the app's name shows on the lock screen | Tests: `notification.test.mjs` (exact payloads, no identifiers, static log and read guard); emulator payload ID scan |
| E41 | A stale or revoked device keeps receiving wake-ups through an old token | No signals to non-active devices | Fan-out targets only devices `active` at send time. A move out of `active` deletes the token. Unregistered and stale tokens are deleted. Logout clears the token (signed) and deletes it at FCM (D-098) | A push already in flight at revocation is still delivered (content-free) | Tests: emulator `revocation deletes the token at once…`, `revoked, pending and stale devices are never targeted…`, identity reset |
| E42 | Token hijack: an attacker with the account password registers its own token for a victim device, or silences it | Only the device key can register its token | Single-use challenge bound to the token hash and signed with the device key (`push_token` purpose 3, domain-separated); server-only token store; one token per device | — | Tests: emulator `a password alone cannot register a token…`, `a challenge is bound to one token…`; Rust and TS purpose separation |
| E43 | Unauthorized media download (outsider, revoked or removed device) | No content without a key | Rules admit members only (account level). A non-active device refuses downloads itself. Keys come only through MLS, so a removed device gets no keys for new media | **Storage reads cannot see devices:** a revoked device holding its account's session can download *ciphertext* until it is removed from MLS. It keeps media it already received (no remote deletion) | Tests: rules read tests; `a_revoked_recipient_gets_no_key_for_media_sent_after_its_removal`; service revoked-device test |
| E44 | Compromised server attempting media decryption | Impossible without device keys | The server never holds media keys, MLS state or plaintext. Functions never receive media. No server-side thumbnails (D-099) | Metadata only | Tests: the invariants above; static guard that notification code never reads documents whole |
| E45 | Media metadata leakage (filenames, types, EXIF, sizes) | Minimise | Opaque paths, a constant content type and only `sd` metadata (rules enforce it); class inside the ciphertext; EXIF only inside the ciphertext | **Exact object sizes** (padding deferred, D-099); upload timing; the upload correlates with the following message; EXIF still reaches the *partner* until stripping exists | Test: `content type and metadata are fixed…` (rules) |
| E46 | Cached plaintext media exposed on the device | No plaintext at rest | Ciphertext-only cache in the backup-excluded slot. Plaintext only in memory: native copies wiped, the Dart copy wiped by the caller. Keys in sealed history under the platform store key. Removing the slot deletes the cache | Dart heap copies cannot be reliably wiped (GC); OS-level screenshots and exports; a rooted device while the app runs (E21) | Tests: `no_plaintext_reaches_disk_through_send_or_open` (Rust); the service test scans both slots |
| E47 | Stolen Firebase session or password used to pair, accept, confirm, reject or cancel (Prompt 12) | A session alone changes no pairing | Every step needs a single-use challenge signed by an **active** device's key under proof purpose `pairing` = 4, verified against the stored certificate in the step's transaction (D-102) | A thief who also holds an unlocked trusted device (E6) can pair it; the partner still verifies lineage on device | Tests: emulator `a password alone cannot pair`, `bound to one step…`; purpose matrix (Rust, TS, Dart) |
| E48 | An attacker pairs their own account with someone without consent (intercepted or forwarded link) | No couple without both people's explicit consent to each other | Two consents: the invitee accepts with the token, then the inviter confirms *that account* after comparing a 6-digit code; the inviter can reject; the claim binds the invitee's account and device (D-101) | An inviter who confirms without comparing the code can still pair the wrong person (UX must insist; unpairing deferred, D-105) | Tests: `rejects the account that accepted`, happy path (same code both sides) |
| E49 | Replayed invitation token or step challenge | Single use | The token hash is deleted on redemption or end; challenges are deleted by their first use and bound to step, subject, account and device | — | Tests: `a token redeems once…`, `a challenge is bound to…` |
| E50 | Expired or stale invitation, claim or lock | Nothing outlives its deadline; nothing stale blocks | Server-clock deadlines (24 h + 24 h, challenges 5 min), lazily recorded as `expired`; locks re-validated against their pairing | Ended records stay as audit evidence (retention deferred) | Tests: expiry, `a stale claim…` |
| E51 | Concurrent accepts, invitations, confirmations, or cross-accepts | Exactly one outcome, never two couples | One Firestore transaction per step over the pairing, both locks, both partner and trust records, and the bound devices; first commit wins (D-103) | — | Tests: four concurrency tests (emulator) |
| E52 | Pairing an account that is already paired | One couple per account (V1) | `accountPartners` checked in every step; confirmation invalidates if either side paired meanwhile | — | Tests: `a paired account cannot…` |
| E53 | A revoked (or otherwise inactive) device pairs or accepts, or a bound device is revoked mid-pairing | No pairing authority without an active device | Active status checked in the step's transaction; the inviter's creating and the invitee's accepting device are re-checked and the pairing `invalidated` if either is no longer active | — | Tests: revoked-device tests |
| E54 | Identity reset during pairing (a password thief starting a reset, or a completed reset with a new PIK) | Never couple a reset or resetting identity | A pending reset refuses steps; a changed `identityEpoch` or a pending reset on either side invalidates the pairing (D-102) | A reset requested *after* the confirmation commits leaves the couple; partners then see a new unverified identity (D-082) | Tests: reset tests, including the concurrent race |
| E55 | Direct Firestore writes: forged pairings, locks, couples, partner records or self-asserted membership | No client-controlled membership | Rules deny every client write to `pairings`, `pairingLocks`, `couples`, `accountPartners`; profiles cannot carry other fields | — | Tests: `couple.test.js` |
| E56 | Forged client inputs (UIDs, couple IDs, statuses, timestamps) | The server derives all authority | The account comes from the verified auth context; only `deviceId`, `challengeId`, `proof`, `token`/`pairingId` are read, pattern-checked; everything else is ignored | — | Tests: `client-supplied accounts, statuses, IDs and timestamps are ignored`, malformed inputs |
| E57 | Account, invitation or relationship enumeration | Learn nothing about other accounts | Uniform `invitation_invalid` / `pairing_not_found`; no lookup callable; no listing of `users`, `couples`, `pairings`; 128-bit tokens; redeem-failure and step rate limits; state reads return no IDs | Display names are revealed to the other participant after acceptance | Tests: enumeration tests, callable surface scan, rules listing tests |
| E58 | Client and server clock disagreement | Deadlines are the server's | Clients never send times; returned times are display-only; rules require `request.time` for profile timestamps | — | Tests: expiry with server `now`, forged `createdAt` |
| E59 | Pairing secrets in logs (tokens, codes, IDs) | No secret in logs | The pairing module has no logger; callable logs are `{outcome}` only (static guard); Dart logs step + category only | Platform request logs record that a callable ran | Tests: log guards (Functions, Dart) |
| E60 | Account deletion or disablement during pairing | No pairing by a disabled account | Every step needs an active device proof; a disabled account's ID token expires within 1 h | No deletion flow yet: it must end pairings and dissolve couples (D-105) | — |
| E61 | Moment from or into another couple (forged conversation or couple ID, wrong account) (Prompt 15) | A moment belongs to exactly one couple | No couple ID in a moment; the conversation comes from the server's pairing answer and is bound into the MLS AAD; rules admit members only (D-113) | — | Tests: `moments_isolation.test.js` (other couple, forged IDs, listing); service test (another conversation, another account's core) |
| E62 | Caption or memory date read by the server | Private content never server-readable | Inside the kind-3 MLS payload and the sealed history only (D-114) | That a moment-sized message exists | Tests: scans of server data, both slots and logs for the caption |
| E63 | A member re-attributes or re-claims the partner's photos in a manifest | Unreadable, never shown as theirs | Same-sender-device and single-claim rules over MLS-authenticated senders (D-114) | DoS of the forger's own moment | Tests: timeline unit tests; native forged-manifest test |
| E64 | Revoked or stale device adds or fetches moments | Nothing new | Active status before every write, fetch and download; lineage refresh blocks the timeline; senders refuse an untrusted roster; rules refuse writes (D-115) | Moments already on the device stay readable there (D-096) | Tests: service (revoked/pending/unknown, signed partner revocation); controller (blocked) |
| E65 | A moment reported saved that can never be delivered, reported failed while it will still be delivered, or a duplicate after retry | Truthful outcome, exactly once | Seal all parts first; discard on failure and on permanent refusal; a transient failure after sealing is `savedOnPhone`; retries reuse sealed messages; create-only objects and lost-ack recognition (D-115) | — | Tests: service (failed photo, removed account, registry offline before/after sealing, lost ack, offline, concurrency) |
| E66 | Partial moment: crash between sealing photos and the manifest | No moment appears half-made | Photos without a manifest are never shown as a moment | Those photos still upload as orphan media messages the partner's device can decrypt but no UI shows (the person had chosen to save them) | — |
| E67 | Decrypted photos linger (memory, image cache, temp files) after sign-out or lost trust | Plaintext in memory only, short-lived | Bytes wiped on dispose; decoded images evicted on session change and when blocked; picker copies deleted after encryption (D-115, D-117) | Dart heap copies and decoded pixels cannot be reliably wiped (GC); picker copies exist until the save ends | Tests: controller (wipe on block) |
| E68 | Location or camera metadata (EXIF) in shared photos | The server never sees it | EXIF only inside the ciphertext | **The partner's device receives it**; stripping deferred (D-117) | — |
| E69 | Future or Us record read or written by another couple (forged conversation or couple ID, wrong account) (Prompt 16) | A record belongs to exactly one couple | No couple ID in a record; conversation from the server's pairing answer, bound into the MLS AAD; member-only rules (D-118) | — | Tests: service (another conversation, another account's core, account outside the couple) |
| E70 | Titles, notes, story, rituals or dates read by the server or left in plaintext on a phone | Never server-readable; no plaintext at rest | Inside the kind-4 MLS payload and the sealed history only; no caches or files (D-119) | That a small message exists, its size and timing | Tests: scans of server data and both slots (native and on-device); logs |
| E71 | Revoked or stale device keeps changing the notebook | Nothing new leaves it | Active status before sealing and before upload; lineage refresh blocks the notebook; senders refuse an untrusted roster; rules refuse writes (D-121) | Records already on the device stay readable there (D-096) | Tests: service (revoked/pending/unknown, sealed-then-revoked, signed partner revocation); controller (blocked) |
| E72 | "Remove" mistaken for erasure | Removal is honest | UI says it disappears for both of you; docs and D-119 say it is not erasure | Earlier versions remain sealed in both phones' histories and as server ciphertext until a retention design | — |
| E73 | Concurrent edits silently lose one partner's change, or phones disagree | Both phones converge | Deterministic server order (time, then message ID); full-record replacement; terminal remove (D-119) | The earlier of two simultaneous edits is replaced without notice | Tests: assembly (order, ties, removal races); native (late edit after remove) |
| E74 | A partner floods the notebook (many edits) to exhaust the 10,000-record history bound or the outbox | Bounded impact | Live-record limits per section; outbox bound (100); MLS-authenticated authorship | Edits are unbounded and share the history bound with chat and Moments; compaction deferred | — |
| E75 | Notification reveals notebook activity | No content | Constant, content-free notifications (D-097) | Once deployed, each change wakes the partner's phone with the generic message notification (timing only) | — |
| E76 | A forged or contradictory change re-files a record (wrong section) or is shown as content | Fails closed | Strict decode; section fixed at create; wrong-section changes counted as unreadable and ignored | — | Tests: payload, assembly, native forged update |
| E23 | Secret leakage through logs, errors or the Dart boundary | No secrets outside the Rust core | No logging in the core (CI scan + clippy deny); OpenMLS debug features banned; error codes only; no export/dump function in the ABI; redacted Debug/toString; native buffers wiped | Decrypted plaintext in the Dart heap can't be reliably wiped (GC) | — |
| E19 | Abusive partner seeking access after unpairing | No access after unpairing | Unilateral instant unpair; partner leaves removed; rules cut access; new group on re-pair; roster changes visible while paired | Content already received by the abuser stays with them; coercion with physical access can't be solved technically | — |

**Prompt 11 numbering.** The Prompt 11 brief named its threats E30–E40,
but Prompt 10 had already used E30–E34. Existing IDs are never renumbered,
so the brief's threats map as follows:

| Brief | Threat | Here |
| --- | --- | --- |
| E30 | Malicious storage access | **E35** |
| E31 | Storage modification | **E36** |
| E32 | Ciphertext substitution | **E37** |
| E33 | Key substitution | **E38** |
| E34 | Cross-conversation replay | **E39** |
| E35 | Notification leakage | **E40** |
| E36 | Stale or revoked token | **E41** |
| E37 | Unauthorized download | **E43** |
| E38 | Server decryption | **E44** |
| E39 | Metadata leakage | **E45** |
| E40 | Cached plaintext | **E46** |

E42 (token hijack by someone holding the account password) was added by the
design review.

## Assumptions

- Device OS and hardware keystores are not compromised (outside T4).
- Established cryptographic libraries are correctly implemented.
- Firebase enforces Security Rules as documented.
- Users keep their device lock enabled (we encourage but cannot enforce).

## Unresolved risks (tracked)

1. Account recovery vs. E2EE trade-off. Designed in Prompt 04 (recovery key opt-in, no escrow; RECOVERY-AND-REVOCATION); offering a history archive is still undecided.
2. Web as a device class. Prompt 04 recommends no private content on web v1 (WEB-SECURITY); needs product approval.
3. Shared history after unpairing — product/legal decision pending.
4. Metadata minimisation — schema-level decisions pending.
5. Abuse/safety design for presence and location-like features — per-feature.
6. No independent security review has been performed.
7. MLS library: OpenMLS 0.9.1 selected (D-054, medium confidence). The SRLabs review covered an earlier commit and excluded providers; the delta review is pending. *(Prompt 04's "no audit found" was corrected in Prompt 05.)*
8. No post-quantum protection in standard MLS ciphersuites ("harvest now, decrypt later").
9. Server message *withholding* detection (gap detection) not designed.
10. The platform key store (Prompt 07, D-066) is unreviewed, and device activation is not deployed (needs Blaze, D-025). No real user's content until both are resolved and reviewed.
13. Device registration abuse: rate limits and a pending cap exist since Prompt 08 (D-077); deployment needs Blaze.
14. Multi-device trust, revocation and recovery (Prompts 08–09) are unreviewed. Identity reset (D-082) needs push notifications before production (the content-free wake-ups exist since Prompt 11 but are not deployed); local rollback protection is open (D-079, partly addressed by D-083); peers rely on the server for evidence completeness and ordering (D-084).
15. Encrypted media and notifications (Prompt 11: media format, AAD, ABI v6, Storage rules, push-token protocol, fan-out) are unreviewed and not deployed (Blaze). Exact media sizes are visible (padding deferred, E45).
16. Couple and pairing (Prompt 12: two-consent protocol, proof purpose 4, rules, locks) are unreviewed and not deployed (Blaze). Unpairing and account deletion do not exist yet (D-105).
17. Moments (Prompt 15: manifest format, timeline rules, composition with ABI v6) are unreviewed; there is no production backend (D-116), no deletion, and EXIF reaches the partner (E68).
18. Future and Us (Prompt 16: kind-4 notebook format, assembly rules, the shared conversation lock) are unreviewed; there is no production backend (D-121); removal is not erasure (E72); edits are bounded only by the shared history limit (E74).
11. Local whole-state rollback is undetected (E22).
12. The Prompt 06 crypto core (credential policy, record format, FFI, rollback) is unreviewed.
