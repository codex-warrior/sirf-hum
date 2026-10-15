# `lib/security` — client security boundary

Everything that touches private-content confidentiality on the device lives
here. Full requirements: `docs/security/E2EE-REQUIREMENTS.md` and
`docs/security/THREAT-MODEL.md`.

| Folder    | Owns                                                         | Status (Prompt 01) |
| --------- | ------------------------------------------------------------ | ------------------ |
| `crypto/` | Encryption/decryption, the `EncryptedEnvelope` boundary type | Boundary type only |
| `keys/`   | Device identity keys, secure key storage, rotation           | Not started        |

Rules:

1. Only this layer sees plaintext private content on its way to or from the
   network. `lib/infrastructure` receives `EncryptedEnvelope`s, never
   plaintext private content.
2. No custom cryptographic algorithms. Use established, audited libraries
   and protocols chosen in the dedicated E2EE phase.
3. Private keys never leave the device in plaintext and are never logged.
4. Nothing in this folder may claim E2EE in user-facing copy until the E2EE
   phase is implemented and reviewed.
