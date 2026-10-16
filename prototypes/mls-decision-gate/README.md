# ⚠️ EXPERIMENTAL — NOT PRODUCTION CODE

Prompt 05 MLS decision gate. **Not part of the Sirf Hum app**: never
imported by it, no real keys, no Firebase, no user data (D-052). Its
existence does not make Sirf Hum end-to-end encrypted.

## What it answers

Which MLS implementation should be the Sirf Hum crypto core? Identical
scenarios run against **OpenMLS 0.9.1** and **mls-rs 0.56.0** through one
backend-neutral trait (`harness`), with only RFC 9420 wire bytes crossing
devices.

| Crate | Purpose |
| --- | --- |
| `harness` | `Backend` trait, 11 scenarios + 2 observations, rough benchmarks |
| `backend-openmls`, `backend-mlsrs` | Adapters (plain-label credentials; no person binding) |
| `interop` | One group mixing both implementations (15 steps) |
| `ffi` + `ffi/dart` | Narrow EXPERIMENTAL C ABI and a `dart:ffi` test; no key export |

Results and the decision:
[`docs/security/MLS-IMPLEMENTATION-COMPARISON.md`](../../docs/security/MLS-IMPLEMENTATION-COMPARISON.md) ·
[`docs/security/MLS-DECISION.md`](../../docs/security/MLS-DECISION.md).

## Run (needs a native C linker; CI does all of this)

```sh
cargo test --locked --workspace
cargo run --release -p backend-openmls --example bench
CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUNNER=wasm-bindgen-test-runner \
  cargo test --locked --target wasm32-unknown-unknown -p backend-openmls -p backend-mlsrs --tests
cargo build --release -p sh-crypto-ffi-spike && (cd ffi/dart && dart pub get && \
  SH_FFI_LIB=../../target/release/libsh_crypto_ffi_spike.so dart test)
```

CI: `.github/workflows/prototypes.yml` (native, wasm32, Dart FFI, Android,
iOS, upstream test vectors). Never enable OpenMLS `crypto-debug` /
`content-debug`.
