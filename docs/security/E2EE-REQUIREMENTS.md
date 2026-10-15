# End-to-End Encryption Requirements

Status: **Requirements only (Prompt 01). No cryptography is implemented.**
Sirf Hum is **not** end-to-end encrypted today and must not say it is.

## Goal

The backend must not become a trusted plaintext repository for private
relationship content.

```text
USER DEVICE → LOCAL ENCRYPTION → ENCRYPTED PAYLOAD → SERVER / STORAGE
           → ENCRYPTED PAYLOAD → RECIPIENT DEVICE → LOCAL DECRYPTION
```

## Scope: content intended for E2EE

| Content | Target |
| --- | --- |
| Private messages (text, reactions) | E2EE |
| Photos, videos, voice messages, voice memories | E2EE (media + thumbnails + metadata like captions) |
| Letters, private vault content, private memories | E2EE |
| Realtime call media | E2EE where practical (LiveKit frame encryption); evaluated in calls phase |
| Plans / Future items | To be classified in the Future phase (default: treat as private) |

## Non-negotiables

1. **No invented cryptography.** Only established primitives, protocols and
   mature, maintained libraries. No home-made ciphers, KDFs, or protocols.
2. **Private keys never leave the device in plaintext** and are never logged,
   sent to analytics, or included in crash reports.
3. **Servers never hold content keys.** Cloud Functions operate on metadata.
4. **Versioned envelopes.** Every ciphertext carries a protocol version so
   algorithms can be migrated (implemented: `EncryptedEnvelope.protocolVersion`).
5. **No E2EE claim without implementation + review** of that feature.
6. **Plaintext boundary in code:** only `lib/security/` sees plaintext
   private content on the network path; `lib/infrastructure/` accepts only
   `EncryptedEnvelope` for private content.

## Identity model

```text
PERSON → ACCOUNT → DEVICE(S) → CRYPTOGRAPHIC IDENTITY → COUPLE → PRIVATE CONTENT
```

- Each person has an independent account and cryptographic identity.
- Each device has its own key pair; a person's identity vouches for their
  devices.
- A couple is a relationship between two identities, not a shared account.
- Pairing never grants one partner access to the other's account, devices or
  keys.

## What the dedicated E2EE phase must decide and document

Before any implementation, a design document and Decision Log entries must
cover each item below. A protocol is not "secure" until all are documented.

| Topic | Questions to answer |
| --- | --- |
| **Threat model** | Which actors in [THREAT-MODEL](THREAT-MODEL.md) are in scope; what is explicitly out of scope |
| **Protocol choice** | Evaluate established options (e.g. Signal protocol family — X3DH/PQXDH + Double Ratchet; MLS (RFC 9420) for multi-device group state). Two people × N devices is effectively a small group. Choose, don't invent. |
| **Library choice** | Mature, audited implementations usable from Flutter on Android, iOS **and Web** (native FFI vs. platform channels vs. WASM). Licence compatibility. |
| **Key generation & storage** | Android Keystore, iOS Keychain/Secure Enclave, web storage limitations |
| **Key exchange** | How devices discover and verify each other's keys; key directory in Firestore; signatures |
| **Verification** | How partners can verify each other (safety numbers / QR) without friction; defaults |
| **Key rotation** | Forward secrecy, post-compromise security, scheduled and event-driven rotation |
| **Multi-device** | Adding a device, syncing history to new devices (or not), per-device sessions |
| **Revocation** | Removing a lost/stolen device; what it can still read; server enforcement |
| **Recovery** | Lost all devices: recovery key / passphrase / encrypted backup — trade-off between recoverability and server knowledge, explained to users in plain language |
| **Media** | A separate key per file; chunked and resumable encrypted uploads; thumbnails; streaming |
| **Unpairing** | Key consequences when a couple separates; abusive-partner considerations |
| **Calls** | LiveKit E2EE key distribution via Sirf Hum keys |
| **Notifications** | On-device decryption for previews, if ever allowed |
| **Metadata** | What remains visible (who, when, size); mitigations (padding) |
| **Testing** | Known-answer test vectors, interop between platforms, negative tests (tampering, replay, wrong key, revoked device) |
| **Review** | Independent cryptographic review before claiming E2EE publicly |

## Transport and access control are separate layers

| Layer | Protects against | Does **not** protect against |
| --- | --- | --- |
| TLS | Network eavesdroppers | Server, database, admin, cloud compromise |
| Firebase Auth + Security Rules | Other users, unauthenticated access | Server/admin/cloud compromise, legal compulsion of the operator |
| **E2EE** | All of the above, including the operator | Compromised endpoint device, metadata analysis |
