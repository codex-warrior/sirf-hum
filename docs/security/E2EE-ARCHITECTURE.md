# E2EE Architecture

Status: **Design (Prompt 04, 2026-10-16). Nothing here is implemented in the
app.** Sirf Hum is **not** end-to-end encrypted and must not say it is.

Companion documents:
[KEY-MANAGEMENT](KEY-MANAGEMENT.md) ·
[PAIRING-AND-DEVICE-TRUST](PAIRING-AND-DEVICE-TRUST.md) ·
[RECOVERY-AND-REVOCATION](RECOVERY-AND-REVOCATION.md) ·
[WEB-SECURITY](WEB-SECURITY.md) ·
[CRYPTOGRAPHIC-BOUNDARIES](../architecture/CRYPTOGRAPHIC-BOUNDARIES.md) ·
[E2EE-TEST-PLAN](../testing/E2EE-TEST-PLAN.md) ·
[THREAT-MODEL](THREAT-MODEL.md) · requirements in
[E2EE-REQUIREMENTS](E2EE-REQUIREMENTS.md).

## Labels

Every important conclusion carries one label:

- **APPROVED**: explicitly established by the product owner.
- **RECOMMENDED**: technically justified proposal awaiting approval.
- **UNRESOLVED**: evidence or a decision is still required.

No library or protocol in this document is described as production-ready.
"Evidence" means a source was checked on 2026-10-16. Claims without a source
are marked *unverified*.

## 1. Summary

| Layer | Conclusion | Label |
| --- | --- | --- |
| Goal | Private content encrypted on the sender's device and readable only by authorized devices; the server never holds plaintext or content keys | **APPROVED** (Prompt 01) |
| Protocol specification | **MLS, RFC 9420**: one MLS group per couple whose members are *devices* | **APPROVED direction** (product owner, Prompt 05; D-042) |
| Ciphersuite | `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` (RFC 9420 mandatory-to-implement) | **RECOMMENDED** |
| Post-quantum | Not available in standard MLS ciphersuites; Signal has it (PQXDH + SPQR) | **APPROVED**: not a V1 launch blocker; crypto agility + migration path required (D-050) |
| Library | **OpenMLS 0.9.1** selected for development, **medium confidence**; mls-rs 0.56.0 kept as tested fallback ([MLS-DECISION](MLS-DECISION.md)) | **RECOMMENDED (D-054)**; production conditional on the review gates |
| Platform integration | One small Rust crate wrapping OpenMLS, bridged to Dart with flutter_rust_bridge; built for Android, iOS and wasm32 | **RECOMMENDED**, not yet prototyped through Flutter |
| Key storage (mobile) | Encrypted local store whose wrapping key is non-exportable in Android Keystore / iOS Keychain | **RECOMMENDED** ([KEY-MANAGEMENT](KEY-MANAGEMENT.md)) |
| Key distribution | Device KeyPackages in Firestore, authenticated by a per-person identity key; partner identity verified out of band | **RECOMMENDED** ([PAIRING](PAIRING-AND-DEVICE-TRUST.md)) |
| Backend authorization | Firestore/Storage rules and Functions authorize *access to ciphertext*; they never decrypt | **APPROVED** principle; rules **UNRESOLVED** until designed per feature |
| Web | **No private content on web in the first release** (restricted capability) | **APPROVED direction** (Prompt 05; D-046) ([WEB-SECURITY](WEB-SECURITY.md)) |
| Recovery | Add a device from an existing device; optional user-held recovery key; no Sirf Hum escrow | **RECOMMENDED** ([RECOVERY](RECOVERY-AND-REVOCATION.md)) |
| Media | Random per-object key; libsodium `crypto_secretstream_xchacha20poly1305`; key sent inside an MLS message | **RECOMMENDED**, library binding **UNRESOLVED** |
| Independent review | Required before any E2EE claim | **APPROVED** (Prompt 01) |

## 2. Identity model

```text
PERSON ──► ACCOUNT ──► DEVICES ──► CRYPTOGRAPHIC IDENTITY ──► COUPLE ──► PRIVATE CONTENT
```

| Layer | Identifier | Who issues it | What it proves | Never treat as |
| --- | --- | --- | --- | --- |
| Person | none (a human) | — | — | — |
| Account | Firebase Auth `uid` | Firebase Auth | A sign-in happened; authorizes **server** access | A cryptographic identity; proof a device is trusted |
| Person identity | **Person Identity Key (PIK)**: Ed25519 signing key pair, one per person | Generated on the person's first device | That a device belongs to this person: the PIK signs each device credential | Something the server can create or replace |
| Device | `deviceId` (random 128-bit) + device signing key (MLS leaf signature key) + MLS encryption keys | Generated on the device | Which device sent a message (MLS sender authentication) | Shared between devices |
| Device authorization | **Device certificate**: PIK signature over (deviceId, device signature public key, created time) | The person's PIK | This device was approved by its owner | A Firestore flag |
| Couple | `coupleId` (random, opaque) | Server, at pairing | That two accounts agreed to pair (server-side authorization) | Cryptographic trust; a key; a secret |
| Couple cryptographic state | One **MLS group** whose members are the devices of both people | Created by a device of the inviter | Authenticated, consistent roster + shared epoch secrets | Access to the partner's account or devices |
| Conversation | MLS group ID (random 32 bytes) | Creating device | Which group a ciphertext belongs to | An authorization token |
| Personal state | A second MLS group per person containing only **their own** devices | Person's first device | Private-to-self sync (drafts, settings, personal vault) | Visible to the partner |

Rules (**RECOMMENDED**):

1. **Couple membership is not cryptographic trust.** Trust comes from
   verified PIKs and device certificates checked by every member's MLS
   authentication-service callback.
2. **Authenticated is not authorized.** A signed-in `uid` lets a client read
   only the documents rules allow, and those contain ciphertext.
3. **The partner never gets your PIK private key**, account credentials or
   device keys. Pairing exchanges *public* identity only.
4. **A member is accepted only if:**
   - its MLS credential carries a device certificate signed by one of
     exactly **two** PIKs, the verified pair;
   - the device ID is not revoked in the signed roster history;
   - the leaf signature key matches the certificate.

   Anything else is rejected, including any third person or a device the
   server inserted.

## 3. Data flow and trust boundaries

```text
 Alice's phone (trusted for Alice)          Firebase (untrusted for content)            Bob's phone (trusted for Bob)
┌───────────────────────────────┐    TLS   ┌──────────────────────────────────┐   TLS  ┌───────────────────────────────┐
│ UI (Flutter)                  │          │ Auth: uid sessions               │        │ UI (Flutter)                  │
│   │ plaintext                 │          │ Firestore:                       │        │   ▲ plaintext                 │
│ lib/security (Dart) ──FFI──►  │  ──────► │   device records, PIK publics,   │ ─────► │ lib/security ◄─FFI── Rust     │
│   Rust crypto core (OpenMLS)  │ cipher-  │   KeyPackages, MLS handshake log,│ cipher-│   core (OpenMLS) decrypts     │
│   encrypts; keys in keystore  │  text    │   MLS ciphertext, delivery meta  │  text  │   keys in keystore            │
│   EncryptedEnvelope only ───► │          │ Storage: encrypted media blobs   │        │                               │
│ lib/infrastructure (Firebase) │          │ Functions: invites, fan-out, TTL │        │ lib/infrastructure            │
└───────────────────────────────┘          │ FCM: content-free wake-ups       │        └───────────────────────────────┘
        ▲ TB1                              └──────────────────────────────────┘                 ▲ TB1
        └──────── TB2: partners verify each other's PIK out of band (QR / safety number) ───────┘
```

- **TB1 Device ↔ everything else.** Plaintext and private keys exist only
  inside the device boundary (Rust core + platform keystore). In Dart,
  plaintext exists only in `lib/security` and the UI that renders it.
- **TB2 Partner ↔ partner.** Partners trust each other's *verified* PIKs for
  shared content only.
- **TB3 Operator/Google.** Sees ciphertext and the metadata listed in §9.
- **TB4 Push providers (FCM/APNs/Web Push).** See only content-free payloads.

## 4. Candidate evaluation

Evidence was gathered on 2026-10-16 from GitHub repository metadata, project
documentation, CI configuration and published audits. **Sources** are at the
end of this section.

### 4.1 Protocol families

| Property | Signal (X3DH/PQXDH + Double Ratchet + SPQR; Sesame for multi-device) | Olm + Megolm (Matrix) | MLS (RFC 9420) |
| --- | --- | --- | --- |
| Standardization | Published specifications by Signal; not an IETF standard | Matrix specification | **IETF Proposed Standard, RFC 9420 (2023)** |
| Forward secrecy | Yes (per message) | Olm yes; Megolm partial (ratchet only forward; keys shareable) | Yes, per epoch and per-message within an epoch (secret tree deletion) |
| Post-compromise security | Yes (DH ratchet) | Olm yes; **Megolm no** | Yes, via Update/Commit (TreeKEM) |
| Post-quantum | **Yes**: PQXDH (2023) + SPQR "Triple Ratchet" (Oct 2025) | No | Not in standard ciphersuites (PQ ciphersuites are drafts, *unverified* status) |
| Asynchronous | Yes (prekeys) | Yes (one-time keys) | Yes (KeyPackages) |
| Multi-device | Sesame: pairwise sessions per device pair; roster is the *application's* problem | Pairwise Olm per device + Megolm; device trust via Matrix cross-signing (outside the crypto library) | **Devices are group members**; the protocol itself gives an authenticated, consistent roster (epoch authenticator) |
| Device add/remove | Application builds/destroys sessions; no protocol-level roster agreement | Application-level; known historic attack surface | Protocol-level Add/Remove commits; removed members lose future epoch secrets |
| Key verification | Safety numbers (application) | Cross-signing + SAS (Matrix spec) | Application authentication service validates credentials (RFC 9420 §5.3) |
| Replay protection | Yes | Yes | Yes (generation-indexed keys, deleted after use) |
| Formal analysis | Extensive academic literature; Cryspen analysis of SPQR (per Signal) | 2024 mechanized analysis ("Matrix Reloaded") | Multiple analyses of TreeKEM; Cremers et al. 2025 covers RFC 9420 additions |
| Relevant known failures | — | 2022: practical attacks by a malicious server against Matrix/Element, incl. device-list trust (Albrecht et al.) | Implementation advisories (OpenMLS 2025, below) |

Why the multi-device roster matters most for Sirf Hum. Every privacy
property here depends on *which devices* receive keys. Matrix's 2022
vulnerabilities show what happens when a server-influenced device list is
trusted, which is exactly the threat we face (a compromised Firebase project).
MLS makes the roster part of the authenticated group state: all members
compute the same epoch authenticator, so a server cannot show different
rosters to different devices without detection. The Signal and Olm families
leave that agreement to application code, which we would have to design: a
custom protocol layer, which our rules forbid.

### 4.2 Concrete implementations

| Implementation | Protocol | License | Maintenance (GitHub, 2026-10-16) | Independent review evidence | Android / iOS | Browser (wasm) | Flutter path | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **libsignal** (Signal) | Signal | **AGPL-3.0** | Very active; v0.105.1 released 2026-10-15 | Signal's own; formal work cited for SPQR | Java/Android, Swift (official) | **No**: TypeScript is a Node add-on; no browser/wasm in README | Would need platform channels to Java/Swift; no web | **Rejected for v1**: README says "use outside of Signal is unsupported"; "APIs subject to change without notice"; AGPL would require open-sourcing the app (licensing **UNRESOLVED** only if the owner wants an AGPL client); no web |
| libsignal_protocol_dart (Mixin) | Signal (unofficial Dart port) | GPL-3.0 | Last push 2026-06-21; no releases | **None found** | Dart | Dart | Direct | **Rejected**: unofficial re-implementation, no review found, GPL |
| **vodozemac** (Matrix) | Olm + Megolm | Apache-2.0 | Active; 0.11.1 released 2026-09-30 | **Least Authority audit (report dated 2022-03-30)**: 10 issues (A–J) + suggestions, fixed per Matrix; 2024 low-severity timing fix (<0.7.0) | Rust; used by Element mobile via matrix-rust-sdk | **Yes**: Element Web uses it via wasm (matrix-sdk-crypto-wasm) | flutter_rust_bridge, or famedly's Dart binding (AGPL-3.0) | **Fallback candidate**: audited and deployed on web, but device trust/roster lives in matrix-sdk-crypto (Matrix-specific); using vodozemac alone means designing our own roster protocol |
| **OpenMLS** | MLS | **MIT** | Active; 0.9.1 on crates.io 2026-10-07; CI runs **native and wasm32 tests**, fuzzing and an interop job | **SRLabs Security Assurance Assessment v1.2 (2026-03-11)** of core crates at commit `a3402f2`; providers out of scope (*Prompt 04 wrongly said none was found; corrected in Prompt 05*). Indirect: NCC Group review of libxmtp. 5 advisories, all fixed by 0.9.1 | Rust; production use via **Wire core-crypto (pinned OpenMLS fork)** | **Yes in CI** (`tests.yml` wasm job; `openmls-wasm` crate) | flutter_rust_bridge or own C ABI | **Selected for development (D-054)** |
| **mls-rs** (AWS Labs) | MLS | Apache-2.0 / MIT | Active (pushed 2026-10-15); releases via crates.io | lib.rs listing: conformance-validated but **"not yet received a full security audit by a 3rd party"** | Rust; has FFI bindings (*unverified* for our targets) | *unverified* | flutter_rust_bridge | **Alternative candidate** |
| Wire core-crypto | MLS (OpenMLS fork) + Proteus | **GPL-3.0** | Active | Wire's own; *unverified* | Yes (Wire apps) | Yes (Wire web) | Kotlin/Swift/TS bindings | **Rejected**: GPL; tightly coupled to Wire (X.509/E2EI, Proteus) |
| Build from primitives (libsodium, Web Crypto) | — | — | — | — | — | — | — | **Rejected**: would be a custom protocol |

### 4.3 Recommendation

- **Protocol: MLS (RFC 9420). RECOMMENDED.**
  - Standardized, formally analysed core.
  - Forward secrecy and post-compromise security.
  - A protocol-level authenticated device roster, which is the property our
    threat model most needs.
  - Efficient add/remove of devices.
  - "Two people × a few devices" is a small group, well inside MLS' design
    range.
- **Accepted cost:** no standardized post-quantum MLS ciphersuite yet. Content
  recorded today could be decrypted by a future quantum adversary
  ("harvest now, decrypt later"). Signal is ahead here. Whether to accept this
  for v1 is **UNRESOLVED (owner decision)**, with a tracked plan to adopt PQ
  ciphersuites when they are standardized and implemented.
- **Library: OpenMLS selected in Prompt 05 (D-054, medium confidence); see [MLS-DECISION](MLS-DECISION.md).** Prompt 04 reasons it led:
  - permissive license;
  - active maintenance;
  - wasm32 tests in its own CI;
  - production use through Wire's fork;
  - a responsive advisory process;
  - the Prompt 04 spike (§12) passed natively and on wasm32.

  Before a decision:
  1. Search for, or commission, an independent security review of the exact
     OpenMLS version and crypto provider we ship.
  2. Prototype through flutter_rust_bridge on Android, iOS and Web.
  3. Decide the storage provider (encrypted SQLite) and audit its use.
  4. Compare once more with mls-rs on the same criteria.
- **Crypto provider (UNRESOLVED):** OpenMLS ships `openmls_rust_crypto`
  (RustCrypto crates) and `openmls_libcrux_crypto` (formally verified
  primitives from Cryspen). Prefer libcrux if it supports our ciphersuite on
  all targets (*unverified*).
- **Never enable** OpenMLS' `crypto-debug` / `content-debug` features: they
  log secrets and plaintext.

Sources (accessed 2026-10-16):
- Repository metadata (license, archived, last push, latest release) from the
  GitHub API for each repository named in §4.2.
- [libsignal README](https://github.com/signalapp/libsignal): AGPL-3.0, "Use
  outside of Signal is unsupported", bindings.
- [Signal SPQR announcement](https://signal.org/blog/spqr/) ·
  [Least Authority vodozemac audit](https://leastauthority.com/static/publications/LeastAuthority-Matrix_vodozemac_Final_Audit_Report.pdf) ·
  [Matrix audit announcement](https://matrix.org/blog/2022/05/16/independent-public-audit-of-vodozemac-a-native-rust-reference-implementation-of-matrix-end-to-end-encryption/) ·
  [libolm deprecation](https://matrix.org/blog/2024/08/libolm-deprecation/)
- [Albrecht et al., Practically-exploitable Cryptographic Vulnerabilities in Matrix (ePrint 2023/485)](https://eprint.iacr.org/2023/485) ·
  [The Matrix Reloaded (arXiv 2408.12743)](https://arxiv.org/pdf/2408.12743)
- [Cremers et al., ePrint 2025/229 (RFC 9420 TreeKEM analysis)](https://eprint.iacr.org/2025/229) ·
  [Alwen et al., ePrint 2019/1189](https://eprint.iacr.org/2019/1189)
- OpenMLS CI: `.github/workflows/tests.yml` (wasm job) and `build.yml` at
  `main`; [OpenMLS advisories (GitLab advisory DB)](https://advisories.gitlab.com/pkg/cargo/openmls/) ·
  [NCC Group: XMTP MLS implementation review](https://www.nccgroup.com/research/public-report-xmtp-mls-implementation-review/)
- Wire `core-crypto` `Cargo.toml` (OpenMLS fork dependency) ·
  [Wire MLS rollout](https://wire.com/en/blog/redefining-secure-collaboration-with-mls)
- [mls-rs on lib.rs](https://lib.rs/crates/mls-rs) (audit statement)

## 5. Group topology

**RECOMMENDED:**

| Group | Members | Carries |
| --- | --- | --- |
| **Couple group** (one per active pairing) | All verified devices of both partners | Messages, shared Moments, letters, Future items, media keys, call key material |
| **Personal group** (one per person) | That person's own devices only | Private-to-self data: drafts, personal vault, settings that must stay private from the partner, device-roster announcements |

- A new pairing always creates a **new** couple group. Groups are never
  reused after unpairing.
- One couple group, not one group per feature. Different content types are
  application message kinds inside the group. This keeps the roster single
  and auditable.
- Calls derive keys from the couple group with the MLS exporter (§11), not a
  separate key exchange.

## 6. Messaging encryption model (future; not implemented)

**Protocol-managed (defined by RFC 9420; we do not invent these):**
- `PrivateMessage` framing;
- group ID;
- epoch;
- content type;
- sender leaf;
- generation;
- reuse guard;
- encrypted sender data;
- AEAD ciphertext and signature.

**Application-defined (inside the MLS application plaintext):**
`SirfHumPayload v1` = {
- `schemaVersion`;
- `kind` (text, reaction, letter, media_ref, plan, …);
- `clientMessageId` (random 128-bit);
- `sentAt` (sender clock, display only);
- body fields per kind;
- optional `replyTo`.

**Application metadata authenticated but not encrypted:** the MLS
`authenticated_data` field carries only the `schemaVersion` and a coarse
`kind` class needed for routing. **RECOMMENDED** default: put nothing in AAD
unless routing requires it.

| Concern | Design | Label |
| --- | --- | --- |
| Session establishment | Joining the couple group via Welcome (pairing or device add) | RECOMMENDED |
| Sender authentication | MLS signature by the sender's leaf key + credential chain to the sender's PIK | RECOMMENDED |
| Recipient selection | Implicit: every current group member. No per-recipient choice exists, so the server cannot add a recipient without a visible, authenticated Commit | RECOMMENDED |
| Encryption | MLS application message under the current epoch | RECOMMENDED |
| Message identity | `clientMessageId` inside ciphertext (dedupe across retries) + server document ID (transport only) | RECOMMENDED |
| Replay | MLS rejects reuse of a (sender, generation) key; the spike verified replay rejection. The app also drops duplicate `clientMessageId` | RECOMMENDED |
| Ordering | Handshake messages (Commits) must be totally ordered per group: Firestore create-if-absent on `groups/{g}/epochs/{n}` ("first commit for epoch n wins"; losers re-base). Application messages may arrive out of order within the sender-ratchet tolerance. Display order uses sender time with server sequence as a tie-break; neither is security-relevant | RECOMMENDED; tolerance values UNRESOLVED |
| Offline delivery | Ciphertext stays in Firestore until every member device that existed at send time acknowledges it, or until the retention TTL (UNRESOLVED) | RECOMMENDED |
| Retries | Same ciphertext and `clientMessageId` re-sent; never re-encrypted under a new epoch silently | RECOMMENDED |
| Acks | Per-device delivery state (non-secret metadata). Read receipts are encrypted application messages if offered | RECOMMENDED |
| Past-epoch messages | Keep a small window of past epoch secrets to decrypt late messages (OpenMLS `max_past_epochs`); larger windows weaken forward secrecy | Window size UNRESOLVED |
| Key/roster changes | Every Add/Remove/Update is a Commit visible to all members; the UI announces roster changes ("Bob added a device") | RECOMMENDED |
| Failure | See §10. Never show fake content; never bypass verification | APPROVED principle |

## 7. Media encryption model (future; not implemented)

| Topic | Design | Label |
| --- | --- | --- |
| Key strategy | Fresh random 256-bit key per object (photo, video, voice note, letter attachment, vault file), from the OS CSPRNG via the crypto library | RECOMMENDED |
| Construction | **libsodium `crypto_secretstream_xchacha20poly1305`**: designed for chunked streams; per-chunk authentication; a FINAL tag detects truncation; 24-byte header; rekey tag available. libsodium had a published audit of v1.0.12/1.0.13 (Matthew Green, 2017, sponsored by PIA; no critical findings). No custom chunking scheme | RECOMMENDED |
| Binding | Which binding provides secretstream on Android, iOS and Web (libsodium via `sodium`/`sodium_libs` with sodium.js on web, or a Rust binding inside the crypto core) | **UNRESOLVED**; prototype and review needed |
| Nonces | Managed by secretstream (header + internal counter); never chosen by app code | RECOMMENDED |
| Chunk size | Fixed (e.g. 64 KiB), so resumable uploads align to chunk boundaries | Value UNRESOLVED |
| Authenticated metadata | Per-chunk additional data = (`objectId`, `schemaVersion`) so chunks can't be moved between objects | RECOMMENDED; needs crypto review |
| Key delivery | `media_ref` MLS application message = {`objectId`, storage path, key, secretstream header, plaintext SHA-256, ciphertext size, MIME class, encrypted thumbnail ref} | RECOMMENDED |
| Upload | Encrypt on device → resumable upload of ciphertext to Storage at an opaque random path → send `media_ref` | RECOMMENDED |
| Download | Fetch ciphertext → stream-decrypt; any chunk failure aborts and discards partial plaintext | RECOMMENDED |
| Thumbnails / previews | Generated **on device**, encrypted as separate objects with their own keys. The server never generates or sees thumbnails. Notification previews never include media | RECOMMENDED |
| Size leakage | Pad ciphertext to size buckets to blur exact sizes | Scheme UNRESOLVED (needs review) |
| Local cache | Ciphertext on disk is fine; decrypted cache only inside app-private storage, excluded from OS backups, evicted on revoke/logout | RECOMMENDED |
| Deletion | Delete the Storage object + send an encrypted `delete` message. **Limit:** devices that already decrypted or exported the content can keep it | RECOMMENDED; limit documented |
| Sharing with new devices | New devices get media keys only for messages they can read (MLS gives no history). History transfer is in [RECOVERY](RECOVERY-AND-REVOCATION.md) | RECOMMENDED |
| Key rotation | Media keys are per object and never rotated. To revoke access, delete the object, or re-encrypt it under a new key and send a new `media_ref` | RECOMMENDED |
| Large files | Chunked secretstream supports large files; very long videos may need multiple streams | Specialist review **UNRESOLVED** |

## 8. Firebase boundary

| Component | Responsibility | Never |
| --- | --- | --- |
| Firebase Auth | Account sessions (`uid`), server-side authorization | Decides cryptographic trust |
| Firestore | Device records, public PIKs + device certificates, KeyPackages, ordered MLS handshake log, MLS ciphertext, delivery metadata, invites (hashed tokens) | Plaintext private content; private keys |
| Cloud Storage | Encrypted media blobs at opaque paths | Plaintext media or thumbnails |
| Cloud Functions | Invite issue/redeem, pairing state, FCM fan-out, retention cleanup, rate limits (needs Blaze) | Content keys; decryption; device trust decisions |
| FCM | Content-free wake-ups | Message text, names, media |
| App Check | Raises the cost of non-genuine clients | Authorization, encryption |
| Security Rules | Who may read/write which ciphertext and metadata documents; append-only handshake log; first-commit-wins per epoch | Confidentiality (rules don't protect against the operator) |
| Device crypto core | All encryption, decryption, signing, key generation, credential validation | Trusting server-supplied membership without validating credentials |

Firestore and Storage stay **deny-by-default** until each feature's rules are
designed and tested (**APPROVED**, D-019). This prompt changes no rules.

### What the backend can see (metadata)

Visible by design:
- that two accounts are paired;
- the number of devices and their opaque IDs;
- public keys;
- MLS group ID, epoch numbers and sender leaf index (the sender identity
  inside `PrivateMessage` is encrypted, but the uploading `uid`/device is
  visible to the server);
- message and handshake timestamps, sizes (padded), frequency;
- FCM tokens;
- IP addresses (Google);
- media object sizes (bucketed) and counts.

E2EE **does not** hide timing, device, delivery or relationship metadata.
Minimization (padding, coarse timestamps, short retention) reduces it but
doesn't remove it.

## 9. Notifications

**RECOMMENDED:**
- **Payload:** data-only FCM message `{ "t": "new", "g": <opaque short group ref>, "s": <server seq> }`. The visible notification text is
  generic and local: "You have something new from your person". It never
  carries a name, preview, emoji from the message, or media.
- **On-device previews:** off by default; **UNRESOLVED**. They require the
  iOS Notification Service Extension / Android background decryption, keys
  available after first unlock, and a review. If ever enabled, decryption
  happens only on the device.
- **Tokens:** stored on the device record. Replaced on token refresh, deleted
  on device revocation, logout and unpairing.
- **Deep links:** opaque routes (`/together`, `/moments/<opaqueId>`) only.
- **Quiet hours and batching:** applied server-side using collapse keys;
  preferences are non-secret settings.
- **Retention:** delivery metadata TTL **UNRESOLVED** (shortest workable).

## 10. Failure behaviour

| Situation | Behaviour (never fake content, never skip verification) |
| --- | --- |
| Missing key / unknown epoch | Keep the ciphertext and retry after syncing the handshake log. If it still fails, show "This message couldn't be opened on this device." |
| Invalid key / bad credential | Reject; show a security notice: "We couldn't confirm who sent this." Report a non-content diagnostic. |
| AEAD/authentication failure, malformed ciphertext | Drop the ciphertext; show "A message couldn't be opened." Log only the error type. |
| Device revoked (this device) | Wipe local keys and decrypted caches; sign out of the couple. Message: "This device was removed." |
| Recipient has no active device | Sender can't encrypt to an empty group; queue locally and tell the sender "Your person needs to open Sirf Hum to receive this." |
| Reinstall | No keys ⇒ a new device. It must be approved by an existing device or recovery; old messages are not readable unless transferred. |
| Unsupported protocol/schema version | Fail closed: "Update Sirf Hum to see this." Never downgrade or fall back to a weaker version. |
| Undecryptable message | Placeholder that says it couldn't be opened, never invented text. |
| Backup cannot be restored | Explain plainly; offer adding from an existing device; never claim recovery that the secrets can't provide. |
| Network loss mid-operation | Commits are idempotent per epoch (first wins; others re-base). Uploads resume at chunk boundaries. Local state changes only after the server accepts a Commit (merge after confirmation). |

## 11. Calls (future; LiveKit)

**RECOMMENDED direction; UNRESOLVED details.** Derive per-call media keys
with the MLS exporter (RFC 9420 §8.5) from the couple group, with label
`"sirf-hum call v1"` and context = call ID. Pass them to LiveKit's E2EE key
provider. LiveKit documents shared-key and custom key-provider modes for
some SDKs. **Support in the Flutter SDK was not verified**, so that's a
calls-phase blocker to check. Until verified, calls must not be described as
E2EE.

## 12. Protocol evolution

| Concern | Design | Label |
| --- | --- | --- |
| Versioning | Three layers: MLS protocol version + ciphersuite (in group context), `EncryptedEnvelope.protocolVersion` (Sirf Hum wire format), `SirfHumPayload.schemaVersion` | RECOMMENDED |
| Unknown version | Fail closed with "update the app"; never parse heuristically | APPROVED principle |
| No silent downgrade | A group's ciphersuite is fixed. Changing it means a new group via MLS ReInit or a new pairing group, announced to both people | RECOMMENDED |
| Staged rollout | Server enforces a minimum client version for writes to MLS documents; senders use the lowest common feature set of the group's devices (device capabilities are in MLS leaf nodes) | RECOMMENDED |
| Old messages | Remain encrypted under their original epoch; readable only on devices that hold those keys | RECOMMENDED |
| Interrupted rotation | Commits are atomic per epoch; a device that crashed before merging re-syncs the log and processes from its last merged epoch | RECOMMENDED |
| Library updates | Pin exact versions; review changelogs and advisories; run the E2EE test plan before upgrading; storage format migrations tested | RECOMMENDED |
| Post-quantum migration | Adopt standardized PQ MLS ciphersuites when available via ReInit | UNRESOLVED (timeline) |

## 13. Prototype (Prompt 04)

`prototypes/mls-device-roster/` is an **experimental spike, not in the app**.
It answers one question: can unmodified OpenMLS 0.9.1 express one couple
group whose members are devices, with:
- a convergent authenticated roster;
- removed devices unable to read later messages (whether online or offline
  when removed);
- rejection of replayed and tampered ciphertext;
- outsiders unable to read;
- all of this natively and on wasm32?

**Result (GitHub Actions run 38870995297, commit `a308745`, 2026-10-16):**
**6/6 tests passed natively (Linux) and 6/6 under wasm32 (Node,
wasm-bindgen-test)**:
- roster convergence with an equal epoch authenticator;
- the sender device is identified;
- a removed device can't read later messages, offline or after processing
  its removal;
- replay rejected;
- tampered ciphertext rejected;
- an outsider can't read.

The first CI attempt failed to compile because the spike called a test-only
OpenMLS API (`into_welcome`); it was fixed to use the public `extract()`.

**It does not establish:**
- security of OpenMLS;
- device-to-person binding (credentials are plain labels);
- persistence or key storage;
- the Flutter bridge;
- performance.

## 14. Unresolved decisions (summary)

1. ~~MLS library~~: OpenMLS selected (D-054); the **independent delta review of OpenMLS + our crypto core** remains blocking for production.
2. Accept no post-quantum protection in v1, or wait/choose differently.
3. Web capability in v1 (recommended: no private content). Needs product approval.
4. Credential format binding devices to PIKs (X.509 vs Basic credential + PIK-signed certificate extension).
5. Partner-verification UX and fingerprint format (QR in person; safety-number comparison).
6. Recovery offering (recovery key and/or encrypted history backup), and the user copy explaining loss.
7. Media binding (libsodium via Dart vs Rust), chunk size, size padding scheme.
8. Sender-ratchet tolerance, past-epoch window, retention TTLs.
9. Notification previews (default off).
10. LiveKit Flutter E2EE key-provider support.
11. Shared history after unpairing (product + legal; from the Privacy Constitution).
