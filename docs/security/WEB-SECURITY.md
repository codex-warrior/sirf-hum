# Web Security

Status: **Assessment and recommendation (Prompt 04); implemented state and review added (Prompt 18, D-139, D-140).** Labels follow
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

## Prompt 18: implemented state and review (2026-10-21)

Everything above remains the design rationale. This section records what
the web build **actually** does now (D-046 accepted, D-139, D-140).

> **Web does not hold private content and does not do E2EE.** Headers,
> CSP and App Check reduce the attack surface of an account-management
> origin; they **do not** make the web client trusted, and none of them is
> a reason to enable private content on web.

### Fail-closed private-content boundary

| Layer | Behaviour | Evidence |
| --- | --- | --- |
| Device identity | Web never gets one; the platform key store reports unsupported | `Web never gets a device identity`; `PlatformSecureKeyStore.isSupported` |
| Crypto core | Not built for web; `private_content_crypto` refuses on web | `private_content_crypto_test.dart` |
| Messages, Moments, Future + Us | Controllers never ask the backend on web; screens show the "use your phone" notice | `web never loads moments…`, `web never loads the notebook…`, `web: needs the phone, the backend is never asked` |
| Photo picker, QR scanner, picker sweep | Not wired on web (`main.dart`, `kIsWeb`) | `main.dart`; `PickerCacheSweeper.isSupported` |
| Recovery key entry | Not offered on web | RECOVERY-AND-REVOCATION |

### Browser persistence

| Store | What | Assessment |
| --- | --- | --- |
| IndexedDB (`firebaseLocalStorageDb`) | Firebase Auth session (refresh token, UID, email) | SDK default (`LOCAL`), not overridden. A stolen session = an account session (AUTH-PRODUCTION-DECISION §3): metadata, no content. Consider `SESSION` persistence when the web sign-in UI is built |
| Firestore cache | none persisted: offline persistence is off by default on web and the app does not enable it | Reads on web are account-level records only |
| Service worker | Flutter 3.41 emits a **self-unregistering** stub (`flutter_service_worker.js`): it unregisters itself and reloads clients; no offline cache | Verified in a local production web build |
| HTTP cache | `index.html`, `flutter_bootstrap.js`, `main.dart.js`, `version.json` and the service worker are `no-cache`, so a fixed or revoked build applies on the next load | `tool/check_web_headers.mjs` |
| localStorage / cookies set by the app | none | `grep` of `lib/` (no `shared_preferences`, no `package:web` storage) |

No private plaintext is persisted in the browser because no private
plaintext exists on web.

### Headers (Firebase Hosting, every path)

| Header | Value | Purpose |
| --- | --- | --- |
| `Content-Security-Policy-Report-Only` | `default-src 'self'`; `script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com https://www.google.com/recaptcha/`; `style-src 'self' 'unsafe-inline'`; `img-src 'self' data: blob:`; `font-src 'self' data: https://fonts.gstatic.com`; `connect-src 'self' https://*.googleapis.com https://*.cloudfunctions.net https://www.gstatic.com https://fonts.gstatic.com https://www.google.com`; `worker-src 'self' blob:`; `frame-src` reCAPTCHA only; `frame-ancestors 'none'`; `object-src 'none'`; `base-uri 'self'`; `form-action 'none'`; `manifest-src 'self'` | Script injection and exfiltration limits; **report-only** for now |
| `X-Frame-Options` | `DENY` | Framing (with `frame-ancestors`) |
| `X-Content-Type-Options` | `nosniff` | MIME sniffing |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | No paths leak to other origins |
| `Permissions-Policy` | camera, microphone, geolocation, display-capture, payment, usb, serial, bluetooth, hid, midi all `()` | Web needs none of them; LiveKit on web would need a reviewed change |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | HTTPS only (no `preload` until the domain is final) |
| `Cross-Origin-Opener-Policy` | `same-origin-allow-popups` | Window isolation; popups kept possible for a future sign-in flow |
| `Cross-Origin-Resource-Policy` | `same-origin` | Other origins cannot embed our resources |

Why `'unsafe-inline'` for styles: Flutter's engine writes inline styles
into the DOM (the strict control run below reported `style-src-elem
inline`). Scripts allow no inline code and no `eval`; only WebAssembly
compilation (`'wasm-unsafe-eval'`, needed by CanvasKit/skwasm) and the
Google CDN that serves CanvasKit and the Firebase JS SDK
(`www.gstatic.com/flutter-canvaskit/<engine>`, `www.gstatic.com/firebasejs/<version>`).
A compromise of that CDN would compromise the web client: the same class
of risk as Hosting itself ("Why web is different"). Self-hosting CanvasKit
(`--no-web-resources-cdn`) and the Firebase SDK would remove it and is
recommended before enforcement.

### CSP compatibility evidence

A development web build (Flutter 3.41.5, CanvasKit) was served locally
with exactly the `firebase.json` headers plus a test-only `report-uri`,
and loaded in headless Chrome:

| Run | Policy | Result |
| --- | --- | --- |
| Real | as above | App rendered (welcome screen, CanvasKit, web fonts); **0 reports** |
| Control | `default-src 'self'; script-src 'self'; connect-src 'self'; font-src 'self'` | 6 reports: CanvasKit script, WebAssembly compile, CanvasKit and two font fetches, inline style; proves the reporting path works |

Not covered: Firebase Auth/Firestore/Functions endpoints and reCAPTCHA
(an unconfigured development build never loads the Firebase SDK). That is
why the CSP stays **Report-Only** until staging Hosting, with Firebase
configured, has produced clean reports (P2-4).

### Remaining web gates

| Gate | State |
| --- | --- |
| Enforce CSP (drop `-Report-Only`) after staging reports are clean; add a `report-to` endpoint | **Deferred** (P2-4): needs a deployed staging origin |
| Self-host CanvasKit and the Firebase JS SDK; then drop `www.gstatic.com` | Recommended before enforcement |
| Trusted Types | Not attempted: Flutter web's compatibility is unverified |
| Isolated app origin `app.sirfhum.com`, separate from marketing | Custom domain not attached (ENVIRONMENTS) |
| App Check on web | Production refuses to start without a reCAPTCHA site key (D-139); enforcement off |
| Private content on web | **Not planned in V1** (D-046); any future design needs its own review (Option B above) |
