# `lib/security` — client security boundary

Everything that touches private-content confidentiality on the device lives
here. Full requirements: `docs/security/E2EE-REQUIREMENTS.md` and
`docs/security/THREAT-MODEL.md`.

| Folder    | Owns                                                         | Status (Prompt 06) |
| --------- | ------------------------------------------------------------ | ------------------ |
| `crypto/` | `EncryptedEnvelope` boundary type; `privateContentCryptoSupport()` over `package:sirf_hum_crypto` (Rust core, Prompt 06) | Core bundled; **development only** (unreviewed) |
| `device/` | Device identity (per-account slots), `DeviceKeyStore` port, status state machine, registration flow (DEVICE-IDENTITY.md) | Implemented (Prompt 07); activation server emulator-only |
| `couple/` | `PairingService` (device-signed pairing steps, purpose 4), `PairingBackend` port, strict `PairingState` (COUPLE-AND-PAIRING.md) | Implemented (Prompt 12); server emulator-only, no UI |
| `moments/` | Moments over messaging + media: `MomentPayload` (kind 3), `assembleMoments` (timeline rules), `MomentsService` / `MomentsBackend` (MOMENTS-ARCHITECTURE.md) | Implemented (Prompt 15); **development only**, no production backend, not reviewed |
| `messaging/` | Text messaging over the ABI v5 core: `MessagingService` (lineage trust, per-epoch sync, staged commits, sealed outbox), `EncryptedMessageEnvelope`, `TextPayload`, `ConversationTransport` port (E2EE-MESSAGING-DESIGN.md) | Implemented (Prompt 10); **development only**, no UI, not reviewed |

Rules:

1. Only this layer sees plaintext private content on its way to or from the
   network. `lib/infrastructure` receives `EncryptedEnvelope`s, never
   plaintext private content.
2. No custom cryptographic algorithms. All cryptography goes through
   `package:sirf_hum_crypto` (OpenMLS 0.9.1, D-054); see
   `docs/security/CRYPTO-CORE-ARCHITECTURE.md`.
3. Private keys never leave the device in plaintext and are never logged.
4. Nothing in this folder may claim E2EE in user-facing copy until the E2EE
   phase is implemented and reviewed.
