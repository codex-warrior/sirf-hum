# Security Test Matrix

Status: **Prompt 17, 2026-10-20.** Adversarial properties → the tests that
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
- No test of conversation re-provisioning (P1-3b): designed in D-127, not
  built.
- The native Dart verification and messaging tests run only in CI (Linux
  host); this Windows machine has no host build of the core.
