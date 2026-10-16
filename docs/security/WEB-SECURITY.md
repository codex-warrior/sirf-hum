# Web Security

Status: **Assessment and recommendation (Prompt 04).** Labels follow
[E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md#labels).

## Why web is different

On mobile, the app binary comes from a store and is signed, and keys can be
wrapped by hardware-backed keystores. On the web, **the server delivers the
code on every page load**, and the code runs alongside extensions and
whatever else can inject script into the origin. For E2EE this matters most:
whoever can change the JavaScript/WASM can read plaintext and keys. A
compromised or coerced hosting path is equivalent to a compromised client.

## Threat assessment

| Threat | Exposure on web | Possible mitigations | Residual |
| --- | --- | --- | --- |
| Malicious code delivery (compromised Hosting/CI/CDN, malicious update) | **High**: every load trusts the server | Strict CSP, Subresource Integrity for third-party assets, reproducible builds, deploy only from protected CI (D-038/D-039) | No mechanism in mainstream browsers lets users pin or verify the app code they run. The operator remains in the TCB on web |
| XSS | **High impact**: script in-origin can call crypto APIs and read decrypted DOM | Flutter web renders to canvas (no HTML templating of user content), CSP without `unsafe-inline`, Trusted Types, no `eval`, no third-party scripts on the app origin | Flutter's own bootstrap and wasm loading need CSP exceptions (e.g. `wasm-unsafe-eval`); must be tested |
| Malicious browser extensions | **High**: extensions with site access can read the DOM/canvas, inject script | None reliable from the page | Users can't be fully protected; must be disclosed |
| Browser profile compromise / shared computers | **High**: IndexedDB persists; other users of the profile can open the app | Non-extractable Web Crypto keys wrapping local data; short sessions; explicit "this is a shared computer" mode with no persistence; logout wipes | Non-extractable keys stop *exfiltration* but not *use* by code running in the origin |
| Browser storage | IndexedDB/localStorage unencrypted at rest (OS disk encryption aside) | Wrap all persisted secrets with a non-extractable AES-GCM `CryptoKey` | Same as above |
| Key persistence | OpenMLS state would persist in IndexedDB | Ephemeral sessions (keys only in memory) | Ephemeral sessions can't receive while closed and lose state on reload |
| Session theft | Firebase ID tokens in browser storage | Short-lived tokens, App Check (reCAPTCHA Enterprise), re-auth for sensitive actions | A stolen session can't decrypt without device keys, but can read metadata |
| Device verification | Web "device" must be approved like any device | QR approval from a phone | — |
| Logout / local key removal | Must wipe IndexedDB and caches | Explicit wipe on logout; `Clear-Site-Data` header on logout endpoint | Browser crash or killed tab may skip the wipe |
| Remote revocation | MLS Remove + server revocation works the same as mobile | — | A revoked browser tab that is open keeps already-decrypted content |
| Browser-based backup/recovery | Typing a recovery key into a web page exposes it to the code-delivery risk above | Don't allow recovery-key entry on web in v1 | — |

Web Crypto now offers Ed25519 and X25519 in Chromium, Firefox and Safari:
- Firefox ~129–130 (2024);
- Safari 17 for Ed25519, X25519 in 2025;
- Chrome 137 for Ed25519.

The exact Chrome X25519 version is *unverified*. Web Crypto supplies
**primitives, not a protocol**. It doesn't implement MLS, so on web the MLS
library (OpenMLS compiled to wasm32) would hold its keys in WASM memory.
Non-extractable `CryptoKey`s can still wrap persisted state.

## Options

| Option | Description | Assessment |
| --- | --- | --- |
| A. Full web device | Browser is a regular MLS member with persistent keys | Weakest link in the couple's security; code-delivery risk applies to all history the device can read. **Not recommended for v1** |
| B. Ephemeral linked session | Phone approves a browser session by QR; keys live only in memory; no persistence; auto-removed from the group on logout/timeout; sees only new content | Better, but adds MLS churn (add/remove per session), no offline receipt, history needs transfer. Needs design + review. **Candidate for a later release** |
| C. No private content on web (v1) | Web offers account/settings, help, and download links; any E2EE content requires the mobile app | Keeps the privacy promise intact. **RECOMMENDED for v1** |

## Decision

- **RECOMMENDED, needs product-owner approval:** web v1 offers **no
  end-to-end-encrypted private content** (Option C). Web shows account
  settings, device management (revoke a lost phone from a computer), support
  and download prompts. The UI must not imply web is as private as mobile.
- **Next step (UNRESOLVED):** design Option B as a separate phase. Its gates:
  - CSP/Trusted Types proven compatible with Flutter web builds;
  - an isolated app origin (`app.sirfhum.com`), separate from marketing
    (`sirfhum.com`);
  - a reviewed storage design;
  - an independent review.
- Allowing remote revocation from web is safe: it uses the account session
  plus a signed request from a remaining device, or recovery. That flow is
  defined in [RECOVERY-AND-REVOCATION](RECOVERY-AND-REVOCATION.md).

This is a restricted capability, **not** a weakened promise. When web is
added for private content, the privacy promise must hold or the difference
must be disclosed plainly.
