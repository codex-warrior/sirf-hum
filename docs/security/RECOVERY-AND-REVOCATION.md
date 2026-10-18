# Recovery and Revocation

Status: **Design (Prompt 04). Revocation, device approval and an optional recovery key implemented in Prompt 08 ([MULTI-DEVICE-TRUST](MULTI-DEVICE-TRUST.md)); unreviewed.** Labels follow
[E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md#labels).

Principle (**APPROVED**, Prompt 01 / D-011): **no silent key escrow with
Sirf Hum.** We never promise recovery that the available secrets can't
deliver.

## Part 1: Revocation

### Flows (RECOMMENDED)

| Case | Who acts | What happens |
| --- | --- | --- |
| Remove one of my devices | Any of my other approved devices | MLS Remove commit in my personal group and the couple group; device record marked revoked (signed by my PIK); its KeyPackages and FCM token deleted |
| Lost / stolen device | Another device of mine, or a new device restored via recovery | Same as above, done remotely. Revocation is effective once the Remove commit is accepted, even if the lost device is offline |
| Lost device + no other device | Recovery key on a new device, then remove | See Part 2. Without recovery, create a new identity (partner sees a key change) and the old devices are removed by unpairing/re-pairing |
| From the web (v1) | Account session **plus** a confirmation from a remaining device; or recovery | Web can *request* removal. The Remove commit is made by a device holding keys (web v1 holds none) |

### Key rotation after revocation

- The MLS Remove creates a new epoch. Remaining devices derive new secrets,
  and the removed device gets nothing (verified by the Prompt 04 spike for
  online and offline removal).
- Each remaining device should also send an MLS Update soon after, so a
  device compromised *before* removal can't use stolen leaf keys
  (post-compromise healing).
- The server stops delivering to the revoked device: rules deny its device
  ID, and its tokens and KeyPackages are deleted. This is defence in depth;
  confidentiality comes from MLS.

### Limits of revocation (must be explained to users)

- Content a device already decrypted, displayed, screenshotted, exported or
  backed up **cannot be taken back.**
- A thief with an unlocked stolen phone sees what the owner could see until
  the Remove commit happens and the phone syncs it (or forever, if the thief
  keeps it offline with data already decrypted).
- Media URLs fetched before revocation remain decryptable by the device that
  received the key.

### Offline and concurrent cases

- **Offline revoked device:** it can't decrypt anything from later epochs
  (spike case 1). When it reconnects it processes its removal and wipes
  local state, assuming it runs honest code.
- **Concurrent roster changes from several devices:** first Commit per epoch
  wins; others re-base and retry. Everyone converges on one authenticated
  roster.

## Part 2: Recovery

### Options

| Option | Secrets needed | Who can decrypt | All devices lost? | Forgotten secret | Takeover risk | Usability |
| --- | --- | --- | --- | --- | --- | --- |
| **1. Add from an existing device** (QR) | A device you still hold | Only your devices | Not possible | n/a | Low: needs physical access to an approved, unlocked device | High; familiar |
| **2. Recovery key + user-encrypted backup** | A high-entropy recovery key (≥128 bits) the user stores | Only someone with the recovery key | Restores the PIK (and optionally a history archive) | **Recovery impossible**; new identity | A stolen recovery key + account access = takeover. Mitigate: re-auth, notify all devices and partner of the new device | Medium: users must store a key |
| 3. Passphrase-derived backup | User passphrase stretched with Argon2id | Anyone who guesses the passphrase offline, if the backup leaks | As option 2 | Same | **Offline guessing** if the server or backup leaks; weak passphrases are fatal | Higher, but less safe |
| 4. Recovery via the partner's device | Partner cooperation | — | Partner could "vouch" | — | **Rejected:** couple membership must not grant control over the other's identity; abuse risk | — |
| 5. Server escrow (Sirf Hum holds keys) | Our servers | **Sirf Hum** | Always | Always | Operator/compromise reads everything | **Rejected**: breaks the core promise |

### Recommendation

1. **Option 1 is the default** and needs no setup.
2. **Option 2 is an opt-in during onboarding.** Explain it plainly: "Save
   this recovery key. Without it, if you lose all your devices, your private
   history can't be recovered, not even by us."
   - Backup contents: the PIK private key; optionally (**UNRESOLVED**) an
     encrypted history archive.
   - Construction: an established AEAD under a key derived from the
     recovery key with HKDF. The recovery key is high-entropy, so no
     password hashing is needed.
   - Stored as ciphertext in Firestore/Storage.
3. Option 3 only if product insists; it needs a crypto review of the
   Argon2id parameters and the leak model.
4. Options 4 and 5 are rejected.

### What recovery restores

- **Restored:** the ability to certify new devices (PIK), so the partner sees
  no key change, and the user rejoins the couple group via a new Add.
- **Not restored by MLS:** messages from before the new device joined. MLS
  deliberately gives new members no history. Getting history back requires
  either:
  - (a) **device-to-device transfer** from an existing device; or
  - (b) a **history archive** encrypted with keys in the recovery backup.

  Offering (b) at all is **UNRESOLVED**: it adds a long-lived target and
  needs its own design and review.

### Account-takeover analysis

An attacker who takes the **Firebase account** (e.g. email takeover) but has
**no device and no recovery key**:
- can sign in and see metadata;
- **cannot** get a certified device into the groups, because their device
  certificate would need the victim's PIK;
- if they create a new PIK, the partner's app shows a **key change** and
  verification is lost.

Defence: the UI blocks sending to an unverified, changed identity until the
partner re-verifies.

## Part 3: Prompt 05 refinement (direction)

| Option | Description | Verdict |
| --- | --- | --- |
| **A. Trusted-device recovery** | An approved device adds and certifies the new device (QR) | **Default.** No server knowledge; works whenever any device survives |
| **B. User-controlled recovery key** | High-entropy key held by the user decrypts their own backup of the Person Identity Key | **Opt-in.** Restores identity (no partner key-change warning) when all devices are lost |
| **C. Encrypted recovery archive** | Message/media history encrypted under keys from the recovery backup | **Deferred.** A long-lived target; needs its own design and review. MLS gives new devices no history by design |
| **D. Combination** | A + B now; C only after separate review | **RECOMMENDED direction** |

**Explicitly rejected:** a server master decryption key, or any form of key
escrow with Sirf Hum or Google, as a recovery mechanism. It would make the
operator able to read content, contradicting the core promise (D-011).

## Part 4: What the Prompt 06 crypto core implements

Revocation and wipe exist; recovery does not.

- **Device removal:** `removeMember` commits a Remove. On receipt, the
  removed device gets `IncomingRemoved` and deletes its group state.
  Tests cover the removed device online and offline, and restored
  pre-removal state, none of which can decrypt the new epoch.
- **Revocation:** `revokeDevice` adds a device ID to the local trust policy.
  The core then refuses to add it again or accept it in a Welcome or commit.
- **Wipe:** `wipe` deletes every local record and zeroizes memory. Deleting
  the KEK as well is the platform adapter's job (D-066), which exists since
  Prompt 07: `removeAccount` deletes the slot's store key first, then the
  state (crypto-erasure, DEVICE-IDENTITY §7). On its own, the core's `wipe`
  is file deletion, not cryptographic erasure.
- **Recovery: not implemented.** No recovery key, no backup and no archive.
  There is no server key, no escrow and no export function, and none may be
  added (Prompt 06 rules 7–8).

- **Device records (Prompt 07; signed since Prompt 09, D-081):** a
  trusted device revokes a server record one-way (`pending|active →
  revoked`). Revoked device IDs and keys stay
  indexed forever, so neither can be activated again. A device that must
  work again gets a **new** identity (D-069).

Interaction with the MLS core (D-054):
- Recovery restores the **identity** (PIK), never MLS group secrets.
- A recovered device joins groups as a *new* member via Add/Welcome, so
  removal and rotation guarantees are unchanged.

## Part 5: What Prompt 08 implements (D-074–D-080)

Details: [MULTI-DEVICE-TRUST](MULTI-DEVICE-TRUST.md).

- **Trusted-device recovery (option A):** implemented as device approval.
  A trusted device's PIK signs an approval of the new device. **No PIK
  private key is transferred**: this supersedes the Part 3 and D-045 idea of
  moving the PIK between devices (D-074).
- **User-held recovery key (option B):** implemented, opt-in.
  - It is generated in Rust, shown once as `SHRK1-…`, and only its public
    half is registered.
  - It is **single-use**: after a recovery the user creates a new one.
  - It restores *device trust* for a new identity. It does **not** restore
    the old PIK or any history.
- **Encrypted history archive (option C):** still deferred.
- **All devices lost, no recovery key:** since Prompt 09, a delayed
  (7-day), cancellable identity reset to a NEW identity that partners must
  re-verify (D-082). A server or support reset is rejected, because it
  would turn a password compromise into a trust compromise.
- **Revocation:**
  - since Prompt 09, a trusted device signs each revocation (D-081); the
    owner's session alone can no longer revoke;
  - revoked devices cannot approve or register recovery keys;
  - approvals signed before revocation are refused;
  - revocation does not wipe the device remotely;
  - there is no cascade (`approvedBy` lineage is recorded).
