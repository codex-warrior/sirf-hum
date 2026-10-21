# Security Test Matrix

Status: **Prompt 17, 2026-10-20; Prompt 17B; Prompt 17C (2026-10-21); Prompt 18 (2026-10-21).** Adversarial properties → the tests that
exercise them. **New** marks tests added in Prompt 17; each was shown to fail
on the pre-Prompt-17 code. Full per-phase lists:
[E2EE-TEST-PLAN](../../testing/E2EE-TEST-PLAN.md).

Locations: **R** = Rust (`packages/sirf_hum_crypto/native/{src,tests}`),
**F** = Functions emulator (`functions/test/emulator`), **Fu** = Functions
unit (`functions/test`), **S** = Security Rules (`firebase/tests`),
**D** = Dart/Flutter (`test/`, `packages/sirf_hum_crypto/test`),
**I** = on-device integration (`integration_test/`, CI Android emulator).

## Device trust

| Property | Tests |
| --- | --- |
| Revoked device certifies a new device ID | R `a_revoked_device_cannot_mint_a_new_device_id_with_its_old_pik`; **New** R `a_revoked_pik_cannot_return_through_an_unaware_approver`; **New** F `a revoked device's PIK never returns under a new device ID, even through an unaware approver`; **New** F `two pending devices sharing a PIK: the second activation is refused, whoever approves it`; F `A approves B, A revokes B: B can never reactivate or re-register` |
| Old certificate / new device ID; copied keys | R `a_trusted_device_id_under_another_pik_is_refused`, `a_revoked_device_cannot_reuse_its_old_certificate`; F `certificate for a different device ID than the record is rejected`, `copied stale local state (same keys) cannot come back`, `duplicate device public key under a different device ID is rejected` |
| PIK reuse across accounts / identity epochs | **New** F `a PIK is global: another account cannot activate a device with it, even when registered first`, `after an identity reset the old root's PIK cannot root the new identity`; **New** S `personKeyIndex` in `server-only collections` |
| Rollback of trust state | R `stale_lineage_and_stale_approvals_are_refused`, `trust_epoch_only_moves_forward_and_survives_restart`, `trust_policy_survives_restart_exactly`; S `no client can write it: no epoch rollback, bootstrap reopen or fake reset`; **New** R `documented_limit_a_restored_older_state_is_not_detected_until_refreshed` (pins D-079) |
| Replayed approval / revocation / recovery | F `already-consumed (replayed / duplicated) approval`, `wrong device: an approval for D replayed onto C`, `replayed revocation and revoking twice fail; the challenge is single-use`, `two recovery attempts with one single-use key: one wins` |
| Concurrency | F `two first devices bootstrapping at once: only one becomes the root`, `two simultaneous approvals of one request: exactly one wins`, `approval racing a revocation of its approver: the end state is consistent`, `concurrent registrations never exceed the pending cap` |
| Domain separation / forgery | Fu `statements.test.mjs`, `hardening.test.mjs`, `device_proof.test.mjs`; R golden vectors `server_generated_*_vectors_verify_in_rust`; D `lineage_test.dart` |
| Server omission / ordering (documented limits) | R `server_omission_drops_trust_but_never_adds_it`, `documented_limit_peers_rely_on_server_ordering_for_revoked_approvers` |

## MLS and messages

| Property | Tests |
| --- | --- |
| Stale / concurrent / rejected commits | R `concurrent_commits_first_wins_and_the_loser_converges`, `group_creation_race_loser_joins_the_winner`, `a_staged_commit_blocks_everything_that_would_fork_state`, `discard_restores_the_active_state_and_is_idempotent`; S `a second commit for the same epoch loses`, `forged commits are refused` |
| Untrusted / revoked members | R `untrusted_member_in_welcome_is_rejected_before_joining`, `revoked_device_is_removed_and_cannot_rejoin_or_send`, `lineage_trust_and_signed_revocation_drive_mls_membership`, `removed_device_cannot_decrypt_new_epoch` |
| Tampered ciphertext; rejected forgery keeps the key | R `tampered_ciphertext_fails_and_never_consumes_the_key`, `forged_then_valid_message_still_decrypts`, `malformed_then_valid_message_still_decrypts` |
| Wrong AAD / sender / epoch / conversation | R `every_envelope_field_is_cryptographically_bound`, `ciphertext_copied_into_another_conversation_fails`, `group_id_is_the_conversation_id_and_welcomes_cannot_be_redirected`, `future_epoch_waits_for_the_commit_and_stale_epoch_fails_closed`, `late_message_from_previous_epoch_fails_closed` |
| Replay | R `replay_is_rejected`, `duplicates_are_reported_and_replays_rejected` |
| Stale offline message | R `offline_send_is_queued_sealed_and_reencrypted_after_a_stale_refusal`; D `messaging_service_test.dart` |
| Message length hidden within a block | **New** R `ciphertext_length_hides_the_message_length_within_a_block` |
| Rules: sender device / account-level authorization | S `2–5. wrong account, revoked, pending or fake sender devices are refused`; **New** S `documented limit: rules authorize accounts, not devices` (E77) |
| Device-bound commit authorization (D-127) | **17B** F `device-bound commit authorization (D-127)`: active device commits; password-only session fails; wrong device; revoked/pending/unknown (incl. revoked after its challenge); modified signature/conversation/epoch/commit/Welcome/purpose; replay and expiry; concurrent valid commits (first wins); wrong account or couple; malformed. S `commits, Welcomes and the epoch are server-only (D-127)`. Fu `commit authorization v1`. D vector `commit_authorization_test.dart`; D native (CI) `a session without the device key cannot move the epoch; the conversation keeps working`, `a refused authorization never advances local state; a valid one then does`, `revoked, pending and unknown devices get no commit authorization`, `an authorization is bound to its device and account…` |

## Media

| Property | Tests |
| --- | --- |
| Reorder / truncate / tamper / extend / swap | R (unit) `stream_layer_detects_reordering_and_truncation_by_itself`, `wrong_or_tampered_chunks_fail_under_the_schedule`, `the_old_every_chunk_aad_schedule_is_not_accepted`; R `any_modified_object_fails_closed_and_the_genuine_one_still_opens`, `another_objects_ciphertext_is_never_accepted` |
| Conversation / sender binding | R `objects_are_bound_to_their_conversation`, `another_account_cannot_open_the_media`; R (unit) `stream_layer_round_trips_and_rejects_wrong_bindings` |
| Key never crosses Dart; revoked recipients | R `dart_cannot_send_a_media_reference_itself`, `a_revoked_recipient_gets_no_key_for_media_sent_after_its_removal`, `a_revoked_sender_cannot_deliver_new_media_but_old_media_stays` |
| No plaintext at rest | R `no_plaintext_reaches_disk_through_send_or_open`; D `media_service_test.dart` |

## Couples, isolation, sessions, web

| Property | Tests |
| --- | --- |
| Cross-couple access | S `moments_isolation.test.js` (`another couple gets nothing`, forged references), `messaging.test.js` (`1. an account outside the conversation…`); D Moments/notebook service tests (another conversation, another account's core) |
| Pairing: interception, replay, enumeration, races | F `pairing.test.mjs` (`the inviter rejects the account that accepted (e.g. an intercepted link)`, `a token redeems once…`, `an account in an open pairing learns nothing about tokens it presents (no non-consuming probe)`, four concurrency tests) |
| Account switch / sign-out during async work | D `an account switch never carries the old session over`, `a start in flight across sign-out cannot resurrect it`, `a join in flight across an account switch is dropped`, `signed out: nothing from before stays, and a late answer…`, `account A → sign out → account B: B sees only B's notebook…`, `a write that finishes after the account changed never shows…`, `account switch never reuses another account identity` |
| Web private-content boundary | D `web never loads moments, whatever backend exists`, `web never loads the notebook, whatever backend exists`, `web: needs the phone, the backend is never asked`, `Web never gets a device identity`, `private_content_crypto_test.dart`; CI web builds |
| Log leakage | Fu `every logger call logs only an event name and an outcome category`, notification and pairing static guards; R `crypto_core_source_contains_no_logging_or_printing`, `debug_output_is_redacted`, `decrypted_content_and_handshake_outputs_never_print`; D `app_logger_test.dart`, `the recovery key, signatures and codes are never logged` |
| Notification leakage | Fu `no identifiers, topics, previews or other platforms ever appear`; F `revoked, pending and stale devices are never targeted…`, `a password alone cannot register a token…` |

## Prompt 17B

| Property | Tests |
| --- | --- |
| Partner verification (D-128) | D `safety_number_test.dart` (7); D `verification_controller_test.dart` (13: gating, explicit confirmation only, wrong QR, "They don't match", changed while shown, revoked, single flight, sign-out and account switch during async work, logs, the Us → Safety screen flow); D native (CI) `partner_verification_test.dart` (10: correct verification, wrong QR, restart, server substitution, new device, changed identity, revoked root, account switch, revoked own device, unavailable partner) |
| Forced code comparison (D-131) | F `forced code comparison (D-131)` (5); D pairing parse/service tests |
| Rejection needs a trusted device (D-129) | F `rejection needs a trusted device (D-129)` (2) + updated rejection tests; D trust-service test (native) |
| Reset alerts (D-132) | Fu payload test; F `identity reset alerts (D-132)` (3); static guards |
| Proof purposes 5 and 6 | R `proof_purposes_are_separate_signed_domains`, `challenge_must_be_exactly_32_bytes`; Fu purpose matrix; D wire values |

## Known gaps (no test, by design or pending)

- No on-device Android backup/restore test for D-123 (manifest verified by
  the CI build only).
- No end-to-end forged `media_ref` from another member (D-093 F9).
- No fuzzing of MLS, lineage or certificate decoders beyond the malformed
  input tests (recommended for the independent review).
- ~~No test of conversation re-provisioning (P1-3b)~~: built and tested in
  Prompt 17C (D-135, section below).
- The native Dart verification and messaging tests run only in CI (Linux
  host); this Windows machine has no host build of the core.

## Conversation recovery and unpairing (Prompt 17C)

| Property | Tests |
| --- | --- |
| Recovery is device-bound (D-135) | **17C** F `a password-only session, a forged or modified proof, or another purpose cannot recover`, `wrong, revoked, pending and unknown devices cannot recover; nor one revoked after its challenge`, `wrong conversation, wrong account and account switch are refused`; D native (CI) `recovery is device-bound: …` |
| Recovery is state-bound, single-use, one winner | **17C** F `a stale view (epoch or trust epoch) is refused…`, `replay: an authorization works once; a retired conversation is never recovered again`, `both partners recovering at once: exactly one successor, both records agree`, `a dissolved couple cannot be recovered`; D native `recovery is state-bound: …` |
| Recovered conversation works; old history stays; old commit cannot replay; no server plaintext | **17C** R `recovery_reprovisions_a_new_group_old_history_stays_and_old_commit_cannot_replay`; F `a trusted device recovers: old retired, a new group for the same couple, and it works`, `the recovery module never reads, rebuilds or decrypts messages`; D native `recovery: a new group for the couple; old history stays, …, pending messages are not re-sent` |
| Successor redirection by the server | **17C** D native `a successor is followed only if it names this conversation and has the same members` |
| Retired / closed conversations (rules) | **17C** S retired readable not writable; closed contents and media unreadable, no writes (`messaging.test.js`, `media_storage.test.js`) |
| Unpair is device-bound (D-136) | **17C** F `a password-only session, a forged or modified proof, or another purpose cannot unpair`, `revoked, pending, unknown and the partner's devices cannot unpair for an account`, `wrong account, wrong couple, account switch, replay and a stale request are refused`; D `unpair: an unpair-purpose proof over the couple-bound challenge`, `unpair: another account, or a malformed couple ID, never reaches the server` |
| Unpair effects and races | **17C** F `either partner leaves from an active device: …`, `both partners leaving at once: …`, `unpair racing recovery: …`, `unpair racing pairing: …`, `unpair racing device approval: …` |
| E90: no conversation missed by unpairing | **17C-final** F `E90: a successor created after the listing is still closed`, `E90: conversations missing from the listing are found through the predecessor chain`, `E90: a lineage beyond the walk bound fails closed; nothing changes`, `E90: repeated unpair/recovery races never leave an open conversation` (mutation-checked: disabling the walk fails the first three) |
| Removed partner | **17C** F `the removed partner can neither send, approve for the other, nor re-pair without fresh consent` |
| Derivations agree across TS and Dart | **17C** Fu `lifecycle.test.mjs`; D `lifecycle_authorization_test.dart`; D drift guard `server failure categories cover every server category` |

## Prompt 18

| Property | Tests |
| --- | --- |
| P3-15: unpair authorizes before reading the lineage (D-144) | **18** F `P3-15: no listing or lineage walk before the request is authorized` (spy lister never called for a forged proof, unknown challenge, wrong purpose, expired challenge, another account's couple, revoked device; called once authorized), `P3-15: an over-long lineage answers a forged proof with proof_invalid, not the walk bound`; both fail on the pre-Prompt-18 code |
| Production deploy lock and launch gate (D-137) | **18** `tool/test_deploy_guard.sh` (23 hermetic dry runs: laptop production refused; Functions/Hosting/`extensions`/whitespace/combined lists refused while closed; rules and Storage rules allowed; `Open`, `true`, malformed and missing gate files stay closed; confirmation, `main` and clean-tree gates still apply; 20 fail on the previous script) |
| App Check on every callable (D-139) | **18** Fu `app_check.test.mjs` (3: single `onCall` with `enforceAppCheck: true`, no `onRequest`, 29 callables through `callable()`/`audited()`; mutation-checked) |
| Production web never unattested (D-139) | **18** D `production web App Check (D-139)` (4: refuses without site key, starts with one, development and staging not locked out, Android unaffected) |
| Web header policy (D-140) | **18** `tool/check_web_headers.mjs` (CSP directives, banned script sources, frame/MIME/referrer/permissions/HSTS/COOP/CORP, no-cache entry points; 9 failures on the previous `firebase.json`); manual headless-Chrome run: 0 reports with the policy, 6 with a strict control (WEB-SECURITY) |
| Picker plaintext copies swept (D-141) | **18** D `picker_cache_sweeper_test.dart` (7: picker-shaped directories removed; other names, wrong UUID version/variant, nested directories, loose files kept; links never followed; missing cache; channel failure; unsupported platforms never ask); I `a leftover photo-picker copy is swept at start-up` (CI emulator, real channel and cache) |
| Gradle supply chain (D-142) | **18** CI: production release resolves against `android/app/gradle.lockfile` (STRICT) and must not change it; OSV-Scanner on the lockfile; wrapper `distributionSha256Sum` |
| No silently debug-signed production release (D-143) | **18** CI step `A production release is never silently debug-signed` (Gradle dry run must fail with the signing message); verified locally with and without the opt-in |

## Prompt 19

| Property | Tests |
| --- | --- |
| A build config holds only its environment's identifiers (D-146) | **19** `tool/test_check_env_config.mjs` (9: staging-only passes; wrong `SH_ENV`, wrong sender, a production app ID or bucket in a staging file, a staging file checked as production, the production debug provider, non-objects and unknown environments fail; problems name keys, never values); CI and `tool/verify.sh` |
| Staging APK embeds staging config only (D-146) | **19** `staging-build.yml` steps (application ID, crypto core per ABI, `libapp.so` has the staging Android app ID and no development or production app ID); **not yet run** (needs `main` and the staging secret) |
| Deployed staging rules = reviewed rules | **19** manual: live ruleset source byte-compared with `firebase/firestore.rules`; unauthenticated GET/LIST/PATCH on `users`, `couples`, `conversations`, `accountTrust`, devices → 403 (STAGING-BETA §3) |
| Live staging security tests A–P | **19** not run beyond the unauthenticated deny probe: blocked by billing, sign-in and App Check (STAGING-BETA §5) |

