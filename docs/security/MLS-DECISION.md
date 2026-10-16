# MLS Decision (Prompt 05 decision gate)

Status: **Decided for development, conditional for production
(2026-10-16).** Evidence: [MLS-IMPLEMENTATION-COMPARISON](MLS-IMPLEMENTATION-COMPARISON.md).
Decision Log: D-054 (supersedes the open D-043).

> **Sirf Hum is NOT production E2EE.** Nothing here is in the app.

## Can Sirf Hum safely proceed with MLS?

**Yes, as the protocol foundation, with conditions.**
- Both evaluated implementations passed every security-relevant scenario
  in our model, natively and on wasm32:
  - the device lifecycle;
  - revocation;
  - stale state;
  - replay, tamper and outsider rejection.
- They interoperate on the wire, and their upstream RFC 9420 test-vector
  suites pass at the pinned versions.
- No finding suggests MLS is unsafe for a two-person, multi-device group.

The investigation also surfaced issues the application must handle. Those
are the conditions below.

## Decision

**Cryptographic core: OpenMLS `0.9.1`** (MIT), with `openmls_rust_crypto`
`0.6.0`, `openmls_basic_credential` `0.6.0` and `openmls_traits` `0.6.0`.
`mls-rs` `0.56.0` is the **tested fallback**: our harness and interop suite
keep it runnable, so switching stays practical.

**Confidence: MEDIUM.**

### Why OpenMLS (evidence)

1. **Independent review exists.** SRLabs assessed the core crates
   (report v1.2, 2026-03-11) and found 8 issues, the most serious fixed.
   mls-rs states it has had no third-party audit. For a product whose
   promise is privacy, reviewed code beats unreviewed code when engineering
   fit is otherwise comparable.
2. **A visible security process.** Five advisories were published with
   fixed versions, three of them *after* the audit, showing ongoing
   scrutiny. mls-rs has published none: absence of advisories is not
   evidence of absence of bugs.
3. **Production use** through Wire (pinned fork), XMTP and White Noise,
   two of which had their own third-party reviews.
4. **Upstream wasm32 testing** in OpenMLS' own CI, matching our measured
   wasm results.

### Why not HIGH confidence

- The audit covered commit `a3402f2` (2025-10-22), **not 0.9.1**. The delta
  since then is unreviewed, and three parser/DoS advisories appeared in it.
- **Crypto providers, storage providers and bindings were out of audit
  scope.** We would ship `openmls_rust_crypto` (RustCrypto crates) and our
  own storage provider.
- Audit finding **S1-3 (storage desync) is acknowledged, not fixed**.
- No published independent review of the `openmls_rust_crypto` provider was
  found.

### Where mls-rs fits better (and how we compensate)

| mls-rs advantage | Compensation required with OpenMLS |
| --- | --- |
| `IdentityProvider` hook validates credentials inside the library | Our crypto core must validate every credential (PIK certificate policy) before merging any staged commit or welcome; tested negative cases required |
| Explicit `write_to_storage()` gives the app atomic control | Transactional storage provider (single transaction per processing call) + checkpoint/rollback |
| Keeps prior-epoch keys (late messages decrypt) | Configure a small past-epoch window deliberately (D-060) |
| ~50% smaller binaries | Accept ~2.5 MB arm64 / 2.7 MB wasm for now |

## Conditions before production use

1. **Delta review.** An independent review of OpenMLS changes from
   `a3402f2` to the exact pinned version, *plus* our crypto core: credential
   policy, storage provider, FFI boundary, and processing/rollback logic.
2. **Crypto provider review.** Evidence of review for the RustCrypto crates
   behind `openmls_rust_crypto`, or adopt `openmls_libcrux_crypto`
   (formally verified primitives) after verifying it supports ciphersuite
   0x0001 on Android, iOS and wasm32.
3. **Transactional persistence** mitigating S1-3, so one processing call is
   one atomic commit to local storage, with rollback on any failure.
4. **Rollback-on-rejection processing** for every untrusted input,
   mitigating rejected-forgery poisoning (measured in both libraries).
5. **Credential validation layer.** Accept only device certificates chained
   to the two verified Person Identity Keys (D-045). Never use
   BasicCredential trust in production.
6. **Input limits** before parsing: message size, extension count, nesting
   (audit S0-1 risk-accepted upstream; 2026 parser advisories).
7. **Forbidden features enforced in CI:** `crypto-debug`, `content-debug`.
8. **Exact pins + advisory monitoring:** `cargo-deny`/RustSec on every
   build; upgrade only via a reviewed PR that reruns the full decision-gate
   suite and upstream vectors.
9. **Platform security testing** on real devices (keystore integration,
   backup exclusion, memory handling) and **penetration testing** before
   launch.
10. **Independent cryptographic review of the whole design** (identity,
    pairing, recovery) before any public E2EE claim.

## Revisit triggers

- A High/Critical advisory in OpenMLS without a timely fix, or the project
  becoming unmaintained (no release or security response for ~6 months).
- **mls-rs publishes an independent audit**, or another implementation with
  stronger review evidence appears.
- Breaking API or storage-format changes that block upgrades.
- Flutter/FFI integration breaks on a supported platform.
- A standardized post-quantum MLS ciphersuite becomes implementable
  (crypto-agility path, D-050/D-061).
- Changes to RFC 9420 errata or MLS architecture guidance that affect our
  usage.
- Binary size becoming a store or performance problem.

## Dependency lock (prototype; production pins are set when the crypto core is created)

| Package | Exact version | Source | Tag / commit | License |
| --- | --- | --- | --- | --- |
| openmls | 0.9.1 | crates.io / github.com/openmls/openmls | `v0.9.1` = `1762090a4523cdd241f454b4058e91b64bbdc6de` | MIT |
| openmls_rust_crypto | 0.6.0 | crates.io (same repo) | released with v0.9.x workspace | MIT |
| openmls_basic_credential | 0.6.0 | crates.io (same repo) | same | MIT |
| openmls_traits | 0.6.0 | crates.io (same repo) | same | MIT |
| mls-rs (fallback) | 0.56.0 | crates.io / github.com/awslabs/mls-rs | `0.56.0` = `8f1b43f447a792ff9307f1c2c7f54da63914870e` | Apache-2.0 OR MIT |
| mls-rs-crypto-rustcrypto (fallback) | 0.22.1 | crates.io (same repo) | — | Apache-2.0 OR MIT |
| mls-rs-core (fallback) | 0.27.0 | crates.io (same repo) | — | Apache-2.0 OR MIT |

The full transitive set is locked in `prototypes/mls-decision-gate/Cargo.lock`.

## What still needs review (security review gate)

| Area | Code review | Protocol review | Dependency review | Independent crypto/security review | Pen test | Platform security test |
| --- | --- | --- | --- | --- | --- | --- |
| OpenMLS core (delta since audit) | ✔ | — | ✔ | ✔ | — | — |
| Crypto provider | ✔ | — | ✔ | ✔ | — | — |
| Our crypto core (credential policy, storage, rollback) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| FFI / Dart boundary | ✔ | — | ✔ | ✔ | ✔ | ✔ |
| Identity, pairing, recovery design | — | ✔ | — | ✔ | ✔ | — |
| Android/iOS key storage integration | ✔ | — | ✔ | ✔ | ✔ | ✔ |
| Firebase rules for ciphertext access | ✔ | — | — | ✔ | ✔ | — |

Using an established protocol does not make an implementation secure.
