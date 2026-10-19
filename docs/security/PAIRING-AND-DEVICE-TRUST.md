# Pairing and Device Trust

Status: **Design (Prompt 04). Own-device enrollment implemented in Prompt 08 as signed approvals without PIK transfer ([MULTI-DEVICE-TRUST](MULTI-DEVICE-TRUST.md), D-074); pairing two people implemented server-side in Prompt 12 ([COUPLE-AND-PAIRING](COUPLE-AND-PAIRING.md), D-100–D-105: server-generated token, inviter confirmation of the claimant, device-signed steps); no UI; PIK verification still open.** Labels follow
[E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md#labels).

## Principles

- A database record is **never** proof of cryptographic trust.
  - A `coupleId`, an invite token or a Firestore "paired" flag authorizes
    *server access*.
  - Cryptographic trust comes only from **verified Person Identity Keys
    (PIKs)** and **device certificates** that every device checks itself.
- Two independent people. Each controls their own PIK and devices.
  Pairing exchanges public identity only.
- Established mechanisms only:
  - MLS Add/Welcome for joining;
  - out-of-band fingerprint comparison for verification (as in Signal safety
    numbers and Matrix QR/SAS).

  No new key-exchange protocol is designed here.

## Device enrollment (own devices)

> **Superseded in part by D-074 (Prompt 08).** Each device keeps its own
> PIK; the existing device *signs an approval* of the new device instead of
> transferring the PIK private key (steps 1 and 4 below). The QR-based
> transfer channel is not needed. A six-digit comparison code on both screens
> binds the user's choice to the right device. Current design:
> [MULTI-DEVICE-TRUST §4](MULTI-DEVICE-TRUST.md#4-approval-handshake-d-075).

1. **First device:** generates the PIK, a device key and a device
   certificate, and creates the personal MLS group.
2. **Additional device (RECOMMENDED):**
   1. The new device shows a QR code containing:
      - its device signature public key;
      - a fresh random session secret;
      - a channel ID.
   2. An existing device scans it. A camera scan is an out-of-band
      authenticated channel, so no PAKE is designed here.
   3. The existing device signs a device certificate for the new key.
   4. It transfers the PIK private key to the new device over a channel
      encrypted with an established construction keyed by the scanned secret
      (exact construction **UNRESOLVED**; must use a reviewed library API,
      e.g. HPKE RFC 9180 to the new device's key).
   5. It commits an MLS Add of the new device to the personal group and the
      couple group.
3. **Recovery path:** if no existing device is available, use the recovery
   key ([RECOVERY-AND-REVOCATION](RECOVERY-AND-REVOCATION.md)).
4. **Unknown device rejection:** a KeyPackage or Add whose credential lacks
   a valid certificate from an expected PIK is rejected by every member's
   MLS authentication check, even if Firestore lists it.
5. **Visibility:** every device add or remove produces a Commit, and the UI
   announces it to *both* partners ("Bob added a new device"). This protects
   against covert monitoring.

## Pairing two people (RECOMMENDED)

```text
Alice (inviter)                          Server (Functions + Firestore)                 Bob (invitee)
 create invite ──────────────────────►  store H(token), alice uid, PIK_A fpr,
                                         expiry (e.g. 24 h), single-use
 show QR / link: {token, PIK_A fpr} ─────────────── out of band (in person or link) ──► scan / open
                                         redeem(token) by Bob's uid: atomic,
                                         first redeemer wins, rate-limited ◄──────────── redeem
                                         ─► links accounts (server-side only)
 fetch PIK_B + Bob device certs ◄──────  publish both public identities ───────────────► fetch PIK_A, compare
                                                                                         with fpr from QR
 verify PIK_B (see Verification) ...                                                     ... verify PIK_A
 create couple MLS group; Add all of
 Bob's certified devices (KeyPackages) ─► store Commit + Welcome (ciphertext) ──────────► join via Welcome
```

| Requirement | Design |
| --- | --- |
| Invitation generation | 128-bit random token from the device CSPRNG; server stores only a hash (SHA-256) + metadata |
| Expiration | Short TTL (24 h default, **UNRESOLVED**); expired invites can't be redeemed |
| Single use | Atomic redeem (Firestore transaction / Function); first redeemer wins; token deleted |
| Interception | An intercepted link lets an attacker *redeem*, but the inviter then sees an unexpected PIK and verification fails. Inviter must verify before content flows (see below). Redeem also requires the attacker to have an account and pass App Check and rate limits |
| Replay / reuse | Hash deleted on redeem; replays fail; one active invite per person |
| Concurrent attempts | Pairing state machine per account: `unpaired → invited → paired`; a person can't hold two active pairings; concurrent redeems resolved by transaction |
| Guessable IDs | `coupleId` and group IDs are random and grant nothing by themselves |

### Verification

- **In person (RECOMMENDED default when possible):**
  1. Bob scans Alice's QR, which includes her PIK fingerprint, so Bob
     verifies Alice.
  2. Alice scans a QR that Bob's device then shows with **his** PIK
     fingerprint, so Alice verifies Bob.

  Both directions are verified with no typing.
- **Remote:** TOFU (trust on first use) at pairing, shown as
  **"not yet verified"**. Partners compare a short safety number derived
  from both PIKs over a call or in person later.
- **Fingerprint format: UNRESOLVED.** Use a documented scheme (e.g. Signal's
  published numeric fingerprint format, or Matrix's SAS/QR verification
  method) rather than inventing one; needs review and licensing check.
- **Key changes:** if a partner's PIK changes, the relationship returns to
  "not verified" and the UI warns before any new content is sent.

## Device roster convergence

- **The authoritative roster** is the MLS group's membership. Every member
  computes the same tree and epoch authenticator, and an inconsistent server
  view causes Welcome/Commit processing to fail.
- **Firestore's device records** are a *directory* (where to find
  KeyPackages and FCM tokens), never the trust source.
- **Acceptance rule, run by every device before merging any Commit:**
  - each added leaf has a valid certificate chain to one of the two verified
    PIKs;
  - its device ID isn't revoked;
  - leaf keys match the certificate;
  - the group never contains credentials from a third PIK.
- **Concurrent changes:** handshake messages are serialized per epoch ("first
  Commit for epoch n wins"); a device whose Commit lost re-bases and retries.

## Unpairing and re-pairing (RECOMMENDED)

- Either person can unpair **unilaterally**. Their device commits Remove for
  all of the partner's leaves, then the group is abandoned.
- The server marks the couple dissolved. Rules then deny both accounts access
  to the old group's documents (except, if product allows, each person's own
  export window), and FCM fan-out stops.
- Nothing new can be encrypted to the ex-partner. Content already on their
  devices can't be recalled.
- **Re-pairing** (same or different person) always creates a **new** group
  with fresh verification.
- **Shared history after unpairing:** **UNRESOLVED** (product + legal).
- **Abuse considerations:**
  - instant unpair;
  - no "unpair needs consent";
  - presence/location features stop immediately;
  - the ex-partner gets no signal beyond "unpaired";
  - roster changes are always visible while paired, so neither person can
    covertly add a monitoring device.
