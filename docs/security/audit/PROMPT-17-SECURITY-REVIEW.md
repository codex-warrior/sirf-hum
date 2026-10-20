# Prompt 17 — Security Review (internal)

Status: **Internal engineering review, 2026-10-20.** Baseline `main`
`d72aca3`. This is **not** an independent audit and does not make Sirf Hum
production E2EE. Classification of everything still open:
[PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md). Decision: D-125.

## 1. Method

1. Read the security and architecture documents and D-042–D-121.
2. Read the implementation rather than the documents: Firestore and
   Storage rules; every Cloud Function; the Rust core (`trust.rs`,
   `identity.rs` lineage, `engine.rs` processing/transactions,
   `engine/conversation.rs`, the media layer via the D-093 review); the
   Dart services (`MessagingService`, device trust/registration, pairing,
   push, Moments, notebook, session); Android Keystore adapter and
   manifest; CI/CD workflows; dependency locks.
3. For each property: documented → implemented → tested. Where the
   implementation diverged, write a failing test first when practical.
4. Close what can be closed without a new trust model, primitive or format;
   document the rest with an owner and a blocker class.

What was **not** done: no penetration test, no fuzzing campaign, no review
of OpenMLS or RustCrypto internals beyond what the core calls, no
on-device backup/restore experiment, no deployment.

## 2. Security-gap matrix

Columns: **Expl.** = exploitability; **Prod.** = blocks production (class
from PRODUCTION-BLOCKERS); **Ind.** = needs independent review.

| ID | Component | Threat | Expected property | Actual behaviour (before Prompt 17) | Expl. | Impact | Existing mitigation | Tests | Action | Prod. | Ind. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **P17-01** | Device trust: server activation + Rust lineage | A revoked device's retained PIK certifies a new device ID; a reset re-uses the old root PIK (E30, E78) | One PIK ↔ one device, ever (D-074, D-085) | Server indexed device IDs/keys only; the approver's guard knew only revocations it had seen; the chain verifier allowed one PIK on two devices. The static `verifyLineage` then listed the reborn device as proven while MLS trust skipped it, and devices it approved became lineage-trusted | Medium: needs the revoked PIK plus an approval from a device that has not refreshed lineage (or the password + old root PIK after a reset) | Revocation bypass at the server, inconsistent trust views, laundering of trust to descendants | Peers' `apply_lineage` skipped revoked PIKs; approver guard when informed | None for this path | **Fixed (D-122):** `personKeyIndex` on every activation; lineage rejects a PIK on two devices. 1 Rust + 4 emulator + 1 rules test, each shown to fail on the old code | Fixed | Yes |
| **P17-02** | Android app config | OS cloud backup / device-to-device transfer carries the Firebase Auth session and Firestore cache (E79) | No app data leaves the phone except through the app (D-066 intent) | `allowBackup` unset (default on), no extraction rules. Crypto slots were already excluded (`noBackupFilesDir`) and useless elsewhere | Low–Medium: anyone who restores the user's backup to another phone | A restored *session* (account access: metadata reads, identity-reset request, pairing reads); relationship metadata in backups. Never device trust or content keys | Keystore-wrapped store key, slots in `noBackupFilesDir` | None | **Fixed (D-123):** `allowBackup=false`, `fullBackupContent=false`, extraction rules exclude every domain (cloud + transfer) | Fixed (CI Android build verifies the merge) | No |
| **P17-03** | CI/CD | A moved tag or compromised action/tool runs in the credentialed deploy job or in the merge gates (E80) | Deploy credentials only reach reviewed code | All actions on mutable tags, `dtolnay/rust-toolchain@master` (a branch), `npm install -g firebase-tools` unpinned in Deploy and CI | Low (needs an upstream compromise) | Production deploy credentials (WIF), merge-gate integrity | WIF bound to repo + environment + `main`; least-privilege `permissions` | None | **Fixed (D-124):** SHA pins, exact `firebase-tools`, npm audit gate for Functions | Fixed | No |
| **P17-04** | Deploy workflow | Script injection through the free-text `confirm` input (E80) | Inputs are data, not code | `${{ inputs.confirm }}` spliced into a `run:` script | Low: needs dispatch rights (repo write) | Code execution in the production-bound job | Environment branch policy, single admin | None | **Fixed (D-124):** passed as env vars | Fixed | No |
| **P17-05** | Firestore/Storage authorization | A session of the account (left on a revoked or stolen device, or a password thief) writes as **another active device** of that account (E77) | "Rules refuse a revoked device's writes" (E33, E64, E71) | Rules see the account, not the device, and never parse MLS: a write naming any active device of the caller's account passes. MLS rejects such messages on receipt (envelope device ≠ authenticated sender; revoked credential refused), so they are noise. **Commits are worse:** whoever wins `commits/{epoch}` moves the server epoch. A commit written as another device fails the sender check (`EnvelopeMismatch`) on every receiver, and the device it names finds "its" commit not staged (`stateDiverged`), so **every device stalls** and nothing can be sent at the new server epoch. No device key is needed: random bytes suffice. Key packages of the account can also be overwritten or deleted | Medium–High: **any Firebase session of either account** (a password thief, a session left on a revoked or stolen phone, the partner) | Permanent denial of service of the couple's conversation (no recovery path exists, E32); pre-empts the Remove of a revoked device (prolongs E33 for devices that never refreshed). **No confidentiality break** | MLS AAD/sender binding (D-089), credential validation on every commit, first-commit-wins | New rules test "documented limit: rules authorize accounts, not devices"; new Dart (native) `a commit nobody can validate wins the epoch: every device fails closed, none resets or skips it`; Rust `every_envelope_field_is_cryptographically_bound`, `revoked_device_is_removed_and_cannot_rejoin_or_send` | **Open.** Design device-bound authorization for commits (Function-verified device proof, or a per-device custom claim minted after a device proof) and conversation recovery/re-provisioning (E32). Consider forcing re-authentication of the account's sessions on revocation. Until then a password compromise is a conversation kill switch | P1 | Yes |
| **P17-06** | MLS membership policy | A member device (a modified partner client) removes the other person's devices; they can only return by a Welcome from a member (E82) | Either person can leave; neither can lock the other out of shared history | Receivers apply any valid Remove by a trusted member; the app itself removes only untrusted devices | Medium for an abusive partner with a modified client | Availability/lockout (T10). Removal never grants access | Rules (account-level), MLS authentication | None | **Open.** A removal policy must not break legitimate removals by devices with stale trust (that would fork the group); design with unpairing (D-105) | P2 | Yes |
| **P17-07** | `rejectDeviceApproval` | A password alone moves the owner's pending devices to terminal `rejected` | "A password alone no longer changes device state" (D-081) | No device proof, no rate limit. Already listed as an *accepted* risk in MULTI-DEVICE-TRUST §13, but in tension with D-081's rationale | Medium (password only) | DoS of enrolment; no trust gain | Pending cap; the owner can register another device | Emulator `rejection is terminal for the device` | **Open, re-classified P2.** Require a proof from an active device or the pending device itself; add a limit (§13 annotated) | P2 | No |
| **P17-08** | Pairing confirmation | An intercepted invitation is accepted by a stranger and the inviter confirms without comparing (E48) | Both explicit consents, to each other | `getPairingState` hands the inviter the same code the claimant sees; `confirmPairing` takes no code, so confirming does not prove a comparison happened. The claimant chooses its display name | Medium (social: needs an inviter who confirms without checking) | Wrong couple at the server; content still needs PIK anchoring (P17-09) | Two consents, single-use token, reject path, uniform failures, rate limits | Emulator `the inviter rejects the account that accepted (e.g. an intercepted link)` | **Open (product decision).** Before any pairing UI: make the inviter enter the code the invitee reads out (server-checked, attempt-limited), and never anchor a PIK from pairing alone | P1 | Yes |
| **P17-09** | Partner / own-root PIK anchoring | Server substitutes a partner identity at first contact (E1, E5, T8) | Device trust rests on out-of-band PIK verification (D-064, D-085) | No production code calls `trustVerifiedPersonKey`: messaging cannot start in production (fails closed: no partner device is trusted). The risk is the future UX degrading to automatic trust-on-first-use of server data | — (fails closed today) | If built as silent TOFU: undetectable server MITM | Lineage from an anchored root only; no auto-anchor exists | Rust `trusted_partner_credentials_are_accepted`, `untrusted_person_key_is_rejected_when_adding` | **Open.** Build verification (safety numbers / QR) and own-account root anchoring for non-root devices; record any TOFU fallback as a decision with UI warnings | P1 | Yes |
| **P17-10** | App Check | Unattested clients call Functions; first deploy rejects every real client | Defence in depth, documented accurately | Every callable has `enforceAppCheck: true` **in code**, while ENVIRONMENTS said enforcement was off everywhere (true only for Firestore/Storage, console settings). No attestation provider is configured | — | Doc accuracy; deploy readiness (all callables would fail) | Auth + device proofs are the authorization | None | Docs corrected (ENVIRONMENTS, FIREBASE-ARCHITECTURE). Configure Play Integrity + debug tokens before deploying Functions | P1 (deploy prerequisite) | No |
| **P17-11** | Moments picker | Plaintext photo copies outlive a killed process (E81) | Picker copies deleted after encryption (D-117) | Deletion runs on composer dispose; process death leaves them in the app cache until the OS clears it | Low (device access) | Plaintext copy of a photo the person already has in their gallery | App-private cache, excluded from backup | Controller wipe tests | **Open.** Sweep the picker cache at start-up and on sign-out | P2 | No |
| **P17-12** | Web hosting | XSS / injected script on the web origin (E15–E17) | Web holds no private content (D-046); session protected | Headers set (nosniff, frame DENY, HSTS, referrer, permissions) but **no CSP** | Low today | Account session on web (profile/couple metadata, identity-reset request), not content | No private content on web (three layers, §13) | `private_content_crypto_test`, web build | **Open.** Add a CSP compatible with Flutter web before public web launch (needs a deployed-origin test) | P2 | No |
| **P17-13** | GitHub repository | Public code and history; settings (E83) | Visibility decided deliberately; free protections on | **Public.** Secret scanning, push protection and Dependabot alerts **disabled** (free for public repos). `main` unprotected and no rulesets, although public repos get them free; one admin collaborator | — | Exposure of unreviewed design and known limits (no secrets: gitleaks history scan clean, 80 commits); merge-gate integrity | CI gitleaks on full history; WIF + environment policy | CI `secrets-scan` | **Owner action, not automated:** enable secret scanning + push protection + Dependabot alerts now; add a ruleset on `main` (required checks, no force-push); decide visibility before production — making it private does not recall existing clones | P2 | No |
| **P17-14** | Rate limits | Cost abuse / small overshoot | Every security-sensitive callable limited (D-077, D-103) | All verifying callables share the failure budget; `listDeviceApprovalRequests`, `getPairingState` (reads) and `rejectDeviceApproval` have none; `requireBudget` is a non-transactional pre-check (bounded overshoot under concurrency; consumption is transactional) | Low | Cost/DoS only; App Check enforced on callables | Per-account limits, uniform `rate_limited` | Emulator rate-limit boundary and concurrency tests | Accept reads (P3); fix with P17-07 | P3 | No |
| **P17-15** | Rules-test harness deps | Vulnerable dev dependency | No known-vulnerable shipped code | `@grpc/grpc-js` 1.9.16 (5 high, server-side mTLS/error-message issues) via `firebase@13` in `firebase/` (tests only, local emulator) | None in product | None | Not shipped, not deployed | — | Accept; bump when the Firebase JS SDK moves | P3 | No |
| **P17-16** | Dependency scanning | Known-vulnerable Dart/Flutter/Gradle dependency ships unnoticed | Advisory gates for every shipped ecosystem | Rust: `cargo audit` (D-068). Functions: none before Prompt 17 (now D-124). Dart/Flutter/Gradle: none | Low | Unknown | Exact Rust pins, lockfiles | — | Add OSV-Scanner (or Dependabot alerts) for `pubspec.lock` and Gradle | P2 | No |
| **P17-17** | Local state (D-079) | Older copy of the whole state restored on the same phone (E22) | Documented precisely; no protection claimed | See §4.3: not detected; bounded by the next lineage refresh and MLS removal | Low: needs write access to app-private files with the Keystore usable (root / device compromise, T4) | Re-trusts a revoked device until refresh; resurrects "deleted for me" history; restores consumed MLS keys (forward-secrecy loss for that window) | Server trust is server-side; IDs/keys/PIKs indexed forever; MLS removal; OpenMLS `reuse_guard` | New Rust `documented_limit_a_restored_older_state_is_not_detected_until_refreshed`; existing restored-state tests | **Accepted residual for pre-production**; decide an external freshness anchor or explicit acceptance before public launch | P2 | Yes |
| **P17-18** | Retention / deletion | Removed or deleted content persists | Honest semantics (E72, D-116) | Server never deletes messages, commits, Welcomes or media (rules forbid it); "remove" and "delete for me" are not erasure; no account deletion flow (D-105) | — | Ciphertext retained indefinitely; metadata retained | Honest UI wording | — | Retention and account-deletion design (Play policy requires account deletion) | P2 | Yes |

| **P17-19** | MLS framing (Rust core) | Server reads the exact length of every message, caption and notebook record (E12, E62, E70) | "Padded sizes" (THREAT-MODEL E2, E12; E2EE-ARCHITECTURE §8) | OpenMLS `padding_size` never set (default 0): measured 219 vs 368 bytes for a 2- and a 150-byte payload | High (passive server/DB observer) | Content-length side channel (e.g. yes/no answers, caption length) | None | None | **Fixed (D-126):** 256-byte padding on create and join configs; RFC 9420 zero padding, no format change. Test fails without it. Lengths still leak to within a block | Fixed | Yes |

No finding shows a break of message, media or notebook **confidentiality**
against the server, a database dump, or another couple.

## 3. Critical / high findings

None of **critical** severity. One **high-for-production** item, which is a
missing component rather than a defect in shipped code:

- **P17-09** — partner PIK verification does not exist; messaging fails
  closed until it does. Building it as silent trust-on-first-use would make
  a compromised server undetectable at first contact.

The Medium items fixed in this prompt (P17-01, -02, -03, -19) and the open
Medium items (P17-05, -06, -08, -17) are in §2. P17-19 is the one case where
a documented security property (padded message sizes) was simply absent from
the implementation.

## 4. Area reviews

### 4.1 Trust / device identity chain (Part 2)

`Firebase account → device identity → PIK → certificate → signed activation
→ lineage → approval → revocation → identity reset → MLS credential`.

| # | Property | Verdict | Evidence |
| --- | --- | --- | --- |
| 1 | Firebase auth is never cryptographic trust | **Holds** | Activation needs proof of possession (bootstrap once) or a PIK-signed approval/recovery statement (`registration.ts`, `trust.ts`); MLS trust only from anchored lineage (`trust.rs`) |
| 2 | Device IDs not derived from personal identifiers | **Holds** | 16 random bytes in Rust (`OsRng`); account ID validated separately and never used as a key (D-071, D-100) |
| 3a | Revoked device cannot approve | **Holds** | Server: approver must be `active` at submission; Rust: approver in chain + revocations applied. Emulator `approval created before the approver was revoked, submitted after` |
| 3b | …register a replacement / certify a new device | **Held only partly → fixed** | P17-01 / D-122 |
| 3c | …regain trust with retained keys | **Holds** | Device ID, device key and now PIK indexed forever; status server-side; Rust revokes the PIK permanently |
| 3d | …keep sending | **Holds for confidentiality; DoS open** | Senders refuse untrusted rosters; receivers refuse revoked credentials; rules authorize per account (P17-05) |
| 4 | Old certificate under a new device ID | **Holds** | The certificate binds the device ID; server compares cert device ID with the record (`registerDevice`, `activateDevice`); Rust pins PIK→ID |
| 5 | Person + device + certificate + lineage bound | **Holds** | Every statement binds account, both certificates, challenge, expiry; device→account binding permanent in Rust |
| 6 | Signed approvals verified | **Holds** | Against the **stored** approver certificate; golden vectors across TS/Rust/Dart |
| 7 | Signed revocations verified | **Holds** | Same; challenge bound to the revoker |
| 8 | Trust epoch prevents server rollback | **Holds relative to what the device saw** | D-083; does not survive a local file rollback (§4.3) |
| 9 | Reset cannot be cancelled by an unauthorized device | **Holds** | Cancel needs an `active` device's PIK signature; a revoked device cannot. Residual D-081: a *stolen active* device can cancel |
| 10 | First device cannot race into two roots | **Holds** | One transaction over `accountTrust`; emulator `two first devices bootstrapping at once: only one becomes the root` |
| 11 | Recovery key single-use | **Holds** | Deleted in the activating transaction; emulator `two recovery attempts with one single-use key: one wins` |
| 12 | Recovery cannot silently restore the old identity | **Holds** | Recovery activates a **new** device (new PIK) and never history; reset opens a new identity epoch; old root PIK can no longer root it (D-122) |
| 13 | Trust state cannot move backwards | **Server: holds** (one-way transitions, terminal states, rules deny client writes). **Device: holds against stale server views, not against local file rollback** |
| 14 | Old/restored local state cannot regain server trust | **Holds** | Status is server-side; indexes forever; restored state is the same (revoked) device |

### 4.2 Remaining limits of the chain (documented, unchanged)

- The server controls ordering and completeness of lineage evidence
  (D-084): with a revoked device's PIK it can present a post-revocation
  approval as earlier (`documented_limit_peers_rely_on_server_ordering_for_revoked_approvers`).
- A stolen, unlocked, still-active device can approve, revoke and cancel a
  reset (D-081 residual).

### 4.3 Local rollback (D-079): exactly what happens

Precondition: an attacker can write the app's private files **and** the
phone's Keystore still unwraps the store key (same phone; root, malware with
app-level access, or a forensic tool on an unlocked phone). A copy moved to
another phone, or restored after reinstall, fails closed (`stateCorruption`
/ `key_missing`). Android backups never contained the slots and, since
D-123, contain nothing.

If an older copy of the slot directory is put back:

| Effect | Bounded by |
| --- | --- |
| Not detected: every record authenticates (same key) | — (no monotonic anchor exists) |
| Local trust forgets later revocations: a revoked device is trusted again, and the trust-epoch floors roll back, so older server views are accepted | The next `refreshTrust` with the server's current lineage re-learns the revocation permanently (tested). A **colluding server** can keep serving the old view |
| MLS state returns to an older epoch: the device re-processes the server's commits and messages from there | It cannot pass a commit that removed it (`restored_pre_removal_state_cannot_decrypt_new_epoch`) |
| Message keys already consumed reappear (messages of that window decrypt again) | Forward secrecy is lost only for that device's own past window; it gains nothing it was not entitled to read |
| Re-sending within a rolled-back epoch would re-use sender-ratchet generations | OpenMLS `reuse_guard` (32 random bits XORed into each nonce, RFC 9420 §6.3.1) makes nonce reuse improbable, not impossible; receivers have consumed those generations and reject the messages |
| "Delete for me" records and cached ciphertext come back | Not erasure (already documented) |
| Media: no effect on nonces (fresh key per object, D-093) | — |
| Server trust: none regained | Status, indexes and epochs are server-side |

Mitigations that would not invent a trust model were evaluated: an in-state
counter rolls back with the state; Android offers no general app monotonic
counter; key rotation per write would re-seal everything and still roll
back with the wrapped key file. A server-anchored state version (per-write
activity metadata plus an offline design) remains the only real option.
**Classification: accepted residual (P2), test added, no protection claimed.**

### 4.4 MLS / OpenMLS (Part 3)

| Topic | Verdict | Evidence |
| --- | --- | --- |
| Version | OpenMLS **0.9.1**, `openmls_rust_crypto` 0.6.0, `openmls_basic_credential` 0.6.0, `openmls_traits` 0.6.0; enforced by `tool/check_crypto_core.sh`; still the latest releases (2026-10-20) | `Cargo.lock`, CI |
| Wrapper boundary | Hand-written C ABI v6, opaque handle, Rust-owned wiped buffers, no key/state export, no logging (CI scan + clippy) | D-063, `ffi.rs`, `crypto_core_source_contains_no_logging_or_printing` |
| Credential validation | Basic credential → strict certificate decode → PIK signature → not revoked → exact certificate trusted → leaf key = certified key; on every Add, Update, update-path leaf, Welcome member and **every sender** | `trust.rs` `validate`, `engine.rs` `process_inner` |
| Member/device binding | Exact certificate is the trust unit; PIK pinned to one device; device→account permanent | D-085, D-122 |
| Revoked devices | Refused as senders, committers and add targets; senders refuse rosters containing them | `check_member`, trust tests |
| Commit staging / acceptance / rejection / rollback | Staged (D-087); confirm after the server's `commits/{e}` names us; discard otherwise; every untrusted input in a checkpoint, rollback on any error (D-056); poisoned core on rollback failure | messaging tests |
| Epochs | Window 0 (D-091); future epoch waits, stale fails closed; envelope epoch = MLS epoch | `future_epoch_waits_for_the_commit_and_stale_epoch_fails_closed` |
| First commit wins | Create-only `commits/{e}` written atomically with the epoch bump (rules check both halves) | rules + Rust `concurrent_commits_first_wins_and_the_loser_converges` |
| Replay / tamper / AAD / conversation / sender binding / moved ciphertext | Rust-built AAD compared inside the transaction; group ID = conversation ID; authenticated sender = envelope device; account = lineage account | `every_envelope_field_is_cryptographically_bound`, `ciphertext_copied_into_another_conversation_fails`, `tampered_ciphertext_fails_and_never_consumes_the_key`, `replay_is_rejected` |
| New / multi-device / removal | Trusted devices added with KeyPackages; removed devices cannot read new epochs | `a_new_trusted_device_joins_later_and_reads_only_from_then`, `four_device_conversation`, `removed_device_cannot_decrypt_new_epoch` |
| Proposals by reference, external joins | Refused (`Unsupported`) | `process_inner` |
| Padding | 256-byte blocks since D-126 (was 0) | `ciphertext_length_hides_the_message_length_within_a_block` |

Differences from upstream OpenMLS behaviour, and why: (1) credential
validation is ours (OpenMLS leaves it to the application, D-057);
(2) checkpoint/rollback around every input (upstream consumes a key on a
rejected forgery, D-056); (3) one atomic sealed record per operation
(SRLabs S1-3, D-058); (4) input limits before parsing (D-059);
(5) staged commits never advance the epoch until the server's verdict
(D-087); (6) sender-ratchet out-of-order tolerance 32 (default 5, D-091).
All six need the independent review (D-054 conditions). Open MLS-level
items: P17-05 (stall by a winning invalid commit), P17-06 (removal policy).

### 4.5 Media crypto (Part 4)

The D-093 review (2026-10-19, [D-093-SECURITY-REVIEW](../D-093-SECURITY-REVIEW.md))
covers key generation, lifetime, nonces, chunk sequencing, AAD schedule
(first chunk only, corrected in F4), truncation/reordering/duplication,
digest-before-decrypt, partial uploads, limits and plaintext lifetime.
Prompt 17 re-checked the code paths against it and found no drift.
**Verdict:** can remain as-is pending independent review; no design change
is required **before** the audit. F3 (format version inside `media_ref`) is
required before any format v2. `aead::stream` and the composition stay
**unaudited** (F8); tests passing is not evidence of production safety.

### 4.6 E2EE messages (Part 5)

The server cannot read private message content: payloads exist off-device
only as MLS PrivateMessage ciphertext; keys never leave the core; Dart
receives plaintext only as return values and never writes or logs it;
history is sealed (kind 5) under the slot's store key. What the server
**can** observe is listed in [METADATA-EXPOSURE](METADATA-EXPOSURE.md).
Offline queue, retry (same message ID re-encrypted after a stale refusal),
duplicate prevention (create-only IDs, history dedupe), stale epochs and
server ordering hold as designed (D-089–D-091). Server **withholding**
remains undetectable (E10). Account switching: the core re-checks the slot
account on every call (`AccountMismatch`); controllers drop late answers by
generation.

### 4.7 Moments, Future + Us (Part 6)

No plaintext reaches Firestore, Storage, Functions, logs, FCM, analytics or
Crashlytics: captions, dates, titles and notes exist only inside kind-3/4
MLS payloads and sealed history (scanned by the service tests); logs are
`snake_case` events with `SafeLogString` categories and counts; FCM payloads
are constant. Both features use the conversation-wide `exclusive` lock;
controllers drop results across session changes; web never runs them.
Residuals: EXIF reaches the partner (E68), picker copies after process
death (P17-11), removal is not erasure (E72, P17-18), notebook edits share
the 10,000-record history bound (E74).

### 4.8 Push / notifications (Part 7)

Verified in code: payload `{v:'1', k:'m'|'s'}` plus constant generic text,
no message/conversation/couple/device/account IDs, no topics; token
registration needs a device-key proof (purpose 3) bound to the token hash;
only `active` devices are targeted and a status change out of `active`
deletes the token; fan-out logs counts only. What FCM/Google still sees is in
[METADATA-EXPOSURE](METADATA-EXPOSURE.md).

### 4.9 Pairing / couple (Part 8)

Verified: 128-bit server token (`randomBytes(16)`), only its domain-separated
SHA-256 stored and deleted on redemption or end; single use; 24 h + 24 h
server-clock expiry; 6-digit code from `randomInt`; inviter must confirm the
specific claimant; claim binds invitee account + device; every step signed by
an `active` device (purpose 4) in the step's transaction; one transaction
over pairing, both locks, partners, trust records and devices; pending reset
or identity-epoch change invalidates; uniform `invitation_invalid` /
`pairing_not_found`; no lookup callable; rate limits; caller-state refusals
before token-dependent ones (the earlier enumeration regression: emulator
`an account in an open pairing learns nothing about tokens it presents (no
non-consuming probe)` — re-run green in this prompt). A stranger who
intercepts a link cannot pair **silently**: the inviter must confirm that
account. They can pair if the inviter confirms without checking (P17-08).

### 4.10 Rate limiting (Part 9)

| Callable | Limits |
| --- | --- |
| `registerDevice` | 5/h + 3 pending |
| `issueDeviceChallenge` | 10/h; failure budget |
| `activateDevice`, `proveDeviceEnrollment`, `approveDevice`, `registerRecoveryKey`, `cancelIdentityReset`, `registerPushToken`, `confirmPairing`, `rejectPairing`, `cancelPairing` | Failure budget (5 failed verifications/h, then every verifying call refused); challenges limited at issue |
| `requestDeviceApproval` | 5/h |
| `recoverDevice` | 3/24 h |
| `revokeDevice` | 10/h |
| `requestIdentityReset`, `completeIdentityReset` | 3 per 7 days (shared) |
| `requestPairingChallenge` | 30/h (+ redeem-failure budget for `accept`) |
| `createPairingInvitation` | 10/24 h |
| `acceptPairingInvitation` | 10 failed redemptions/h |
| `requestPushTokenChallenge` | 20/h |
| `listDeviceApprovalRequests`, `getPairingState` | **None** (reads; P17-14) |
| `rejectDeviceApproval` | **None** (P17-07) |

Nothing relies on client-side throttling alone. All callables enforce App
Check in code (P17-10). Limits are per account (no enumeration oracle) and
not global.

### 4.11 Logging / observability (Part 10)

Searched `lib/`, `packages/`, `functions/src`, Rust: no `print`,
`debugPrint`, `console.*` or stray `developer.log`; every Dart log goes
through `AppLogger` (raw strings redacted, errors reduced to type names);
`SafeLogString` wraps only enum names and fixed categories (every use
reviewed); `RedactedId` is unused. Crashlytics receives `RedactedError(type)`
and sanitized breadcrumbs; collection is disabled in the manifest until
configured. Functions log `{outcome}` categories and counts only (static
guards in tests). Rust has no logging (CI scan, clippy). `toString`/`Debug`
of private types are redacted. Platform request logs still record that a
callable ran (E59).

### 4.12 Local storage / backup (Part 11)

Store key: 32 random bytes per account slot, wrapped by a non-exportable
Keystore AES-256-GCM key (StrongBox when available), AAD-bound to the slot,
in `noBackupFilesDir`; removal deletes the wrapped key first
(crypto-erasure). Private keys are only inside sealed records. Account
slots are separate directories with separate keys; the core refuses another
account's slot. Uninstall deletes the Keystore key, so a reinstall is a new
device. Backup/transfer: fixed by D-123 (P17-02). Firebase Auth persistence
is account access only; it never activates or trusts a device. Dart heap
copies of plaintext and of the store key (platform codec) cannot be wiped
reliably (E23, E46, D-066 residual).

### 4.13 Web boundary (Part 12)

Three independent layers, verified: (1) compile-time import split — on web
`CryptoCore` is `core_unsupported.dart`, every call throws `unsupported`;
(2) `privateContentAvailableProvider` is `!kIsWeb`, checked by the Moments,
notebook, Together and pairing controllers before they start; (3) production
wires no messaging/Moments/notebook backend, and `main.dart` installs no
photo picker on web. No shared service, cached state or route can load
private history on web because there is nothing that can decrypt it there.
Gap: no CSP (P17-12).

### 4.14 Firebase / backend (Part 13)

Default deny (`match /{document=**} { allow read, write: if false; }`,
Storage likewise). Server-only: `pairings`, `pairingLocks`, `couples`
(members read), `accountPartners` (owner read), `pushTokens`,
`deviceChallenges`, `deviceApprovalRequests`, `deviceIdIndex`,
`deviceKeyIndex`, `personKeyIndex`, `rateLimits`, `accountTrust` and device
records (owner/partner read). No client-writable security collection was
found. Client writes: own profile (exact fields, `request.time`), key
packages, commits + epoch bump, Welcomes, messages, media objects — each
schema-checked and create-only where it matters. Callables derive the
account from the auth context, pattern-check every input, use server time
and run each state change in one transaction. Residual: account-level
authorization (P17-05).

### 4.15 Supply chain (Part 14)

| Item | Status |
| --- | --- |
| Rust | Direct deps `=`-pinned; OpenMLS pins enforced; `cargo audit --deny warnings` with 3 ignores, each re-verified on every run |
| RUSTSEC-2026-0330 / -0331 (`libcrux-kem` 0.0.9 panics) | **Not compiled**: `cargo tree --target all -e normal,build -i libcrux-kem` and `-i hpke-rs-libcrux` are empty (re-checked 2026-10-20). Fix needs `hpke-rs` 0.8; OpenMLS 0.9.1 / `openmls_rust_crypto` 0.6.0 are still the latest releases and pin the 0.7 line. Does not affect Sirf Hum; not a production blocker while uncompiled; must be removed with the next OpenMLS upgrade (D-068) |
| RUSTSEC-2026-0173 (`proc-macro-error2` unmaintained) | Compile-time only (proc-macro users only, re-verified); no fixed release; not shipped; P3 |
| Functions npm (production deps) | 0 advisories; now gated in CI (D-124) |
| Rules-test npm (dev only) | P17-15 |
| Dart / Flutter plugins / Gradle | No advisory gate (P17-16); exact versions in `pubspec.lock` |
| LiveKit | Not a dependency yet |

### 4.16 CI / release (Part 15)

`permissions: contents: read` everywhere except Deploy (`id-token: write`
for WIF). No service-account keys. Production deploy: environment branch
policy (`main`), typed confirmation, WIF conditions bound to repository,
environment and `main`; nothing deploys on push; `tool/deploy.sh` refuses
bare deploys. GitHub Free limits (no required reviewers on private repos)
are documented in D-038; **the repository is public, so rulesets/branch
protection are available now** (P17-13). Fixed: P17-03, P17-04. No build
provenance/attestation yet (P2 with release work).

### 4.17 Repository (Part 16)

Public (`codex-warrior/sirf-hum`, verified 2026-10-20). History scan:
gitleaks 8.30.1, 80 commits, no leaks (also CI on every push). Committed
config is non-secret (`config/env/*.example.json`, `functions/.env.*`
holding only `SH_ENV`). Exposed: the full design, threat model, known
limitations and unreviewed state — an attacker's map, but no secrets
(Kerckhoffs). Making it private later does **not** recall clones or forks.
Owner actions in P17-13.

## 5. Changes made in Prompt 17

| Change | Files |
| --- | --- |
| D-122 person-key uniqueness | `functions/src/device/{common,registration,trust}.ts`; `packages/sirf_hum_crypto/native/src/identity.rs` |
| D-123 Android backup | `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml` |
| D-124 CI/CD | `.github/workflows/{ci,deploy,prototypes}.yml` |
| D-126 MLS padding | `packages/sirf_hum_crypto/native/src/engine.rs` |
| Tests | `native/src/engine/trust_tests.rs` (+2), `native/tests/messaging.rs` (+1), `functions/test/emulator/hardening.test.mjs` (+4), `firebase/tests/messaging.test.js` (+1), `firebase/tests/devices.test.js` (index list), `test/security/messaging/messaging_service_test.dart` (+1, native) |
| Rules comment | `firebase/firestore.rules` (comment only: account-level authorization, new index) |
| Docs | this package; THREAT-MODEL; DECISION-LOG (D-122–D-125); MULTI-DEVICE-TRUST; DEVICE-IDENTITY; FIREBASE-ARCHITECTURE; ENVIRONMENTS; E2EE-TEST-PLAN; MASTER-BLUEPRINT; ROADMAP; CLAUDE.md |
