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
concurrency test showed the same emulator behaviour once, intermittently,
under parallel load; it passed on every isolated and later full run.

## 5. Tests added in Prompt 17C

| Layer | Tests |
| --- | --- |
| R | `recovery_reprovisions_a_new_group_old_history_stays_and_old_commit_cannot_replay`; purposes 7 and 8 valid, 9+ invalid (`device_identity.rs`) |
| F (`recovery.test.mjs`, 9) | valid recovery (new conversation takes a device-bound commit; old refuses commit challenges); password-only, forged, modified, wrong-purpose, missing proof, rate limit; wrong / revoked / pending / unknown device, revoked after its challenge; wrong conversation, wrong account, account switch; stale view, racing commit, racing trust change; replay, retired never recovered again, expiry; both partners at once (one wins); dissolved couple cannot recover; no plaintext / logger in `recovery.ts` |
| F (`unpair.test.mjs`, 9) | valid unpair (closes retired predecessors, devices stay trusted); password-only, forged, modified, wrong purpose, missing proof; revoked, pending, unknown, partner's device, revoked after challenge; wrong account, wrong couple, account switch, replay, stale request; concurrent unpair; racing recovery; racing pairing; racing device approval; removed partner cannot send, approve, or re-pair without fresh consent; new couple and conversation after re-pairing |
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
