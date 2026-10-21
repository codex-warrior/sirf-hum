# Device Identity and Registration

Status: **Foundation implemented (Prompt 07); multi-device trust, revocation
and recovery added (Prompt 08, [MULTI-DEVICE-TRUST](MULTI-DEVICE-TRUST.md)).
Sirf Hum is NOT production E2EE yet.**

- Nothing here has been independently reviewed.
- No UI uses device identity yet. The development messaging service
  (Prompt 10) binds MLS membership to it: an MLS credential is accepted only
  as an exact trusted device certificate (D-085,
  [E2EE-MESSAGING-DESIGN](E2EE-MESSAGING-DESIGN.md)).
- Server-side activation runs only in the emulator until the Blaze plan
  allows Cloud Functions to deploy (D-025).

Decisions: D-066 (platform key store), D-069 (registry), D-070 (proof of
possession), D-071 (account slots); Prompts 08–09: D-074–D-084 in the
[Decision Log](../decisions/DECISION-LOG.md). Related:
[KEY-MANAGEMENT](KEY-MANAGEMENT.md),
[PAIRING-AND-DEVICE-TRUST](PAIRING-AND-DEVICE-TRUST.md),
[CRYPTO-CORE-ARCHITECTURE](CRYPTO-CORE-ARCHITECTURE.md),
[THREAT-MODEL](THREAT-MODEL.md).

## 1. Identity hierarchy

These four identities are distinct types in code, and none ever stands in
for another.

| Layer | What it is | Where it lives | Type |
| --- | --- | --- | --- |
| **A. Account identity** | The authenticated Sirf Hum user (Firebase Auth UID) | Firebase Auth; a server/session label | `AccountId` (Rust, Dart) |
| **B. Device identity** | One installation's identity *for one account*: a random 128-bit device ID | Generated in the Rust core (CSPRNG); public | `DeviceId` |
| **C. Cryptographic identity** | The device's Ed25519 signature key pair, plus the Person Identity Key (PIK) that certifies it in a device certificate (D-064) | Private halves: Rust core only, in sealed local state. Public halves: the certificate | `PersonKey`, `DeviceCertificate` |
| **D. MLS identity / credential** | The MLS `BasicCredential` whose identity bytes are the device certificate, with the device signature key as the leaf key | Inside MLS groups | OpenMLS `Credential` |

Rules:

- **The Firebase UID is never a cryptographic identity.** It names the
  account and labels local storage slots; the server uses it for
  authorization. It is never signed into certificates and never trusted
  for cryptographic decisions.
- **The device ID is never a user ID.** It is random and carries no
  account information.
- **Email and phone are never cryptographic identities.**
- **Mutable profile data and display names are never identities.**
- **Trust comes from verified PIKs and certificates**, checked by every
  device. A server record is a directory entry, never proof
  ([PAIRING-AND-DEVICE-TRUST](PAIRING-AND-DEVICE-TRUST.md)).

### Device ID

- **Generation:** 16 bytes from the OS CSPRNG (`OsRng`), drawn inside the
  Rust core when an identity is created. The collision probability is
  negligible (birthday bound ≈ 2⁻⁶⁴ at 2³² devices), and the server also
  refuses duplicates (§6).
- **Never derived from:** phone, email, hardware serial, advertising ID,
  IMEI, MAC address or Firebase UID. Nothing device-specific goes into it.
- **Scoped per (installation, account):** a second account on the same
  phone gets a different device ID. There is no installation-wide
  identifier, so the server cannot link two accounts used on one phone
  through Sirf Hum's own data. Infrastructure metadata such as IP addresses
  still exists (§10).
- **Exposure:** it appears only in the device record, the certificate and
  MLS. It is redacted in all logs and `toString` output.

### Behaviour by situation

| Situation | What happens | Why |
| --- | --- | --- |
| Normal restart | Same identity. Sealed state is reopened with the slot's store key | Persistence |
| Logout | Nothing is deleted. The core is closed and the slot stays | Logging back in resumes the same device |
| Login as the same account | Same identity | Same slot |
| Account switch (A out, B in) | B opens **B's own slot**. A's identity is never used for B. The core re-checks the account on every open (`AccountMismatch`) | §8 |
| "Remove this account from this device" | `removeAccount`: deletes the store key first (crypto-erasure), then the state. The next login is a **new device** | Explicit only |
| Reinstall (Android) | Uninstalling deletes the Keystore key and the no-backup files: **a new device** | No secure state survives |
| Reinstall (iOS) | App files are deleted but Keychain items survive. With no state, the stale key is discarded and replaced (key rotation): **a new device** | We never pretend identity survives a reinstall |
| App data cleared | Same as reinstall: **a new device** | No secure state survives |
| Migration to a new phone | Not migrated: no-backup storage, `ThisDeviceOnly` Keychain, excluded directories. Since Prompt 17 the app opts out of cloud backup and device transfer entirely, so not even the Firebase session moves (D-123). The new phone is **a new device**, approved by a trusted device or the recovery key | Keys never leave a device |
| Cloned or restored app state | Sealed state without this device's store key fails closed as `LocalIdentityCorrupted(undecryptable)`. Nothing is wiped automatically | Copies are useless without the platform key |
| Compromised device | See §9. The fix is revocation, then a new identity | Not preventable by storage |

The old server record of a replaced device stays until it is revoked.
Revocation of unreachable devices from another device is future
device-management work.

## 2. Key material and local storage

| Material | Created | Stored | Leaves the device? |
| --- | --- | --- | --- |
| Device signature private key | Rust core | Sealed `identity_secret` record (D-065) | **Never** |
| PIK private key | Rust core (first device) | Sealed `identity_secret` record | **Never** (device-to-device transfer is future work) |
| Store key (32 bytes) | Platform adapter (CSPRNG) | Android: wrapped by a non-exportable Keystore AES-256-GCM key (StrongBox if available) in `noBackupFilesDir`. iOS: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain item, not synchronizable | **Never** |
| Keystore wrapping key | Android Keystore | Hardware/TEE | Never; non-exportable |
| Certificate, device public key, device ID | Rust core | Local state + server record | Yes (public) |

Private key material is **never** in Firestore, Storage, SharedPreferences,
UserDefaults, plaintext files, analytics, crash reports, logs or Cloud
Functions. The Dart layer never receives a private key: only the store key
crosses it, once per open, and it is zeroed immediately after.

**Store key handling:**

- It is fetched per open and passed to `CryptoCore.initializeWithPlatformKey`,
  which zeroes the caller's buffer. Rust holds it in `Zeroizing` memory.
- The platform side wipes its own copy after the channel copies it.
- Copies made by the platform message codec cannot be wiped reliably, which
  is a documented residual risk.

**Guarantees, each tested:**

- **Persistence across restarts:** the identity survives reopen.
- **Corruption detection:** sealed records are AEAD-authenticated, and a
  tampered, truncated or moved record means "corrupted".
- **Partial writes:** atomic replace (temp file + fsync + rename). A
  leftover temp file is ignored.
- **Deterministic wipe:** `removeSlot` deletes the key first, then the
  directory.
- **Safe failure:** a missing platform key store or native core means
  `unavailable`, never an unprotected fallback.
- **No test keys in release:** release builds refuse the insecure test key
  stores (`CryptoCore.initialize`).

## 3. Lifecycle

Since Prompt 08: the full state machine, approval and recovery are in
[MULTI-DEVICE-TRUST §3](MULTI-DEVICE-TRUST.md#3-enrollment-state-machine).

```text
 NEW INSTALL / NEW ACCOUNT ON DEVICE
   │ open(account): slot key from Keystore/Keychain (fresh if none)
   │ Rust core: device ID + device key + PIK + certificate (CSPRNG)
   │ private keys sealed locally
   ▼
 unknown ──registerDevice (server)──► pending ──first device ever: proof of possession──► active
                                         │      later devices: approval by a trusted ──┘
                                         │      device or the recovery key
                                         ├──► rejected · expired          (terminal)
 pending / active ──signed by a trusted device (D-081) or identity reset (D-082)──► revoked  (terminal)
```

| Transition | Who | Enforced by |
| --- | --- | --- |
| unknown → pending | **Server** (`registerDevice`: certificate verified, rate-limited, max 3 pending) | Function; rules deny client creates (Prompt 08) |
| pending → active | **Server only**: bootstrap proof of possession (first device, once ever), or approval / recovery | `activateDevice`, `approveDevice`, `recoverDevice`; rules deny client `active` |
| pending → rejected / expired | **Server** | `rejectDeviceApproval`; expiry (lazy + scheduled cleanup) |
| pending → revoked, active → revoked | **Server**, on a trusted device's signed revocation (`revokeDevice`, D-081) or a completed identity reset (D-082) | Function; rules deny every client write (Prompt 09) |
| revoked / rejected / expired → anything | **Never** | Functions check the source state in a transaction; rules deny client writes; records can't be deleted, so a device ID can't be re-created; the uniqueness indexes keep the ID and key forever |

A device that must work again after revocation gets a **new** device
identity (new keys, new device ID). Recovery (MULTI-DEVICE-TRUST §8)
creates trust for a new identity; it never reactivates the old one.

The client flow (`DeviceRegistrationFlow.enroll`) is idempotent. It
resumes from `pending` with a new challenge or request, does nothing when
`active`, and stops at any terminal state.

## 4. Firestore schema

`users/{accountId}/devices/{deviceId}`. `deviceId` is the 32-character
lower-case hex of the device ID.

| Field | Type | Written by | Why the server needs it |
| --- | --- | --- | --- |
| `schemaVersion` | int `1` | server (register) | Readers reject versions they don't understand (D-061) |
| `status` | `pending` / `active` / `revoked` / `rejected` / `expired` | server only (register, activate, reject, expire, signed revocation, reset) | The lifecycle; future rules and fan-out read only active devices |
| `platform` | `android` / `ios` | client input, server-validated | Lets the owner recognise devices when managing them, and allows platform-specific policy (e.g. future attestation). Coarse: no model or OS version |
| `certificate` | bytes ≤ 512 | client input, server-verified at registration; immutable | The public identity binding (PIK → device ID → device key) that the server verifies and other devices verify themselves |
| `ciphersuite` | int `1` | server (register) | MLS capability (D-061); refuses future suites until supported |
| `implementation` | `openmls/0.9.1` | server (register) | Implementation identifier (D-061), for compatibility handling |
| `createdAt` | server timestamp | server (register) | Audit |
| `expiresAt` | timestamp (pending only) | server (register); removed on activation | Server-authoritative expiry of never-activated devices (D-078) |
| `activatedAt` | timestamp | server | When the device became trusted |
| `activationMethod` | `first_device` / `approval` / `recovery` | server | How trust was established (audit, owner review) |
| `approvedBy` | device ID (hex) | server, for `approval` | Lineage, so the owner can review devices approved by a later-revoked device (D-080) |
| `approval` / `recovery` | map of public evidence (protocol version, signer certificate, challenge, expiry, signature; recovery also the key registration) | server, on activation | Peers re-verify the chain on device (D-084) |
| `activatedEpoch` | int | server, on activation | Account trust epoch at activation: orders the chain (D-083, D-084) |
| `rejectedAt` | timestamp | server, for `rejected` | When the owner rejected the request |
| `revokedAt` | server timestamp | server (revoke, reset) | When the device was retired |
| `revokedReason` | `removed` / `lost` / `stolen` / `compromised` / `identity_reset` | server | A fixed enum, never free text |
| `revocation` | map: authority `device` (revoker certificate, reason, challenge, expiry, signature) or `identity_reset` | server | Signed evidence peers re-verify (D-081, D-084) |
| `revokedEpoch` | int | server | Account trust epoch at revocation (D-083) |

**Deliberately absent:**

- `lastSeenAt`: it would record activity patterns and nothing needs it yet;
- app version, OS version, device model, hardware IDs, advertising ID,
  push token (a later messaging phase decides);
- location, contacts, display names.

Server-only collections (Admin SDK; rules deny every client):

| Collection | Contents | Purpose |
| --- | --- | --- |
| `deviceChallenges/{challengeId}` | `accountId`, `deviceId`, `purpose` (`activation` / `recovery_registration`), 32-byte `challenge`, `expiresAt` | Single-use, 5-minute challenge; deleted by the first attempt |
| `accountTrust/{accountId}` | `initializedAt`, `firstDeviceId`, optional `recoveryKey {publicKey, registeredByDeviceId, registeredAt}`, `lastRecoveryAt` | Makes first-device bootstrap once-ever; holds the recovery key's **public** half (D-075, D-076) |
| `deviceApprovalRequests/{requestId}` | `accountId`, `deviceId`, 32-byte `challenge`, `status` (`open` / `proven`), `createdAt`, `expiresAt` | Single-use, 10-minute approval request; deleted by its first approval, rejection or recovery attempt |
| `rateLimits/{accountId}__{operation}` | `windowStart`, `count` | Per-account fixed-window limits (D-077) |
| `deviceIdIndex/{deviceId}` | `accountId` | A device ID is activated at most once, globally, forever |
| `deviceKeyIndex/{sha256(deviceKey)}` | `accountId`, `deviceId` | A device public key is activated at most once, globally, forever |
| `personKeyIndex/{sha256(PIK)}` | `accountId`, `deviceId` | A person key is activated on at most one device, globally, forever (D-122, Prompt 17): a revoked device's PIK never returns under a new device ID or as a new root |

## 5. Security Rules

The rules are in `firebase/firestore.rules` (default deny kept); the tests
are in `firebase/tests/devices.test.js`.

- **Read:** only the owner (`request.auth.uid == accountId`).
- **Create:** never from a client (Prompt 08). `registerDevice` writes the
  `pending` record after verifying the certificate and applying rate limits.
- **Update:** never from a client (Prompt 09, D-081). Until Prompt 09 the
  owner could revoke one-way through the rules; revocation now needs a
  trusted device's signature, verified by `revokeDevice`.
- **Delete:** never.
- **`accountTrust/{uid}`:** owner read (trust epoch, reset state, recovery
  key public half); never written by a client.

Rules cannot verify signatures or count. That is why registration and
`active` are reachable only through the Functions, and why terminal states
can never change. Since Prompt 09 no device state is client-writable.

## 6. Proof of possession (D-070)

Firebase Auth proves who the **account** is. A device record proves
nothing. Activation additionally proves that the registering client holds
the private key of the **device key named in the certificate**.

**Since Prompt 08** (D-075), this activation path applies only to an
account's **first** device, once ever. Later devices prove possession with
purpose `enrollment` (2) and must be approved by a trusted device or the
recovery key ([MULTI-DEVICE-TRUST §4](MULTI-DEVICE-TRUST.md#4-approval-handshake-d-075)).

1. `issueDeviceChallenge({deviceId})`:
   - requires auth and App Check;
   - the record must exist under the caller's account and be `pending`;
   - creates 32 random bytes with a 5-minute expiry, bound to (account,
     device, purpose).
2. The device signs, inside Rust (`CryptoCore.deviceProof`):

   ```text
   "SirfHum-DeviceProof-v1" | purpose=1 | u32 len | accountId | deviceId[16]
     | u32 len | certificate | challenge[32]
   ```

   with its device signature key (Ed25519 via the OpenMLS provider). The
   core builds this payload from its own state, so callers cannot obtain
   signatures over arbitrary bytes. The domain is distinct from
   certificates (`SirfHum-DeviceCertificate-v1`) and from all MLS labels.
3. `activateDevice({deviceId, challengeId, proof})`, in one Firestore
   transaction:
   1. the challenge exists and is **deleted on every attempt**, success or
      failure;
   2. it matches the caller, device and purpose, and has not expired;
   3. the record is `pending` and schema 1;
   4. the certificate decodes strictly and its PIK signature verifies;
   5. it certifies exactly this device ID;
   6. the proof verifies under the certified device key;
   7. the device ID and device key are not yet indexed.

   Only then is the device set `active`, with the indexes created.

Verification uses `node:crypto` Ed25519 (RFC 8032); no primitive is
custom. The TypeScript decoder mirrors the Rust one, and a golden vector
generated by the server code (`functions/test/vectors/device_proof_v1.json`)
is verified by the Rust tests, proving both encodings agree.

**Why this is enough for now:**

- the PIK signs the certificate;
- the device key signs the proof;
- the account binding stops cross-account replay;
- the single-use challenge stops replay over time.

**Not covered:** whether the PIK belongs to the person. That is partner
verification at pairing (future), not the server.

### Replay and cloning defences (all tested)

| Attack | Result | Where tested |
| --- | --- | --- |
| Replayed registration (create the same record again) | Prompt 08: `registerDevice` refuses an existing record (`duplicate_device`), and clients cannot create at all | emulator, rules |
| Replayed proof (same challenge twice) | `challenge_invalid`: consumed on first use | emulator |
| Reused challenge after a failed attempt | `challenge_invalid` | emulator |
| Stale challenge (> 5 min) | `challenge_expired` | emulator |
| Challenge used by another account | `challenge_invalid` | emulator |
| Duplicate device ID (another account, other keys) | `duplicate_device` | emulator |
| Duplicate public identity (same device key, new device ID) | `duplicate_device` | emulator |
| Altered public identity (any certificate byte) | `certificate_invalid` | unit (every byte), emulator, Rust |
| Altered account ID (proof replayed under another account) | `proof_invalid` | unit, emulator, Rust |
| Altered device ID (certificate filed under another ID) | `certificate_invalid` | emulator |
| Revoked device attempting authentication | `device_not_pending` (challenge and activation) | emulator |
| Copied record without the private key | `proof_invalid` | emulator |
| Copied public key with a different device ID | proof impossible without the private key, then `duplicate_device` | unit, emulator |
| Client sets `active` itself | Denied | rules |
| Malformed or oversized input | `invalid_argument` before any read | emulator, rules |

## 7. Revocation

- **Server record:** revocation only by a trusted device's signed
  statement (`revokeDevice`, D-081) or a completed identity reset (D-082);
  clients cannot write device records at all. Server-side states
  `rejected` and `expired` remain. Revoked devices cannot approve, revoke,
  register a recovery key, or use approvals signed before revocation
  (MULTI-DEVICE-TRUST §6–§7).
- **MLS:** revocation in groups is an MLS Remove commit plus the local
  revoked-devices list (Prompt 06, RECOVERY-AND-REVOCATION). Group wiring
  is future work.
- **Local:** `removeAccount` deletes the slot's store key, then its state.
- **Key and ID indexes** keep every revoked key and ID forever, so neither
  can be activated again.

## 8. Account switching

- **One slot per account** (`slot = accountId`, validated
  `[A-Za-z0-9_-]{1,128}`), each with its own directory and store key.
- **On every open,** the Rust core checks that the stored identity's
  account equals the requested account; any mismatch fails closed
  (`accountMismatch`).
- **The registration flow checks it again** before sending anything.
- **Logout** keeps the slot. Signing in as B never touches A's slot.
- **Removing an account** is explicit and irreversible for that device.

## 9. Compromised-device and server assumptions

| Scenario | What the design protects | What it cannot protect |
| --- | --- | --- |
| Rooted Android | Keystore keys stay non-exportable (TEE/StrongBox); copied files are useless off-device | Root code inside the app process can ask the Keystore to unwrap, read memory while the app runs, and act as the device. Revocation is the remedy |
| Jailbroken iOS | Keychain items stay `ThisDeviceOnly` | Same as rooted Android: process-level access defeats local secrecy while the app runs |
| Malware with process access | Nothing local: it is the device | Everything the app can do. Detect, revoke, new identity |
| Stolen unlocked device | Remote revocation from another device (future UX) | Whatever the app shows until revoked |
| Stolen locked device | The store key is `AfterFirstUnlock`: protected before the first unlock after boot; storage encryption at rest | After a first unlock, a locked device in memory is only as strong as the OS lock |
| Compromised Firebase account | Account takeover ≠ device takeover: a new device needs proof of possession for its **own** key and is visible as a new device. The attacker can't activate copies of existing devices | The attacker can register and activate their own new device for that account. The partner-visible roster and PIK verification are the defence (future pairing) |
| Compromised server / Functions | Cannot obtain private keys; cannot forge a device certificate or proof for an existing device | Can withhold, lie about status, activate devices it fabricates, or reveal metadata. Peers must verify certificates and PIKs themselves (D-057), so a fabricated device has no trusted PIK |
| Compromised database (read) | Only public material and metadata | Account ↔ device relationships, platforms, timestamps |
| Revoked device | Can't be reactivated, re-registered or re-indexed. MLS removal blocks new epochs (Prompt 06 tests) | Content it already decrypted; its local copy of old state |

Secure storage reduces exposure **at rest**. It does not make a device
invulnerable, and nothing here claims it does.

## 10. Metadata privacy

- **The server learns:**
  - that an account has N devices;
  - their platforms;
  - creation, activation and revocation times;
  - certificates (public keys, device IDs, issued-at).
- **Timestamps** reveal when a device was set up or retired. They are
  coarse lifecycle events, never activity.
- **Infrastructure metadata exists regardless:** Firebase and Google Cloud
  see IP addresses, user agents and request times for Auth, Firestore and
  Functions calls. This design doesn't add any, and can't remove it.
- **No hardware identifiers, advertising IDs, locations or contacts**,
  and no telemetry.

## 11. Web

Private E2EE on Web is **off** for V1 (D-046):

- `LocalDeviceIdentityService.open` returns `unavailable(web)`;
- `PlatformSecureKeyStore.isSupported` is false;
- the crypto package compiles a stub that throws `unsupported`.

A wasm build of the core is no permission to enable it. Web may later get
an *account session* (non-cryptographic), which is not a device identity.

## 12. App Check and observability

- **App Check:** the callables set `enforceAppCheck: true`. This is defence
  in depth only; authorization is auth plus proof of possession. Development
  builds use the debug provider (Prompt 02).
- **Logs** carry event names and categories only (`device_identity_opened
  outcome=created`, `device_registration_status status=active`, and on the
  server `device_activation outcome=proof_invalid`).
- **Never logged:** keys, store keys, challenges, proofs, certificates,
  device IDs, account IDs (tested on the client).
- **Errors** are category enums on every layer. Platform channel errors
  carry no messages, and nothing goes to Crashlytics except sanitized
  `AppLogger` records.

## 13. Relationship to later phases

- **MLS (messaging):**
  - an `active` device's certificate is its MLS credential;
  - groups add only certified, trusted, non-revoked devices (D-057);
  - KeyPackage publishing will reference the active record.
- **Device approval (Prompt 08, D-074):** each device keeps its own PIK;
  a trusted device's PIK signs an approval of the new one. No private key
  is transferred (this supersedes the PIK-transfer idea in
  PAIRING-AND-DEVICE-TRUST).
- **Recovery (Prompt 08, D-076):** an optional single-use recovery key
  approves a **new** device identity. It never reactivates a revoked one,
  never restores history, and never uses a server key or escrow.

## 14. Limitations and open items

- **Server activation is not deployable:** Cloud Functions need the Blaze
  plan (D-025). Until then deployed clients stay `pending` (`unavailable`
  on challenge). Activation logic is verified in the emulator only.
- **Rate limits and expiry:** added in Prompt 08 (D-077, D-078). The
  scheduled cleanup needs Blaze; lazy expiry works without it. Prompt 12
  adds the pairing limits `pairing`, `pairingInvitation` and
  `pairingRedeemFailure` (D-103) and proof purpose 4 (D-102). Later
  purposes: 5 `commit` (D-127), 6 `approval_rejection` (D-129),
  7 `conversation_recovery` (D-135) and 8 `unpair` (D-136), with limits
  `commit`, `conversationRecovery` (3/24 h) and `unpair` (5/24 h).
- **Local rollback:** not provided (D-079 open, MULTI-DEVICE-TRUST §10).
  The trust epoch (D-083) only refuses older *server* views.
  Restoring a whole older slot directory *together with* its key isn't
  possible off-device (keys don't migrate), but on a rooted device an
  attacker could restore an older state.
- **Dart heap copies** of the store key from the channel codec cannot be
  reliably wiped.
- **No attestation** (Play Integrity / App Attest) beyond App Check.
- **Unreviewed:** the formats, proof protocol, rules and adapters all need
  independent review before any production claim.
