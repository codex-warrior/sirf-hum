# Multi-Device Trust, Revocation and Recovery

Status: **Security foundation implemented (Prompt 08). Sirf Hum is NOT
production E2EE yet.**

- Nothing here has been independently reviewed (§13).
- No product feature or UI uses it yet.
- The server half runs only in the emulator until the Blaze plan allows
  Cloud Functions to deploy (D-025).

Builds on [DEVICE-IDENTITY](DEVICE-IDENTITY.md). Decisions: D-074–D-080 in
the [Decision Log](../decisions/DECISION-LOG.md).

## 1. Trust model

| Term | Meaning | Established by |
| --- | --- | --- |
| **Account** | A signed-in Sirf Hum user (Firebase Auth) | Firebase Auth. Grants server *access*, **never** device trust |
| **Device** | One installation's identity for one account: its own device ID, device key and PIK (D-074) | Created locally in the Rust core |
| **Trusted device** | A device whose server record is `active` | Only: the account's **first** device's proof of possession, approval by a trusted device, or the recovery key |
| **Revoked device** | A device whose record is `revoked` (or `rejected`/`expired` before it was ever trusted) | The owner or the server. Terminal |

**Firebase Auth ≠ device trust.**
- Someone who knows the password can sign in and register a *pending*
  device, but it stays pending: activating it needs a signature by a key
  they do not have.
- Proof of possession alone activates a device only when the account has
  **never** had a trusted device (a server-only `accountTrust` record makes
  this once-ever).

## 2. Multi-device model (D-074)

```text
ACCOUNT
├── Device A  own device ID · own device key · own PIK ── active (first device)
├── Device B  own device ID · own device key · own PIK ── active (approved by A)
└── Device C  own device ID · own device key · own PIK ── active (approved by B)
```

- **No private key is ever shared, copied or transferred between devices.**
  Every device has independent key material, lifecycle and revocation.
- **Trust between a person's devices is a chain of signed approvals:** A's
  PIK signed "B is mine". It is not a shared secret.
- **Approving extends local trust:** the approving device also trusts the
  new device's PIK, so it can add the new device to MLS groups (tested).
  The new device learning its approvers' PIKs is future sync work (§14).

### PIK options evaluated (Prompt 08 §6)

| Option | Verdict | Why |
| --- | --- | --- |
| **A.** Independent PIK per device, no link | Rejected alone | Each device would be an unrelated identity: no way to prove two devices belong to one person, and a partner would have to verify every device separately with no chain |
| **B.** Transfer the PIK private key to new devices (Prompt 04, D-045) | **Rejected** | Prompt 08 §4 forbids reusing private keys across devices. One device's compromise would compromise every device's identity. It also needs a new encrypted transfer channel |
| **C.** Independent PIK per device + a signed authorization artifact | **Selected** | No key leaves any device. It reuses the D-064 certificate unchanged and is verifiable by the server now and by peers later (chain from a verified PIK). Revocation is per device |

D-064 is unchanged. D-045's PIK-transfer recommendation is superseded by
D-074.

## 3. Enrollment state machine

```text
                              ┌─ first device ever: proof of possession ──────┐
NEW ─registerDevice─► PENDING ┤                                               ├─► ACTIVE
                              └─ else APPROVAL REQUIRED:                      │
                                  request ─► proven ─► approved by a trusted ─┘
                                                       device / recovery key
PENDING ─► REJECTED (owner rejects) · EXPIRED (7 days) · REVOKED (owner)
ACTIVE  ─► REVOKED (owner)
```

- **Stored device states:** `pending`, `active`, `revoked`, `rejected`,
  `expired`. The last three are terminal.
- **Request states:** `open` → `proven`, then deleted on first use.
- **Client-side states** (`DeviceRegistrationFlow.enroll`):
  - `EnrollmentActive`;
  - `EnrollmentAwaitingApproval(request, code)`;
  - `EnrollmentTerminal(status)`.

  "Approval required" and "approved" are transient.

**Never:**
- REVOKED/REJECTED/EXPIRED → anything. Records are never deleted, and
  device IDs and keys are indexed forever.
- A second bootstrap.

A reinstall is a new device.

## 4. Approval handshake (D-075)

```text
New device B (pending)                     Server                          Trusted device A (active)
 registerDevice ─────────────────────────► verify cert · pending · expiry
 requestDeviceApproval ──────────────────► request{challenge[32], expiresAt=+10 min}
 ◄───────────────── requestId, challenge, expiresAt
 B's device key signs a device proof
   (purpose 2 = enrollment) ─────────────► verify PoP → request "proven"
 show code(B cert, challenge)                                   listDeviceApprovalRequests ◄── A
                                                                 A shows code(B cert, challenge)
                                           user: the codes match → approve
                                                                 A's PIK signs approval ──── A
                                           approveDevice: one transaction —
                                             request proven & live · A ACTIVE NOW ·
                                             B pending & live · statement verifies
                                             against A's STORED certificate ·
                                             uniqueness → B active, request deleted
```

**Approval statement** (signed by the approver's PIK; Ed25519 via the
OpenMLS provider and `node:crypto`):

```text
"SirfHum-DeviceApproval-v1" | protocol version u8 = 1 | u32 len | account id
| approver device id[16] | u32 len | approver certificate
| new device id[16] | u32 len | new certificate
| challenge[32] | expires_at u64 BE (whole seconds)
```

| Binding | Prevents |
| --- | --- |
| Account | Account confusion; replay into another account |
| Approver ID and certificate (checked against the server's stored record) | Approval by an untrusted or different device |
| New device ID and certificate | Device substitution; approving the wrong device |
| Single-use server challenge | Replay and forwarding (each request is deleted on first use) |
| Expiry (server-chosen, signed) | Late use; the server also checks its clock |
| Domain string and version | Cross-protocol reuse: a Prompt 07 device proof, certificate, recovery statement or MLS signature is never accepted as an approval (tested) |

**Comparison code:**
- **What it is:** a six-digit code, `SHA-256("SirfHum-ApprovalCode-v1" |
  len | new certificate | challenge)[0..4] mod 10⁶`.
- **Who shows it:** both devices. The user approves only the request whose
  code matches the new device's screen.
- **What it stops:** an attacker with the account password registering
  their own pending device and hoping the owner taps "approve".
- **What it is not:** a secret. It is a short authentication string.
- **Guessing:** matching a code takes ~10⁶ rate-limited, server-issued
  requests.

## 5. Security-layer API (for a future UI)

`DeviceRegistrationFlow.enroll`, and `DeviceTrustService`:

- `pendingApprovals` (with codes);
- `approve` and `reject`;
- `revoke`;
- `devices`;
- `createRecoveryKey` and `recover`;
- `refreshStatus`.

All return typed states or `DeviceRegistryException(DeviceRegistryFailure)`
categories, so the UI never handles cryptography. Before approving or
creating a recovery key, a device re-reads its own server status.

## 6. Revocation (D-080)

- **Who:** the account owner, from any signed-in session, via the rules
  (`pending|active → revoked`, one way). Server-side revocation is also
  supported.
- **Why the owner's session suffices:** revocation only *reduces* trust.
  Requiring a trusted device would leave a user whose only device was
  stolen unable to kill it.
- **Accepted cost:** someone with the password can revoke devices. That is
  a denial of service, never a trust gain: they still cannot activate
  anything.
- **What a revoked device cannot do:**
  - reactivate itself;
  - be re-registered (no deletes; ID and key indexes);
  - approve another device or register a recovery key (the server checks
    the approver is active **at submission**);
  - use an approval it signed before revocation (it dies with the
    approver).
- **No cascade:** revoking B does not revoke devices B approved earlier.
  They were legitimately approved while B was trusted. `approvedBy` records
  the lineage so the owner can review and revoke them, e.g. when B was
  compromised.
- **MLS:** removal from groups is an MLS Remove commit (Prompt 06), wired
  up with messaging.

## 7. Revoked-device behaviour and offline devices

**Local data deletion ≠ cryptographic revocation.**
- **Revocation** is a server fact: the device is no longer trusted, and
  peers will remove it from MLS groups.
- **Deletion** is the local wipe of the device's slot (store key first,
  then state).

Revocation does not wipe the device remotely. A thief's offline copy stays
on the thief's device.

When a device learns it is revoked (`refreshStatus` returns a terminal
status):
1. It stops presenting itself as trusted. Approve and recovery-key
   operations refuse locally (`deviceNotTrusted`), and the server refuses
   them anyway.
2. Pending operations are dropped. Cached server metadata is ignored in
   favour of the server's status.
3. The local identity is **not** wiped automatically. Already-received
   content remains readable on that device, which is inherent: E2EE cannot
   recall plaintext. The app offers "remove this account from this device"
   (crypto-erasure) and, if the user wants the phone back, enrolling as a
   **new** device.

**Offline:** while a device is offline, nothing tells it that it was
revoked. The server is authoritative, and every trust-creating call checks
the approver's status at submission. An offline device that reconnects:
- cannot create server-authorized trust;
- sees its revoked status on the next read (tested: offline revocation,
  pre-revocation approval submitted after).

## 8. Recovery (D-076)

| Option | Verdict |
| --- | --- |
| **A. Device-to-device:** a trusted device approves the new one | **Default** (§4) |
| **B. Self-held recovery key** | **Implemented, optional.** For when every trusted device is lost |
| **C. Server recovery** | **Rejected.** The server can authenticate the account, but if it could also create device trust, a password compromise would equal a trust compromise |
| **D. Support/admin recovery** | **Rejected** for trust. Support may help with *account* access (Firebase), never with device trust or content |

**Never:**
- a server master key;
- server copies of private keys;
- a plaintext recovery secret on the server;
- support able to decrypt;
- "forgot password" restoring E2EE history.

**Recovery key:**
- **Generation:** a 32-byte Ed25519 seed generated **in Rust** on a trusted
  device (`createRecoveryKey`).
- **Export:** exactly once, as text, by explicit user action:
  `SHRK1-XXXX-…`, which is RFC 4648 base32 of
  `version | seed | 4-byte typo checksum`. The checksum is only for
  typos; the 256-bit seed carries the security.
- **Server side:** only the **public** half is registered, signed by the
  device's PIK (`"SirfHum-RecoveryKeyRegistration-v1"` statement, single-use
  challenge). Registering again replaces the key.
- **Use:** a new device B registers, opens a request and proves possession.
  The user types the key; Rust signs `"SirfHum-RecoveryApproval-v1" |
  version | account | recovery public key | B's ID | B's certificate |
  challenge | expiry`, then wipes the seed.
- **On success:** the server activates B and **deletes the registered key
  (single-use)**. The user creates a new one from B.
- **Never** a Firebase password-reset token.

**What survives losing all devices:**

| | With a recovery key | Without |
| --- | --- | --- |
| Account access (sign in) | Yes (Firebase) | Yes (Firebase) |
| A new trusted device | **Yes** | **No path yet.** No re-bootstrap: an "identity reset" is designed as a future, partner-visible operation (D-076 open) |
| Message history | **No.** MLS gives new devices no history; an encrypted archive is deferred (RECOVERY-AND-REVOCATION) | No |
| Partner relationship | Continues; the new device is visible (future pairing UX) | Requires reset and re-verification |

A clearly unavailable path is safer than a misleading one. Nothing here
pretends otherwise.

## 9. Rollback (D-079): NOT provided

**Threat:** an attacker with root access, or a restore tool, puts back an
older copy of a device's local state, for example to revive keys before a
rotation or a revocation.

| Option | Assessment |
| --- | --- |
| Counter inside the sealed state | Useless alone: it is rolled back together with the state |
| Platform monotonic counter | Neither Android Keystore nor iOS Keychain offers a general-purpose app counter. Keychain items survive app deletion but can be restored together with the files on a jailbroken device |
| Server-held state version | Needs the device to report a version per write: an activity signal (metadata) plus a design for offline devices. Possible later, not now |
| Hardware attestation (Play Integrity, App Attest) | Narrows tampering; does not prove freshness |

**What does hold today:**
- copied state is useless on another device (non-migrating keys);
- restored state cannot regain *server* trust: status is server-side, and
  revoked IDs and keys are indexed forever;
- MLS removal still blocks new epochs (Prompt 06 test: restored
  pre-removal state cannot decrypt).

**No rollback protection is claimed.** Production hardening must decide it
(D-079 open).

## 10. Rate limits and expiry (D-077, D-078)

Per-account fixed windows, in the server-only `rateLimits` collection:

| Operation | Limit |
| --- | --- |
| `registerDevice` | 5 per hour, and at most 3 `pending` devices at once |
| Challenges (activation, recovery registration) | 10 per hour |
| Approval requests | 5 per hour |
| Verification failures of any kind (bad proofs, approvals, recovery signatures) | 5 per hour, then every verifying call is refused for the window |
| Recovery attempts | 3 per day |

The limits never become an account-enumeration oracle:
- they are keyed by the caller's **own** account;
- the error is a generic `rate_limited`;
- they reveal nothing about other accounts.

**Lifetimes** (server-chosen, enforced on every call):

| Item | Lifetime |
| --- | --- |
| Challenges | 5 minutes |
| Approval requests | 10 minutes |
| Never-activated pending devices | 7 days, then `expired`: kept, never deleted |

**Cleanup:**
- `cleanupExpiredDeviceRecords` runs daily: it expires stale pending
  devices and deletes stale challenges and requests.
- It is idempotent, re-checks each record in a transaction, and never
  touches an active device.
- Its schedule needs Cloud Scheduler, i.e. Blaze. Expiry works without it
  (lazy).

## 11. Server authority

**The server decides:**
- registration status;
- activation;
- revocation;
- approval validity;
- expiry and rate limits.

**The server cannot:**
- sign an approval, a recovery approval or a device proof (it has no
  private key);
- decrypt anything (no content keys, no master key).

A malicious server could still:
- refuse service;
- lie about status;
- fabricate records.

Peers must verify certificates, PIKs and approval chains themselves (D-057).
That peer-side verification of approval chains is future work (§14).

## 12. Observability

- **Logged:** event names and coarse categories only, e.g.
  `device_enrollment_state state=awaiting_approval`, `device_approved
  outcome=approved`, server `device_approved outcome=approval_invalid`.
- **Never logged:** recovery keys, seeds, challenges, signatures, codes,
  certificates, device IDs or account IDs. Tests assert that recovery-key
  fragments, IDs, codes and request IDs never appear in client logs.

## 13. Independent review required (not done)

Each item below needs review before any production claim. None is
independently audited:
- the device approval protocol and comparison code;
- the recovery design and recovery-key format;
- revocation enforcement;
- the platform secure storage adapters;
- rollback analysis;
- the server Functions;
- the Firebase Rules.

## 14. Open / next

- **Deployment:** deploy the Functions and the cleanup schedule (Blaze,
  D-025).
- **Peer-side trust:** devices verify approval chains when adding or
  accepting group members, and learn their approvers' PIKs (messaging
  phase).
- **Identity reset** without devices or a recovery key: partner-visible and
  re-verified (D-076 open).
- **Rollback protection** (D-079).
- **Signed revocations** for attribution and peer verification (D-080
  follow-up).
- **Device-management UI.**
