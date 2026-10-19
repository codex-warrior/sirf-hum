# Threat Model

Status: **Foundation (Prompt 01); E2EE analysis added (Prompt 04); crypto-core threats added (Prompt 06); device identity added (Prompt 07, scenario table in [DEVICE-IDENTITY §9](DEVICE-IDENTITY.md#9-compromised-device-and-server-assumptions)).** A living document. Each phase that adds
data, endpoints or devices must update it. Not every threat can be
eliminated; the goal is that each one is *explicit*.

## Sensitive assets

| Asset | Sensitivity | Notes |
| --- | --- | --- |
| Messages, letters, private memories | Critical | Core intimate content |
| Photos, videos, voice recordings | Critical | Includes thumbnails and captions |
| Cryptographic keys (identity, device, content) | Critical | Compromise exposes content |
| Account credentials / auth tokens | High | Account takeover |
| Device identities | High | Impersonation of a device |
| Relationship information (who is paired with whom) | High | Itself revealing; risk in hostile environments |
| Presence information (online, in a call, location-like signals) | High | Enables stalking/monitoring |
| Operational metadata (timestamps, sizes, frequency) | Medium | Can reveal patterns |

## Trust boundaries

```text
[Person] ⇄ [Device: app + OS keystore]  ══ TB1: device / network ══  [Firebase: Auth · Firestore · Storage · Functions]
                                                                         ║ TB3: Google infrastructure & operators
[Partner's device] ═══════ TB2: between partners ═══════                 ║
                                                                      [FCM / APNs / Web Push]  [LiveKit]  TB4: third parties
```

- **TB1 Device ↔ network/server:** everything past the device is untrusted for private content.
- **TB2 Partner ↔ partner:** partners are trusted with *shared* content they
  receive, not with each other's accounts, devices or private settings.
- **TB3 Operator:** Sirf Hum staff and Google infrastructure are untrusted for content.
- **TB4 Third parties:** push services, LiveKit, crash/analytics vendors see only what we send.

## Attack surfaces

Client app (all platforms) · web origin (XSS, extensions) · Firebase Auth
flows (sign-in, recovery) · Firestore/Storage via Security Rules · callable
and HTTP Cloud Functions · LiveKit token endpoint and rooms · push payloads ·
pairing/invite flow · device-linking flow · local storage, caches, OS backups ·
logs and crash reports · CI/CD and developer credentials · third-party SDKs.

## Threat actors

| # | Actor | Example attacks | Planned mitigations | Residual risk |
| --- | --- | --- | --- | --- |
| T1 | **Compromised server** (Functions code, config) | Read data, serve malicious keys | E2EE: server never has content keys; key changes signed by identity keys; partner verification | Server can withhold/delay data, observe metadata, attempt key substitution if users don't verify |
| T2 | **Compromised database** | Dump Firestore/Storage | Ciphertext only for private content; minimised metadata | Metadata and relationship graph exposed |
| T3 | **Malicious administrator** | Browse user data, alter rules | E2EE; least-privilege IAM; audit logs; rules in source control with tests | Admin can disrupt service, view metadata |
| T4 | **Compromised device** (malware, root) | Read decrypted content, steal keys | OS keystore, app lock (future), minimal plaintext caching | Largely unmitigable: an owned endpoint sees what the user sees |
| T5 | **Stolen device** | Open app, read history | Rely on OS lock; optional app lock; remote device revocation; keys in hardware keystore | Unlocked stolen phone exposes content until revoked |
| T6 | **Compromised account** (phished credentials, SIM swap) | Sign in on attacker device | New device requires approval from an existing device / identity key; partner notified of new device; strong auth options | If recovery bypasses device approval, attacker gains future content — recovery design is critical |
| T7 | **Revoked / old device** | Continue reading after removal | Server-side revocation in rules; key rotation on revocation; FCM token removal | Content already on that device remains readable |
| T8 | **Man-in-the-middle** | Intercept/alter traffic, substitute keys | TLS; E2EE with authenticated key exchange; key-change warnings; optional verification | Users who never verify trust the key directory on first use |
| T9 | **Malicious third party** (other users, bots) | Enumerate users, spam invites, abuse endpoints | Default-deny rules, App Check (wired Prompt 02; enforcement pending rollout), rate limits, invite codes that expire, no public profiles; no Auth provider enabled before the identity phase | Determined attackers with genuine devices |
| T10 | **Abusive partner** | Monitoring presence/location, coercing access, refusing to unpair, using shared history as leverage | No partner access to the other's account/devices; either person can unpair; presence controls; no hidden tracking; considered "safety" design per feature | Coercion with physical device access cannot be solved technically; content already shared can be retained |
| T11 | **Notification leakage** | Lock-screen previews, push-provider visibility | Content-free payloads; on-device decryption only if ever enabled; per-category preferences | Notification *timing* still visible to push providers and onlookers |
| T12 | **Cloud-storage compromise** | Download media blobs | Client-side encrypted media with per-file keys; opaque object paths | File sizes and counts visible |

**Environment confusion** (a test build or deploy touching production): separate projects, no default CLI project, runtime and Functions environment guards, gated deploys (docs/architecture/ENVIRONMENTS.md).

Additional cross-cutting threats: supply-chain compromise of dependencies
(pin versions, review new SDKs, CI secret scanning); developer credential
leakage (no secrets in repo, separate prod access); logging/crash-report
leakage (`AppLogger` enforces typed fields and redacts raw strings; Crashlytics receives error types only); OS cloud backups of local databases
(exclude or encrypt local stores).

## E2EE threat analysis (Prompt 04)

Against the recommended design in [E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md):
MLS couple group of devices, Person Identity Keys (PIK), web v1 without
private content. "Not implemented" applies to every mitigation below.

**What E2EE cannot protect against:**
- a compromised endpoint (malware, a malicious OS, a modified app) sees
  plaintext while the user reads it;
- a recipient can always copy what they can read;
- metadata (who, when, how often, how big, from where) remains visible to
  the server and Google;
- a malicious *code update* is a compromised endpoint.

| # | Threat | Security objective | Mitigations | Residual risk | Assumptions |
| --- | --- | --- | --- | --- | --- |
| E1 | Compromised Firebase project | Server can't read content or impersonate devices | MLS ciphertext only; PIK-signed device certificates validated by every device; partner verification; key-change warnings | Metadata exposure; denial of service; withholding/reordering messages; tricking unverified (TOFU) pairs at first contact | Users verify or heed key-change warnings |
| E2 | Database / Storage leak | Leak reveals no content | Ciphertext only; opaque IDs; padded sizes; no plaintext thumbnails | Relationship graph, timing, sizes | Crypto primitives sound |
| E3 | Malicious administrator | Same as E1 | Same as E1; least-privilege IAM; WIF deploys; audit logs | Same as E1; an admin could ship malicious **web** code (hence web v1 has no private content) | Mobile binaries are store-signed and not replaceable by an admin alone |
| E4 | Compromised Cloud Function | Function can't decrypt or add members | Functions never hold keys; membership changes require Commits signed by member devices with valid certificates | Can disrupt invites/fan-out; can leak metadata | — |
| E5 | Man-in-the-middle | No interception or key substitution | TLS; end-to-end authenticated MLS; out-of-band PIK verification | First-contact TOFU if users never verify | — |
| E6 | Stolen unlocked device | Limit exposure; enable remote cut-off | OS lock; optional app lock (auth-bound key); remote Remove from another device | Content readable until removal is synced; previously displayed content | Owner notices and revokes |
| E7 | Compromised user account (Firebase) | Account takeover ≠ content access | New devices need PIK certification (existing device or recovery key); partner sees key changes | Metadata access; social engineering of the partner | Recovery key kept secret |
| E8 | Malicious / compromised partner device | Limit to what that partner legitimately sees | Partner can only read shared content; can't add devices for you (needs your PIK); roster changes visible; instant unpair | Partner can copy shared content; a compromised partner device leaks shared content until revoked | — |
| E9 | Revoked / obsolete device | No future content | MLS Remove → new epoch (spike-verified online/offline); server denies; tokens/KeyPackages deleted; Updates for PCS | Already-decrypted content stays | Remove commit reaches the group |
| E10 | Replay, reorder, duplication | Accept each message once, authentically | MLS generation keys deleted after use (spike-verified replay rejection); `clientMessageId` dedupe; per-epoch commit ordering | Message *withholding* by the server is undetectable without extra mechanisms (gap detection **UNRESOLVED**). **Prompt 05 finding:** in both OpenMLS and mls-rs a *rejected* forged copy consumes the message key, so an injector (server or member) can make one genuine message undecryptable (DoS); mitigated by checkpoint + rollback on rejection (tested) | — |
| E11 | Push notification leakage | No content to push providers or lock screens | Data-only, content-free payloads; generic local text; previews off | Notification timing reveals activity | — |
| E12 | Metadata exposure | Minimize | Opaque IDs, padding, short retention, minimal AAD | Inherent: timing, sizes (bucketed), device counts, pairing | — |
| E13 | Account recovery abuse | Recovery can't be hijacked | No escrow; recovery key required; new-device notifications to all devices and the partner; re-auth | Stolen recovery key + account = takeover | User stores the key safely |
| E14 | Malicious application update | Detect/limit | Store signing; reproducible builds (future); minimal dependencies in the crypto core; protected CI/deploy | A malicious signed update is a compromised endpoint: E2EE can't stop it | Store accounts and signing keys protected (ACCOUNT-OWNERSHIP) |
| E15 | Compromised browser | — | Web v1: no private content | Account/settings session exposure | — |
| E16 | Malicious browser extension | — | Web v1: no private content | Same | — |
| E17 | XSS / browser storage compromise | — | Web v1: no private content; CSP/Trusted Types before any future web E2EE | Same | — |
| E18 | Loss of all trusted devices | Honest outcome | Recovery key (opt-in); otherwise new identity, visible to the partner | Without recovery, history is lost; this must be stated plainly | — |
| E20 | Malicious MLS input (server, network or member): oversized, malformed, forged, replayed, from outsiders | Reject without crashing, exhausting memory or damaging valid state | Size limits before parsing; OpenMLS validation; checkpoint/rollback on every rejection; panics caught at the ABI; boundary credential validation on every receiver (Prompt 06, tested) | Parser bugs in OpenMLS within the limits (three 2026 advisories fixed in 0.9.1; RustSec monitored by `cargo audit`) | OpenMLS 0.9.1 parsers behave within limits |
| E21 | Local crypto-state theft or tampering (backup extraction, file edit, record swap) | Files reveal nothing; tampering is detected | XChaCha20-Poly1305-sealed records with name/kind-bound AAD; fail closed on any mismatch; app-private directory | The store key comes from the platform key store (Android Keystore-wrapped / iOS `ThisDeviceOnly` Keychain, Prompt 07); a process-level attacker on a rooted/jailbroken device can still use it while the app runs | Platform keystore protects the store key at rest |
| E22 | Local rollback: an older copy of the whole state directory is restored | Old state can't be resurrected to reuse keys | None yet: no monotonic counter or hardware binding. Restored state cannot regain *server* trust (status server-side; IDs/keys indexed forever) | Open (D-079, MULTI-DEVICE-TRUST §10). An attacker with file access could restore an older epoch's state. The trust epoch (D-083) makes a device refuse an *older server view* than it has seen, but rolls back with the files. MLS removal still blocks reading new epochs (tested: restored pre-removal state cannot decrypt) | — |
| E24 | Password/account compromise used to add a device | Account access ≠ device trust | Proof of possession activates only an account's first device, once ever; later devices need an approval statement signed by an active device's PIK or the recovery key; comparison code on both screens; rate limits (Prompt 08, D-075) | The attacker can register pending devices (cap 3), request a delayed identity reset that any trusted device can cancel (D-082), and try to trick the owner into approving; the code comparison is the defence. A password alone can no longer revoke devices (D-081) | Owner compares codes; a trusted device cancels unwanted resets |
| E25 | Lost / stolen / compromised device keeps acting | Revocation is enforced server-side | A trusted device signs the revocation (D-081, verified against stored certificates, evidence kept); revoked devices cannot approve, revoke, cancel a reset, register recovery keys or use approvals signed before revocation (checked at submission); offline devices cannot create trust on reconnect | Content already on the device stays readable there; revocation does not wipe remotely; no cascade to devices it approved earlier (lineage recorded); **only device stolen and no recovery key:** nothing can sign its revocation and its holder could cancel an identity reset (D-081 residual) | Owner keeps a recovery key or a second device |
| E26 | Replayed, forwarded, stale or forged approvals and recovery statements | Each authorization counts once, for one device, one account, before it expires | Domain-separated statements binding account, both identities, single-use challenge, expiry and version; requests consumed on first use; shared failure budget (D-075–D-077) | Rate limits are per account, not global | — |
| E27 | Loss of the recovery key or of every trusted device | Honest outcome | Single-use recovery key (public half only on the server); recovery restores device trust, never history | Without devices or key: a delayed (7-day), cancellable identity reset to a NEW identity that partners must re-verify (D-082); history is never recoverable; reset notifications are not built yet | User keeps the key safe |
| E28 | Malicious server adds or hides devices in an account's device list | A device trusts only what signed evidence proves | Lineage verified on device in Rust from the partner-verified root (D-084); client fails closed if the server lists an active device the chain does not prove; server trust epoch refused if it goes backwards (D-083) | The server can withhold revocations or new links (omission) and controls ordering; the root's identity rests on partner verification (D-064) | Partner verifies the root PIK |
| E29 | Forged, replayed or cross-protocol revocation or reset-cancel statements | Each counts once, for one device, one account | Domain-separated v1 statements binding account, both certificates, reason, single-use challenge bound to the signer, expiry; golden vectors across TS/Rust/Dart (D-081, D-082) | — | — |
| E30 | Revoked device re-mints a trusted identity with its retained PIK | A revoked device gains nothing | Trust unit is the exact certificate; each PIK pinned to one device ID; revoking a device revokes its PIK permanently; lineage only from an anchored root (D-085, Prompt 10, tested) | The server controls the ordering of statements in a lineage (E28) | Partner verifies the root PIK |
| E31 | Server moves, relabels or rewrites a message (other conversation, message ID, sender device/account, epoch, version) | Detected on receipt | Routing fields in MLS AAD built by Rust and compared with the envelope inside the rollback transaction; MLS group ID = conversation ID; sender account checked against the verified lineage (D-089, tested) | The server can still drop or delay messages (E10) | — |
| E32 | Concurrent or forged commits fork the conversation | One agreed epoch sequence | Staged commits (D-087); create-only `commits/{epoch}` written with the epoch move (D-088); every device validates the winning commit and fails closed (`stateDiverged`) if it cannot | A winning but invalid commit stalls the conversation until re-provisioning (deferred) | — |
| E33 | Revoked device keeps receiving new messages | No new content after the sender learns of the revocation | Senders refuse to encrypt to a roster with an untrusted device; Remove commit; rules refuse its writes (Prompt 10) | Firebase reads are per account: until the Remove, a revoked device with its account's session can decrypt messages from devices that have not refreshed lineage yet (no push signal until Prompt 11) | Peers refresh lineage on resume |
| E34 | Plaintext at rest through message history | History unreadable off-device; no plaintext files | Sealed records (kind 5) under the slot's platform store key, atomic with MLS state, no plaintext fallback; name-bound AAD stops record swaps (D-090, tested) | Rooted device while the app runs (E21); restored old files not detected (E22) | — |
| E23 | Secret leakage through logs, errors or the Dart boundary | No secrets outside the Rust core | No logging in the core (CI scan + clippy deny); OpenMLS debug features banned; error codes only; no export/dump function in the ABI; redacted Debug/toString; native buffers wiped | Decrypted plaintext in the Dart heap can't be reliably wiped (GC) | — |
| E19 | Abusive partner seeking access after unpairing | No access after unpairing | Unilateral instant unpair; partner leaves removed; rules cut access; new group on re-pair; roster changes visible while paired | Content already received by the abuser stays with them; coercion with physical access can't be solved technically | — |

## Assumptions

- Device OS and hardware keystores are not compromised (outside T4).
- Established cryptographic libraries are correctly implemented.
- Firebase enforces Security Rules as documented.
- Users keep their device lock enabled (we encourage but cannot enforce).

## Unresolved risks (tracked)

1. Account recovery vs. E2EE trade-off. Designed in Prompt 04 (recovery key opt-in, no escrow; RECOVERY-AND-REVOCATION); offering a history archive is still undecided.
2. Web as a device class. Prompt 04 recommends no private content on web v1 (WEB-SECURITY); needs product approval.
3. Shared history after unpairing — product/legal decision pending.
4. Metadata minimisation — schema-level decisions pending.
5. Abuse/safety design for presence and location-like features — per-feature.
6. No independent security review has been performed.
7. MLS library: OpenMLS 0.9.1 selected (D-054, medium confidence). The SRLabs review covered an earlier commit and excluded providers; the delta review is pending. *(Prompt 04's "no audit found" was corrected in Prompt 05.)*
8. No post-quantum protection in standard MLS ciphersuites ("harvest now, decrypt later").
9. Server message *withholding* detection (gap detection) not designed.
10. The platform key store (Prompt 07, D-066) is unreviewed, and device activation is not deployed (needs Blaze, D-025). No real user's content until both are resolved and reviewed.
13. Device registration abuse: rate limits and a pending cap exist since Prompt 08 (D-077); deployment needs Blaze.
14. Multi-device trust, revocation and recovery (Prompts 08–09) are unreviewed. Identity reset (D-082) needs push notifications before production; local rollback protection is open (D-079, partly addressed by D-083); peers rely on the server for evidence completeness and ordering (D-084).
11. Local whole-state rollback is undetected (E22).
12. The Prompt 06 crypto core (credential policy, record format, FFI, rollback) is unreviewed.
