# Platform Strategy

Status: **Decided (Prompt 01); platforms narrowed by D-092 (2026-10-19)** — one
Flutter codebase for **Android (P0)** and **Web (P1, where applicable)**. iOS is
not part of the current product: not supported, maintained or built. Whether to
build it is decided after the Android product is launched and validated.

## Targets

| Platform | Minimum (current) | Role | Notes |
| --- | --- | --- | --- |
| Android | `flutter.minSdkVersion` (Flutter 3.41 default) | Primary mobile | Firebase requires API 23+ |
| iOS | (15.0 in the unmaintained `ios/` project) | **Not a current target (D-092)** | Not built or tested in CI; the `ios/` project and Keychain adapter remain as they were, unmaintained |
| Web | Evergreen browsers | Secondary: convenience access, larger screens | See web constraints |

Desktop (Windows/macOS/Linux) is **not** a target. Not decided for the future.

## Principles

1. **One codebase.** Shared Dart for all product logic and UI. Platform
   branching is confined to `lib/platform/` (and plugin internals).
2. **Adaptive, not separate.** Layout adapts by window size class (compact /
   medium / expanded), not by platform. Platform conventions (back gestures,
   share sheets, permission prompts, haptics) are respected via Flutter's
   adaptive widgets and `lib/platform/` wrappers.
3. **Explicit capability gaps.** Every platform service reports
   "unsupported here" rather than failing silently.

## Web constraints (must be designed for, not discovered late)

- **Key storage:** browsers lack a hardware-backed keystore comparable to
  Android Keystore / iOS Keychain + Secure Enclave. Web device keys are more
  exposed (XSS, extensions, shared computers). The E2EE phase must decide
  whether web is a full device, a restricted device, or a linked companion.
- **Background execution & notifications:** limited; Web Push requires a
  service worker and user permission; behaviour differs on iOS Safari.
- **Calls:** LiveKit supports browsers; capabilities vary (screen share,
  background audio).
- **Crashlytics** is not supported on web; web error reporting must be
  chosen separately (privacy-reviewed).
- **Content Security Policy** and hosting headers must be defined before
  web launch to reduce XSS risk to keys.

## Application identity (D-022, D-023)

| | Android application ID | iOS bundle ID | Web |
| --- | --- | --- | --- |
| Production | `com.sirfhum.app` | `com.sirfhum.app` | `app.sirfhum.com` (Hosting target `app`, domain not yet attached) |
| Staging | `com.sirfhum.app.staging` | `com.sirfhum.app.staging` | `sirf-hum-staging.web.app` |
| Development | `com.sirfhum.app.dev` | `com.sirfhum.app.dev` | `sirf-hum-dev.web.app` |

The Android namespace and Kotlin package are `com.sirfhum.app`. Production
IDs are permanent after the first store release.

## Verification status

CI verifies Android (development, staging, production builds and the
emulator integration tests), the Web build, and all shared Rust, Dart, crypto,
Firebase and security checks. iOS is not verified (D-092): the CI iOS jobs
were removed on 2026-10-19.
