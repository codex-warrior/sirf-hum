# App Check — Production Readiness

Status: **Prompt 18 (D-139), 2026-10-21. Enforcement is NOT enabled in any
project.** Builds on D-028, [ENVIRONMENTS](ENVIRONMENTS.md) ("App Check")
and [PROMPT-17B-REMEDIATION §4](../security/audit/PROMPT-17B-REMEDIATION.md#4-app-check-exact-production-configuration-do-not-enable-yet),
whose step list this document supersedes as the operational procedure.

> App Check attests that a request comes from a genuine build on a
> genuine device. It is **defence in depth**: it is never the
> authorization (device proofs and Security Rules are), and it does not
> encrypt anything. A rooted device or a determined attacker with a real
> device can still obtain tokens.

## 1. Behaviour per environment (as implemented)

| | Development | Staging | Production |
| --- | --- | --- | --- |
| Android provider | Debug (`AndroidDebugProvider`) | Play Integrity | Play Integrity |
| Web provider | Debug | reCAPTCHA Enterprise if a site key is set, else **skipped with a warning** | reCAPTCHA Enterprise; **without a site key the app refuses to start** (D-139) |
| `SH_APPCHECK_PROVIDER=debug` | default | allowed (e.g. a staging build on an emulator) | **refused at start-up** (`environment_guard.dart`) |
| Emulator / local | Debug tokens; Functions emulator does not verify App Check | — | — |
| Callables | `enforceAppCheck: true` on all 29 (static test `functions/test/app_check.test.mjs`) | same | **paused** (`SH_APP_CHECK_PAUSED=true` in `functions/.env.production`, D-152) until Play Console links Play Integrity |
| Firestore / Storage / Auth enforcement | off (console) | off | off |

Failure behaviour (client): if activation fails the app keeps running and
logs `app_check_activation_failed` (category only). Requests then carry no
token: while console enforcement is off, Firestore/Storage still answer;
callables are rejected by Firebase before the function runs. The client
turns any callable error into a failure category from the server message
(`PairingFailure.fromServer`, `DeviceRegistryFailure.fromServer`, …), so
an unattested call fails like any other refused call: never a success,
never a fallback path. The exact user-facing state for a rejected App
Check token has **not** been exercised against a deployed project.

Backend: Firebase verifies the token before the callable runs; the
function never sees an unverified request when `enforceAppCheck` is true.
Firestore and Storage verify in the service once enforced in the console.
iOS is out of scope (D-092); its provider code is not used.

## 2. What is verified by tests

| Property | Test |
| --- | --- |
| Production never uses the debug provider | `test/app/environment_guard_test.dart` `production forbids the App Check debug provider` |
| Production web never starts unattested | `production web App Check (D-139)` group (4 tests) |
| Development and staging are not locked out | same group, `development and staging stay usable without one` |
| Provider selection | `test/infrastructure/app_check_test.dart` |
| Every callable enforces App Check; no HTTP endpoints | `functions/test/app_check.test.mjs` (mutation-checked: setting `enforceAppCheck: false` fails it) |

Not testable here: real attestation (needs Play and a deployed project).

## 3. Manual steps (owner; none performed)

Order matters. **Steps 1–8 must be complete before the first Functions
deploy**, because callables already enforce App Check in code: deploying
first would reject every client.

1. **Play Console:** create the app `com.sirfhum.app`, enrol in **Play App
   Signing**, upload a first build to the **internal testing** track
   (needs the release pipeline, D-143).
2. **Staging first:** repeat steps 3–8 for `sirf-hum-staging` /
   `com.sirfhum.app.staging` before production.
3. **Firebase console → App Check → Apps → Android (production) → Play
   Integrity → Register:** link the Google Cloud project in Play Console
   (App integrity → Integrity API); register the **SHA-256 of the Play
   app-signing certificate** (Play Console → App integrity), not the
   upload key's.
4. **Web (account features only):** Google Cloud console → reCAPTCHA
   Enterprise → create a **score-based website key** for the Hosting
   domain(s); App Check → Apps → Web → reCAPTCHA Enterprise → paste the
   site key. Put the public site key in `config/env/production.json` as
   `SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY` (the build refuses to start
   without it).
5. **Debug tokens:** development project only, one per developer machine
   and one for the CI emulator, registered under App Check → Apps →
   Manage debug tokens; never in staging or production; revoke when a
   machine is retired.
6. **Minimum supported version:** ship the version gate (builds older
   than the first App-Check-capable release are refused) before enforcing.
7. **Measure:** App Check → Metrics in staging for one release cycle;
   continue only at ≈100 % verified requests from current builds, and
   investigate unverified traffic first.
8. **Production metrics:** the same in production with real testers
   (internal track), enforcement still off.
9. **Enforce, one service at a time, watching errors between steps:**
   Cloud Functions (already in code) → Firestore → Cloud Storage →
   Authentication (Identity Toolkit). Roll back a step by switching that
   service to "Unenforced" in the console.

## 4. What stays open

- Enforcement itself (P1-8): blocked by steps 1–8, which need a Play
  listing, a signed release and a deployed project.
- Replay-protected limited-use tokens (`consumeAppCheckToken`) for the
  most sensitive callables (pairing, unpair, reset): not adopted (D-139);
  decide after staging metrics.
- App Check cannot stop a modified client on a rooted device that passes
  or fakes integrity checks (THREAT-MODEL "malicious modified client").
  The server's real defences are the device proofs and rules.
