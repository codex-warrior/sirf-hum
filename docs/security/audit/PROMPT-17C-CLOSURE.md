# Prompt 17C — Final Security Engineering Closure

Status: **2026-10-21.** This document follows
[PROMPT-17-SECURITY-REVIEW](PROMPT-17-SECURITY-REVIEW.md) and
[PROMPT-17B-REMEDIATION](PROMPT-17B-REMEDIATION.md). It records the last two
P1 engineering items (conversation recovery and unpairing), classifies every
remaining item, and states what must **not** be claimed.

> **SIRF HUM IS NOT YET PRODUCTION E2EE.**
>
> **INDEPENDENT SECURITY/CRYPTOGRAPHIC REVIEW IS STILL REQUIRED.**

Nothing is deployed. No real user's content exists. Every security property
below is implemented and tested **in development** and reviewed **only
internally**.

## 1. Conversation recovery (D-135)

**Problem (E32, P1-3b).** Since D-127, only an active device's key can move
an epoch. A *trusted* device (bug, modified client, compromised phone) can
still win `commits/{e}` with a commit nobody can process; every device fails
closed (`stateDiverged`) and the conversation stalls. MLS has no undo and
the server never parses MLS.

**Design.** Retire and re-provision: the stalled conversation becomes
`retired` (readable, never writable), a **new conversation = new MLS group
ID** is created for the same couple (`generation` + 1, `predecessorId`), and
both partner records point at it. The devices build the new group exactly
as for a new couple, from verified lineage only (D-085).

```text
 device (active)                         Functions (one transaction)                 Firestore
 ───────────────                         ───────────────────────────                 ─────────
 requestRecoveryChallenge(conv, epoch, trustEpoch) ─► checks member, device active,
                                                       epoch + trust epoch unchanged ─► deviceChallenges/{id}
 sign purpose 7 over SHA-256("SirfHum-ConversationRecovery-v1" | 1 | nonce
      | account | device | conversation | epoch | trust epoch)  (inside Rust)
 recoverConversation(…, proof) ──────────────► consume challenge; device ACTIVE now;
                                                trust epoch, epoch unchanged; conversation
                                                active and current for both partners;
                                                couple active; proof valid
                                                ─► old: retired + successorId
                                                ─► new: epoch 0, predecessorId
                                                ─► accountPartners → new
 MessagingService.successor(): follow only if predecessorId == old and members equal
 new MessagingService(new id): refreshTrust → publishKeyPackage → sync (create/join)
```

| Question | Answer |
| --- | --- |
| Who may recover | One **active** device of either member account, with its device key. Never a session/password alone, a revoked/pending/unknown device, or another account |
| Bound to | Account, device, conversation, stalled epoch, account trust epoch, single-use 5-minute nonce |
| Old history | Untouched on every phone and on the server (ciphertext, retired, read-only for the members) |
| Pending messages | Stay queued in the old conversation; **never** re-sent automatically |
| Offline devices | Find `retired` and the successor on reconnect; old state untouched |
| Replay | Challenge single-use; retired conversation never qualifies again; old commits cannot enter the new group (different group ID; Rust test) |
| Racing commit / trust change / second recovery | One transaction; any moved state → `conversation_changed`, nothing changes |
| Server redirect | Client follows a successor only if it names this conversation as predecessor with the same members (E88) |
| Abuse | A trusted device can retire the conversation (denial of service it could already cause by stalling); 3 per 24 h; exit by unpairing |

## 2. Secure unpairing (D-136, supersedes D-134)

| Design question | Answer |
| --- | --- |
| Who can unpair | **Either partner, unilaterally**: an abusive partner must not be able to hold someone in the relationship (T10) |
| What authorizes it | A device proof (purpose `unpair` = 8) by one of the caller's **active** devices over `SHA-256("SirfHum-Unpair-v1" | 1 | nonce | account | device | couple id)`. **A password or Firebase session alone cannot unpair**; no takeover path is added (the leaving device gains nothing over the other account) |
| What happens | One transaction: couple → `dissolved`; every conversation of the couple (active or retired) → `closed`; both `accountPartners` records deleted |
| Removed partner's devices | Stay trusted on their **own** account; lose all access to the couple: closed contents and media are unreadable (rules), commit/recovery/approval paths refuse |
| Shared history | Each phone keeps what it already decrypted (cannot be recalled; stated plainly). Server ciphertext stays, unreadable by clients, until a retention decision (P2-8) |
| Future messages | None: closed conversations accept no writes |
| Moments, Future + Us | Live in the conversation: same as history |
| Pending invitations | Cannot exist while paired; afterwards either account may invite anyone |
| Recovery keys / devices | Unaffected (account-level) |
| Reinstall | A new device of the same account; no couple |
| Re-pairing | Only via the full flow: new invitation, the other's acceptance, the confirmation code (D-101, D-131); a **new** couple, conversation and MLS group. The old couple never returns |
| Reversible | No |
| Notifications | Silent, content-free sync wake-ups to both accounts' active devices; no visible alert |
| Concurrency | Conversations re-read in the transaction, completed through the current conversation's `predecessorId` chain; racing recovery forces a retry (E90) |

## 3. Classification (Part 5)

| Item | Classification | Evidence |
| --- | --- | --- |
| P17-05 device-bound commits | **FIXED** (17B) | D-127; F/S/D tests |
| P17-07 partner verification, no silent TOFU | **FIXED** (17B) | D-128 |
| P17-08 forced pairing-code entry | **FIXED** (17B) | D-131 |
| P17-09 identity-reset alerts | **FIXED** (17B; delivery needs deployment) | D-132 |
| Dependency scanning (Dart, Rust, npm) | **FIXED** (17B; Gradle P2-6) | D-133, `tool/crypto_audit.sh` |
| Conversation recovery (P1-3b, E32) | **FIXED IN 17C** | D-135; §5 |
| Unpairing (P1-5, E19) | **FIXED IN 17C** | D-136; §5 |
| Blaze / Functions / Storage / Eventarc / Scheduler deployment (P1-6) | **DEFERRED TO PROMPT 18** | Not allowed in 17C |
| Sign-in provider (P1-7) | **DEFERRED TO PROMPT 18** | Not allowed in 17C |
| Production App Check (P1-8) | **DEFERRED TO PROMPT 18** | Configuration in 17B §4 |
| Production configuration | **DEFERRED TO PROMPT 18** | ENVIRONMENTS |
| OpenMLS 0.9.1 vs audited `a3402f2`, provider | **REQUIRES EXTERNAL REVIEW** | P0-2 |
| The six deviations from upstream; D-126 padding | **REQUIRES EXTERNAL REVIEW** | Review §4.4 |
| Rust core, C ABI v6, Dart FFI | **REQUIRES EXTERNAL REVIEW** | P0-3 |
| Device trust (purposes 1–8, approvals, recovery, revocation, reset) | **REQUIRES EXTERNAL REVIEW** | DEVICE-IDENTITY, MULTI-DEVICE-TRUST |
| D-127, D-128, D-131, D-135, D-136 | **REQUIRES EXTERNAL REVIEW** | Decision Log |
| STREAM media construction (D-093) | **REQUIRES EXTERNAL REVIEW** | P0-4 |
| Full E2EE architecture | **REQUIRES EXTERNAL REVIEW** | P0-1 |

## 4. Accepted P2 deferrals (Part 6)

Not reopened: picker cache sweep (P2-3), Web CSP (P2-4), Gradle scanning
(P2-6), local rollback (P2-7), account/server deletion (P2-8), EXIF (P2-9).

**Partner lockout (P2-1, E82):** not reopened; its status changed because of
17C, not because of a new issue. A locked-out person can now recover into a
new group built from verified lineage (D-135) or leave (D-136). A hostile
trusted partner device can still remove the other's devices and repeat it,
so P2-1 stays open as P2.

**New issue found while building unpairing (fixed, not a deferral):** the
first unpair implementation queried the couple's conversations inside the
transaction; under concurrent load the Firestore emulator aborted such
transactions with `INVALID_ARGUMENT` instead of retrying. The query moved
outside the transaction with completeness re-established by point reads and
the predecessor chain (D-136 "Concurrency", E90). A pre-existing pairing
concurrency test showed the same emulator behaviour; the investigation is
in §8.3 and §8.4.

## 5. Tests added in Prompt 17C

| Layer | Tests |
| --- | --- |
| R | `recovery_reprovisions_a_new_group_old_history_stays_and_old_commit_cannot_replay`; purposes 7 and 8 valid, 9+ invalid (`device_identity.rs`) |
| F (`recovery.test.mjs`, 9) | valid recovery (new conversation takes a device-bound commit; old refuses commit challenges); password-only, forged, modified, wrong-purpose, missing proof, rate limit; wrong / revoked / pending / unknown device, revoked after its challenge; wrong conversation, wrong account, account switch; stale view, racing commit, racing trust change; replay, retired never recovered again, expiry; both partners at once (one wins); dissolved couple cannot recover; no plaintext / logger in `recovery.ts` |
| F (`unpair.test.mjs`, 13) | valid unpair (closes retired predecessors, devices stay trusted); password-only, forged, modified, wrong purpose, missing proof; revoked, pending, unknown, partner's device, revoked after challenge; wrong account, wrong couple, account switch, replay, stale request; concurrent unpair; racing recovery (once, plus 4 alternating rounds); E90: successor missed by the listing, missing middle link, walk bound fails closed; racing pairing; racing device approval; removed partner cannot send, approve, or re-pair without fresh consent; new couple and conversation after re-pairing |
| Fu (`lifecycle.test.mjs`, 4) | golden vector regeneration; every bound field changes each challenge; contexts never collide; malformed fields refused |
| S | closed conversation: no reads of contents/media, no writes; retired: readable, not writable (Firestore and Storage) |
| D | `lifecycle_authorization_test.dart` (TS vectors); `device_registration_test.dart` drift guard covers `conversation_changed`, `couple_unavailable`; pairing service: unpair proof is purpose 8 over the couple-bound challenge, another account or malformed ID never reaches the server, `coupleUnavailable` surfaces; messaging service (native, CI): recovery end to end with new group, old conversation read-only, outbox not re-sent, ciphertext only; device-bound (other key, other purpose, revoked, account switch); state-bound (trust epoch, epoch, replay); successor redirection refused |

## 6. Prohibited security claims

Until P0 and P1 in [PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md) are closed,
**no** store listing, website, app copy, investor, press or support material
may say or imply:

- "end-to-end encrypted", "E2EE", "encrypted end to end", "zero-knowledge",
  or "we can't read your messages" as a **production** property;
- "audited", "independently reviewed", "security-certified", "penetration
  tested", or "military-grade";
- "nobody, not even Sirf Hum/Google, can see who you talk to or when"
  (metadata is visible: METADATA-EXPOSURE);
- "messages and photos disappear / are deleted for both" after unpairing
  (each phone keeps what it decrypted; server ciphertext is retained);
- "unpairing is instant everywhere" (devices learn on the next sync; push
  wake-ups need deployment);
- "your partner can never lock you out" (P2-1);
- "post-quantum secure";
- "recovery restores your conversation" (it creates a **new** one; old
  history stays read-only, queued messages are not re-sent);
- anything about web clients holding private content (they do not, D-046).

Permitted, accurate wording for development material: "designed for
end-to-end encryption with MLS; not yet independently reviewed; not in
production".

## 7. External review still required

Everything in [PROMPT-17B-REMEDIATION §6](PROMPT-17B-REMEDIATION.md#6-external-review-still-required),
plus, new in 17C: device-proof purposes 7 and 8; the recovery state
transition and its races (D-135); successor following on the client; the
unpairing transaction, its lineage completeness argument and the
abusive-partner model (D-136).

## 8. Final verification (Prompt 17C-final)

### 8.1 Recovery (D-135) review

| Requirement | Result | Where |
| --- | --- | --- |
| Proof of possession | Ed25519 device proof (D-070 format, purpose 7) verified against the stored certificate; certificate's device ID must equal the caller's | `functions/src/conversation/recovery.ts` `recoverConversation` |
| Device binding | Challenge doc and derived hash bind the device ID; device must be `active` at commit time | same; F `wrong, revoked, pending and unknown devices…` |
| Conversation and exact epoch binding | Challenge and hash bind conversation, stalled epoch and account trust epoch; the transaction re-checks all three | F `a stale view (epoch or trust epoch) is refused…` |
| Commit / Welcome binding | Recovery carries no commit or Welcome. The successor's first commit and Welcomes go through `submitMlsCommit` with the D-127 binding (commit and Welcome hashes) | F `a trusted device recovers: … it works` |
| Stale, replayed, forged proofs | Refused (single-use challenge consumed whatever the outcome; modified, other-key, other-purpose proofs fail) | F replay, password-only/forged tests; D native |
| Revoked / pending / unknown device | Refused, including revocation after the challenge | F |
| Concurrent recovery | One transaction; exactly one successor; the loser gets `conversation_changed` | F `both partners recovering at once…` |
| No server plaintext, no MLS bypass | The server never reads messages (static guard); clients build the new group through the normal MLS paths from verified lineage | F static guard; R recovery test |
| No password/session-only path | Every path needs the device key | F |

### 8.2 Unpairing (D-136) review

| Requirement | Result |
| --- | --- |
| Both partners cannot corrupt the state | One transaction; concurrent unpair: exactly one succeeds, the other `couple_unavailable` (F) |
| Device-bound | Purpose 8 proof over the couple-bound challenge; session/password, revoked, pending, unknown, partner's devices refused (F, D) |
| Partner device trust | Device trust is per account and untouched; the removed partner loses couple access (rules, partner records, commit and recovery paths) |
| All conversations, including recovery-created | Yes: listing + partner pointers + `predecessorId` walk, each read in the transaction (E90 tests, mutation-checked) |
| Concurrent unpair deterministic | Yes (F) |
| Collection query inside the transaction | **None remains**: the listing is a plain read before the transaction; completeness comes from point reads in it |
| Partial state | Impossible: all writes in one transaction; beyond the walk bound it fails closed with nothing written |
| Removed partner's trusted operations | Commit challenge, recovery, device approval for the other account, sending: refused (F); closed contents and media unreadable (S) |
| Encrypted history | As D-136 (which superseded the open D-134): each phone keeps what it decrypted; server ciphertext retained, unreadable by clients |
| Plaintext | None on the server; the unpair module reads no message data |

Residual noted in review: a device keeps its local partner-root anchor (D-128) after unpairing. It authorizes nothing server-side, and re-pairing still needs the full two-consent flow; clearing it is client cleanup for the UI phase (P3-13).

`provisionConversation` (server-internal, never a callable) writes partner records without `coupleId`; only `confirmPairing` creates couples in practice. Unpair deletes only partner records naming the couple, so a record without `coupleId` would survive. That record is unreachable through any callable today. Kept as a note for the external review.

### 8.3 D-136 / E90 transaction change

The first implementation ran `where('coupleId', '==', …)` **inside** the
unpair transaction. Under the parallel emulator suite, the concurrent-unpair
test failed with `3 INVALID_ARGUMENT: Transaction is invalid or closed`.

Evidence (Windows, firebase-tools emulator, parallel `node --test`, a fresh
emulator per run):

| Runs | Code | Outcome |
| --- | --- | --- |
| 3 full runs before the fix (17C) | query inside the transaction | concurrent-unpair test failed 3/3 with `INVALID_ARGUMENT`; passed alone |
| 2 full runs, reinstated old design (17C-final) | query inside the transaction | concurrent unpair failed 1/2; a rate-limit concurrency test failed in the same run; the E90 walk-bound test fails by construction (the old design has no walk) |
| 3 + 2 full runs after the fix, plus CI | listing outside, point reads inside | concurrent unpair passed 5/5 + CI; 1 of 5 local runs failed a *different* test (pairing transactions in the removed-partner test) with the same `INVALID_ARGUMENT` |
| 1 isolated run of the unpair file after the fix | current | 13/13 |

Conclusion:
- **Not a product correctness defect.** Every failure was the emulator rejecting a contended transaction at commit (`Transaction is invalid or closed`). The transaction is then not applied (atomic: no partial state), and no assertion about security state failed.
- **The in-transaction collection query made it much more likely**, nearly deterministic for the concurrent-unpair test under parallel load, because it locks the whole `conversations` range that the other suites write to. That design was changed (it would also add contention in production). The change is justified on its own merits and its correctness is tested directly (E90).
- **A residual environmental flake remains** for any heavily contended transaction under the parallel emulator suite (pairing, rate limits): 1 failure in 5 local full runs after the fix, 0 in CI so far. It is an emulator limitation, not reproduced in isolation. Production Firestore returns `ABORTED` for contention, which the Admin SDK retries. That claim is from the documented SDK behaviour; it has **not** been tested here, because nothing is deployed. No test was weakened, skipped or re-ordered.

The change keeps authorization identical: the same checks and proof, in the
same transaction. Atomicity is unchanged: all writes in one transaction.
Completeness is argued in D-136 and tested directly, not only by races.

### 8.4 Pairing concurrency test

The pre-existing test `concurrent confirmations produce one couple; confirm
racing a withdrawal stays consistent` failed with the same emulator error
4 times while the in-transaction unpair query existed: 2 full-suite runs
and 2 isolated runs of `pairing.test.mjs`. The isolated runs contain no
unpair test; their cause is **not established** (possibly an emulator
from an earlier run still holding the port, before every run began by
stopping it). Afterwards: 4/4 isolated passes after a restart, and 6/6
full-suite passes since the fix (5 local + CI).

Classification: **emulator transaction limitation under contention**,
likely amplified in the full suite by the old unpair query (it locked the
`conversations` range that `confirmPairing` writes), plus environmental
flakiness (§8.3; the isolated failures are unexplained).
It is not a deterministic product defect: the failing transaction is never
applied, and the test's invariants (one couple; consistent cancel/confirm)
held in every run that completed. The test is unchanged. The concurrency
property it covers stays as tested, and nothing is marked resolved because
of a pass.

### 8.5 Prompt 05–16 regression

The full suites run in CI on every commit, unchanged and none skipped
(`nativeSkip` only skips native tests on hosts without the core; CI
requires the core): Flutter, crypto Dart package, Rust core, Functions unit
and emulator, Firestore and Storage rules, Android emulator integration,
prototypes. Greps on the branch: the server has no decryption, no key
material and no master key (only hashing, randomness, constant-time compare
and Ed25519 verification); no custom primitives (purposes 7/8 reuse D-070
proofs and SHA-256 derivations); the Firebase UID is bound into proofs as
the account but is never a cryptographic identity (keys are device keys and
PIKs); no web private-content path; no iOS changes.

### 8.6 Final item matrix

| ID | Severity | Status | Evidence | Remaining risk |
| --- | --- | --- | --- | --- |
| D-122 PIK uniqueness (P17-01) | High | Fixed (17) | R, F tests | Review P0-1 |
| D-123 no Android backup (P17-02) | Medium | Fixed (17) | Manifest, tests | No on-device backup test |
| D-124 CI pinning (P17-03/04) | Medium | Fixed (17) | Workflows | Build provenance P2-11 |
| D-125 audit package | — | Done | This package | Internal only |
| D-126 MLS padding (P17-19) | Low | Fixed (17) | R test | Review (deviation) |
| D-127 device-bound commits (P17-05) | High | Fixed (17B) | F, S, D | Trusted device can stall → D-135 |
| D-128 partner verification (P17-09) | High | Fixed (17B) | D native | Review |
| D-129 signed rejection (P17-07) | Medium | Fixed (17B) | F | — |
| D-130 QR libraries | Low | Done | OSV scan | Dependency trust |
| D-131 forced code entry (P17-08) | Medium | Fixed (17B) | F, D | — |
| D-132 reset alerts | Medium | Built (17B) | F | Needs deployment (P1-6) |
| D-133 dependency scanning, repo controls | Medium | Fixed (17B) | CI | Gradle P2-6; repo public P2-5 |
| D-134 unpairing (open decision) | — | Superseded by D-136 | — | — |
| D-135 conversation recovery (P1-3b, E32) | P1 | Fixed (17C) | R, F, S, D | Trusted device can repeat (rate-limited); review |
| D-136 unpairing (P1-5, E19) + E90 | P1 | Fixed (17C, final) | F, S, D | Shared content stays with partner; review |
| P0-1–P0-5 independent review, OpenMLS delta, core/FFI, STREAM, claim language | P0 | **Open** | — | Blocks any security claim |
| P1-6 deployment (Blaze, Functions, Storage, Eventarc, Scheduler) | P1 | **Deferred to Prompt 18** | — | Nothing deployed |
| P1-7 sign-in provider | P1 | **Deferred to Prompt 18** | — | — |
| P1-8 App Check attestation | P1 | **Deferred to Prompt 18** | 17B §4 | — |
| P2-1 partner lockout | P2 | Open (mitigated) | D-135/D-136 | Repeatable by a hostile trusted device |
| P2-3 photo-picker cache sweep | P2 | Deferred | 17B §3 | Plaintext copies after process death |
| P2-4 web CSP | P2 | Deferred | — | Needs a deployed origin |
| P2-5 repository visibility | P2 | Open | D-133 | Public until release |
| P2-6 Gradle dependency scanning | P2 | Deferred | — | Needs dependency locking |
| P2-7 local rollback detection | P2 | Deferred | D-079 | Rooted-device restore undetected |
| P2-8 retention, server and account deletion | P2 | Deferred | — | Dissolved couples' ciphertext retained |
| P2-9 EXIF stripping | P2 | Open | — | Photo metadata inside E2EE payload |
| P2-10 revocation propagation window | P2 | Needs deployment | — | — |
| P2-11 build provenance, signed releases | P2 | Open | — | — |
| P3-1 metadata exposure | P3 | Accepted | METADATA-EXPOSURE | Server sees who/when/how much |
| P3-2 exact media sizes | P3 | Accepted | D-099 | — |
| P3-3 server withholding | P3 | Accepted | E10 | Undetectable |
| P3-4 no post-quantum | P3 | Accepted | D-050 | — |
| P3-5 notification timing | P3 | Accepted | — | — |
| P3-6 Dart heap plaintext | P3 | Accepted | — | — |
| P3-7 unthrottled reads | P3 | Accepted | — | — |
| P3-8 dev-only grpc-js advisories | P3 | Accepted | — | Test harness only |
| P3-9 Rust advisory exceptions (RUSTSEC-2026-0330/0331/0173) | P3 | Accepted, re-verified each CI run | `tool/crypto_audit.sh` | Remove at next OpenMLS upgrade |
| P3-10 server lineage ordering | P3 | Accepted | D-084 | — |
| P3-11 stolen unlocked active device | P3 | Accepted | D-081 | Can also unpair or recover |
| P3-12 notebook edits unbounded | P3 | Accepted | — | — |
| P3-13 local partner anchor kept after unpair | P3 | New, accepted | §8.2 | Client cleanup in the UI phase |

### 8.7 CI evidence

- CI run `39492704498` on `9dfe673`: 10/10 jobs green. Prototypes run
  `39492704507`: 8/8 green. Counts: Flutter 683 tests; crypto Dart package
  63; Rust core 157 passed (2 ignored) + policy, fmt, clippy, cargo-audit;
  Functions unit 59, emulator 166; Firestore rules 61; Storage rules 20;
  Android emulator integration 21; Android development, staging and
  production builds; web builds (development, staging, production);
  gitleaks full history; OSV-Scanner (Dart).
- The final commit adds the E90 fail-closed bound, the injectable listing
  and 4 emulator tests (Functions emulator 170). Its CI run and SHA are
  recorded in the PR #16 description (a commit cannot contain its own
  SHA).
