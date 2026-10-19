# Testing Strategy

Status: **Framework established (Prompt 01).** Coverage is minimal because
the product is minimal. No coverage claims are made.

## Layers

| Layer | Tool | Location | What it proves | Status |
| --- | --- | --- | --- | --- |
| Unit | `flutter_test` | `test/**` (mirrors `lib/`) | Business logic, config, tokens, security boundary types | ✅ in use |
| Widget | `flutter_test` | `test/**` | UI behaviour, navigation, accessibility guidelines, text scaling | ✅ in use |
| Integration | `integration_test` | `integration_test/` | Real entrypoint on device/emulator/browser | ✅ smoke test passes on Android API 36 emulator (locally); not in CI yet |
| Security Rules | `@firebase/rules-unit-testing` + emulators, `node --test` | `firebase/tests/` | Authorization and privacy boundaries | ✅ default-deny tests |
| Cloud Functions | `node --test` on compiled output (+ `firebase-functions-test` later) | `functions/test/` | Environment/project guard; later server logic and authorization | ✅ environment guard tests |
| Environment safety | `flutter_test` | `test/app/environment_guard_test.dart` | Builds cannot cross environments | ✅ |
| Logging privacy | `flutter_test` | `test/core/logging/` | Redaction, error-type-only, sink isolation | ✅ |
| E2EE | Known-answer vectors, cross-platform interop, negative tests ([E2EE-TEST-PLAN](E2EE-TEST-PLAN.md)) | Rust crypto core + `test/security/` | Cryptographic correctness | Crypto-core foundation tests in `packages/sirf_hum_crypto` (Rust, Dart, device) and the decision-gate regression suite (`prototypes/mls-decision-gate`); vectors, interop and review still planned |
| End-to-end | TBD (Patrol / integration_test on device farms) | — | Critical cross-platform flows (pair, message, call) | Future |

## Conventions

- Test files mirror source paths: `lib/a/b.dart` → `test/a/b_test.dart`.
- Test names describe behaviour in plain English.
- Prefer fakes injected via constructors or Riverpod overrides over mocking
  libraries; add a mocking library only when fakes become costly.
- Every widget test that renders a screen should include accessibility
  guideline checks (`androidTapTargetGuideline`, `iOSTapTargetGuideline`,
  `labeledTapTargetGuideline`, `textContrastGuideline`) in light and dark.
- Every Security Rules change ships with tests for **allowed and denied**
  cases (other couple, ex-partner, revoked device, unauthenticated).
- Never disable, skip or weaken a test to make CI pass. Never weaken rules
  to make a test pass.

## Accessibility tests in place

- Semantic color contrast ≥ 4.5:1 (text) and ≥ 3:1 (focus) in both themes.
- Flutter guideline checks on the app shell in both themes.
- 200% text scaling without overflow.
- Reduced motion: `Motion.resolve` returns zero duration.

## Running

```sh
flutter test                                   # unit + widget
flutter test integration_test --flavor development -d <device-id>   # integration (device/emulator)
(cd firebase && npm ci && npm test)            # Security Rules (needs Java + firebase-tools)
(cd packages/sirf_hum_crypto && dart test)     # crypto package (native tests need a Linux/macOS host)
(cd packages/sirf_hum_crypto/native && cargo test --locked)   # Rust crypto core
(cd functions && npm run test:emulator)        # device registration flows (Java + firebase-tools)
flutter test integration_test/device_identity_test.dart --flavor development -d <device>   # real Keystore/Keychain
tool/verify.sh --all                           # everything runnable locally
```

## Gaps (honest)

- App smoke integration test not executed in CI (the crypto-core, device identity and messaging integration tests are, on the Android emulator; iOS is not run, D-092). Locally: keep the emulator screen awake (`adb shell svc power stayon true`) or it renders no frames and the test hangs.
- No golden (screenshot) tests yet — add once visual identity is set.
- No Functions tests (no functions exist).
- No coverage thresholds configured.
- Rust crypto tests cannot link on Windows without the MSVC Build Tools; they run in CI (Linux).
