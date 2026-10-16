# ⚠️ EXPERIMENTAL SPIKE — NOT PRODUCTION CODE

Status: **experimental, isolated, not part of the Sirf Hum app.** It is not
compiled into the Flutter app, not shipped, and holds no credentials or user
data. It does not mean Sirf Hum is end-to-end encrypted.

## Question it answers

Can an unmodified, maintained implementation of MLS (RFC 9420), here OpenMLS
0.9.1, express the Sirf Hum model?

- One group per couple; **members are devices** of two independent people.
- Every device converges on the same **authenticated device roster**.
- A **removed device cannot read** messages sent after its removal, whether
  it was online or offline when removed.
- **Replayed** and **tampered** ciphertexts are rejected.
- The same code **compiles for `wasm32-unknown-unknown`** (the browser target).

See `docs/security/E2EE-ARCHITECTURE.md` → "Prototype" for the result and
what it does *not* establish.

## What it is not

- Not a protocol. All cryptography is OpenMLS; this code only wires devices.
- No device-to-person binding (credentials are plain labels here).
- No persistence, key storage, Flutter bridge, Firebase or delivery service.
- Not a test of OpenMLS' cryptographic correctness. OpenMLS' own RFC 9420
  test-vector and interop suites cover that.

## Run

```sh
cargo test                                          # native (needs a C linker)
rustup target add wasm32-unknown-unknown
cargo build --target wasm32-unknown-unknown --tests  # browser target compiles
```

CI: `.github/workflows/prototypes.yml` (runs only when this folder changes).

Never enable OpenMLS' `crypto-debug` or `content-debug` features: they log
secrets and plaintext.
