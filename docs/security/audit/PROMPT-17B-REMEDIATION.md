# Prompt 17B — Security Blocker Remediation

Status: **2026-10-20.** Follows [PROMPT-17-SECURITY-REVIEW](PROMPT-17-SECURITY-REVIEW.md).
Internal engineering work, **not** an independent audit; Sirf Hum is **not**
production E2EE; nothing is deployed. Classification of what remains:
[PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md).

## 1. Fixed

| Finding | Was | Now | Decision | Proof the old behaviour failed |
| --- | --- | --- | --- | --- |
| **P17-05** (high) | Any Firebase session of either partner could win `commits/{epoch}` with filler bytes and stall the conversation | Commits, Welcomes and the epoch are server-only, written after a device-key proof (purpose 5) over the commit's exact binding; first commit wins inside the same transaction | D-127 | The Prompt 17 rules test asserted the filler commit **succeeded**; it now asserts it is refused. The Prompt 17 Dart test showed every device stalling; it is replaced by tests where the attack is refused and the conversation keeps working |
| **P17-09** (high) | No way to verify a partner; risk of silent TOFU | Safety number + QR over both root PIKs; trust only by explicit confirmation; reported revocations always applied | D-128 | New capability; the revocation gap (old identity's devices trusted until the new one was verified) is covered by `a changed partner identity (reset) needs a new comparison…` |
| **P17-08** | The inviter saw the claimant's code and confirmed without entering it | Only the invitee sees the code; the inviter enters it; 3 wrong codes end the pairing | D-131 | The Prompt 12 test asserted "both screens show the same code"; it now asserts the inviter's state has none |
| **P17-07** | A password alone could reject (permanently block) a pending device | An active device's proof (purpose 6) bound to the request | D-129 | The old call shape (`{requestId}` only) is now asserted to fail |
| Reset notifications (D-082 OPEN) | A password-only reset request raised no signal | Content-free alert to the account's active devices; to the partner on completion | D-132 | New capability; emulator tests |
| Dart advisories (P17-16, part) | No advisory gate for Dart | OSV-Scanner in CI on both `pubspec.lock` files (clean on 2026-10-20: 121 + 52 packages) | D-133 | — |

## 2. P1 items reviewed

| Item | Outcome |
| --- | --- |
| A. P17-08 forced code | **Done** (D-131) |
| B. P17-06 partner removal | **Reviewed, not changed.** Device revocation already requires a trusted device's signed statement (D-081), and since D-127 a password or session alone can no longer commit anything, so it can no longer remove devices from MLS either. What remains is a *trusted partner device* (a modified client) committing a Remove of the other person's devices. Refusing such commits on receipt would fork the group whenever a legitimate removal reaches a device with stale trust, turning a lockout into a stall. The right fix belongs with unpairing (D-134): an abusive partner can always stop participating; the victim needs a clean exit, not a contested roster. Stays **P2** |
| C. P17-07 rejection | **Done** (D-129). The residual threat (a stolen *active* device rejecting) is the same as for approvals (E25) |
| D. P17-10 App Check | **Prepared, not enabled** (§4). No fake attestation; production already refuses the debug provider (`environment_guard.dart`, tested) |
| E. Reset notifications | **Done** (D-132), undeployed (Eventarc needs Blaze) |
| F. Unpairing | **Not implemented: needs its own security decision** (D-134, Open). Shared-history policy, MLS removal versus retiring the conversation, dissolved-couple rules and account deletion are undecided; a rushed version could create a password-only path |

## 3. P2 items: mitigate now or defer

| Item | Decision | Justification |
| --- | --- | --- |
| Picker plaintext copies (P17-11) | **Defer (P2)** | `image_picker_android` copies into random-UUID directories directly under the app cache, next to other libraries' cache files; a safe sweep needs native code that recognises only the plugin's files. Exposure is a copy of a photo already in the person's gallery, in app-private storage excluded from backup (D-123). Design: a `MainActivity` channel that deletes `cacheDir/<uuid>/` directories containing only files the picker created, called at start-up and sign-out |
| Web CSP (P17-12) | **Defer (P2)** | Web holds no private content (D-046, three layers). A CSP for Flutter web (CanvasKit/WASM loading, `wasm-unsafe-eval`, Firebase endpoints) must be tested on the deployed origin, which does not exist; a wrong CSP breaks the app. Start as `Content-Security-Policy-Report-Only` on staging hosting |
| Repository settings (P17-13) | **Mitigated now** (§5) | Free for public repositories; owner authorized in Prompt 17B |
| Missing rate limits (P17-14) | **Partly mitigated** | `rejectDeviceApproval` is now behind a rate-limited challenge (D-129); the two reads (`listDeviceApprovalRequests`, `getPairingState`) stay **P3**: they reveal only the caller's own data and App Check is enforced on callables |
| Dart/Flutter/Gradle scanning (P17-16) | **Dart: mitigated** (D-133). **Gradle: defer (P2)** | Gradle has no lockfile to scan; adopt Gradle dependency locking with the release build work, then add it to OSV-Scanner. Dependabot alerts cover what the dependency graph can see |
| Local rollback (P17-17) | **Defer (P2), unchanged** | As instructed: no new trust model. Behaviour pinned by a test |
| Account deletion | **Defer (P2), with D-134** | Must end pairings, dissolve the couple and retire the conversation: the same decisions as unpairing |
| Server deletion semantics (P17-18) | **Defer (P2)** | Needs a retention decision; until then the UI says plainly that remove is not erasure (D-119) |

## 4. App Check: exact production configuration (do not enable yet)

Prerequisites, in order. Nothing here may be faked: if a step is not done,
enforcement stays off.

1. **Android app on Google Play** (internal testing track is enough) under
   package `com.sirfhum.app` with **Play App Signing**.
2. **Firebase console → App Check → Android app (production) → Play
   Integrity**: link the Google Cloud project to the Play Console app;
   register the **SHA-256 of the Play app-signing certificate** (from Play
   Console → App integrity), not the upload key.
3. **Build configuration:** production uses `SH_APPCHECK_PROVIDER=attestation`
   (the default for non-development environments). The debug provider is
   refused in production builds (`ensureEnvironmentIsConsistent`, tested).
4. **Debug tokens** only in the development project, one per developer
   machine or CI emulator, registered in that project's console; never in
   staging or production.
5. **Web (account features only):** create a reCAPTCHA Enterprise **site
   key** for the hosting domain and set `SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY`
   (public by design).
6. **Measure before enforcing:** App Check metrics in staging for one release
   cycle; proceed only at ≈100 % verified requests from current builds.
7. **Enforce in this order:** callables already enforce in code
   (`enforceAppCheck: true`), so step 1–6 must be complete **before** the
   first Functions deploy; then Firestore, then Storage in the console.
8. **Minimum supported version:** builds without App Check are rejected once
   enforcement is on; ship the version gate before enforcing.

## 5. Repository security

**Applied (owner-authorized, 2026-10-20):** secret scanning, push
protection, Dependabot alerts, and a ruleset on `main`: pull request
required, the CI checks required, no force pushes, no deletion. See the
final report for the exact state.

**Production recommendation:** make the repository **private before the
first production release**, keeping the free controls (or the paid
equivalents) on. Privacy is **not** a security boundary: the design is
written to be safe when public (Kerckhoffs), the history is already public
and cannot be recalled, and the gitleaks history scan is clean. The reasons
to go private are operational: less reconnaissance on unreviewed code, and
the release pipeline (signing, store metadata) should not be public. Keep
two-factor authentication on the single admin account; the ruleset does
not protect against that account's compromise.

## 6. External review still required

This prompt implemented and tested; it did not review independently.
External review is required, at least, for:

1. **OpenMLS integration:** the pinned 0.9.1 versus the audited commit
   (`a3402f2`), the RustCrypto provider, and our use of it.
2. **The six deliberate deviations from upstream behaviour** (review §4.4):
   credential validation, checkpoint/rollback, atomic sealed storage, input
   limits, staged commits, sender-ratchet tolerance; plus the D-126 padding.
3. **The Rust crypto core:** credential policy, exact-certificate trust unit
   (D-085), PIK uniqueness (D-122), lineage verification, sealed records.
4. **The FFI boundary:** the hand-written C ABI v6 and the Dart bindings.
5. **The device trust model:** certificates, proofs and their purposes 1–6,
   approval, recovery, signed revocation, identity reset, trust epoch.
6. **The STREAM media construction** and its composition (D-093).
7. **The application E2EE architecture:** message AAD (D-089), commit
   authorization (D-127), partner verification and the safety number
   (D-128), pairing (D-101, D-131), notifications (D-097, D-132), the web
   boundary (D-046).
