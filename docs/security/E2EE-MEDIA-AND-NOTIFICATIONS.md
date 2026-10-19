# Encrypted Media and Secure Notifications (Prompt 11)

Status: **Design gate and Phase 0 infrastructure. Implemented and tested in
the development environment only. Sirf Hum is NOT production E2EE.** Nothing
here has had an independent review. Cloud Storage and Cloud Functions need
the Blaze plan (D-025), so **deployment of every server part is BLOCKED**;
rules and Functions run in the emulator only. No media UI, no notification
UI.

Decisions: D-093 to D-099 in the [Decision Log](../decisions/DECISION-LOG.md).
Threats: E35–E46 in the [Threat Model](THREAT-MODEL.md) (the brief's E30–E40,
renumbered because Prompt 10 already used E30–E34).
Builds on [E2EE-MESSAGING-DESIGN](E2EE-MESSAGING-DESIGN.md) (D-085–D-091),
[CRYPTO-CORE-ARCHITECTURE](CRYPTO-CORE-ARCHITECTURE.md) and
[MULTI-DEVICE-TRUST](MULTI-DEVICE-TRUST.md). Supersedes the media rows of
[E2EE-ARCHITECTURE §7](E2EE-ARCHITECTURE.md) and its notification sketch (§9)
where they differ.

Scope: Android (D-092). Web has no private media and no push registration
(D-046): it fails closed. iOS is out of scope and untouched.

## 1. Where Prompt 11 plugs in

| Existing piece (Prompts 07–10) | Prompt 11 addition |
| --- | --- |
| Rust core, sealed records, `transact` rollback | `engine/media.rs`: file encryption/decryption, media payload (ABI v6) |
| MLS messages with Rust-built AAD (D-089) | Media keys travel **inside** an MLS message (`media_ref` payload, kind 2) |
| Sealed history record per message (D-090) | Holds the full `media_ref` (with key). Dart only ever gets a key-free view |
| `MessagingService` (outbox, sync) | `sendMedia`, `openMedia`; the outbox uploads the object before the message |
| `ConversationTransport` port | New `MediaStorage` port; `FirebaseMediaStorage` in infrastructure |
| Firestore rules (`conversations/*`) | Storage rules on `conversations/{c}/media/{m}` (cross-service reads) |
| Device proof of possession (D-070) | New purpose `push_token` (3) proves the device registers its own token |
| Device Functions + rate limits | `requestPushTokenChallenge`, `registerPushToken`; notification fan-out triggers |
| Device status lifecycle | A revocation trigger deletes the token and wakes the remaining devices |

## 2. Media encryption (D-093)

### Construction

No new primitive and no new library. The core already depends on
`chacha20poly1305 0.10.1`, which depends on `aead 0.5.2`. Prompt 11 enables
that crate's `stream` feature:

- **STREAM** (Hoang, Reyhanitabar, Rogaway, Vizár, *Online
  Authenticated-Encryption and its Nonce-Reuse Misuse-Resistance*, CRYPTO
  2015; ePrint 2015/189). It is proven nOAE-secure. The construction defends
  against chunk reordering, duplication and truncation. We use the RustCrypto
  `StreamBE32` instance: nonce = prefix ‖ chunk counter u32 BE ‖ last-chunk
  flag u8.
- **AEAD:** XChaCha20-Poly1305 (the same AEAD as the sealed records). Nonce 24
  bytes, so the STREAM prefix is 19 bytes.
- **Authenticated ciphertext digest:** SHA-256 of the whole object (header
  and every chunk with its tag), carried in the MLS-authenticated
  `media_ref` and checked before decryption. This is an integrity check
  against an already-authenticated expected value. It is **not** key
  commitment (D-093 review, F1). `sha2 0.10.9` is already compiled through
  `openmls_rust_crypto`; Prompt 11 adds it as an exact-pinned direct
  dependency.

Prompt 04 recommended libsodium `crypto_secretstream`, binding unresolved.
STREAM from the already-locked RustCrypto crate gives the same properties
(chunked, per-chunk authentication, truncation detection) without a second
native crypto library in the APK. Neither option is audited for the stream
construction itself. No audit of `aead::stream` is known, and libsodium's
published 2017 audit (1.0.12–1.0.13) **predates** `crypto_secretstream`,
which was added in 1.0.14. Full analysis:
[D-093-SECURITY-REVIEW](D-093-SECURITY-REVIEW.md).

| Parameter | Value |
| --- | --- |
| Key | 32 bytes, fresh per media object, OS CSPRNG (`OsRng`), `Zeroizing` in Rust |
| Nonce prefix | 19 random bytes per object, in the object header (a fresh key already makes nonces unique; the random prefix is defence in depth) |
| Chunk size | 65,536 plaintext bytes; every chunk carries a 16-byte tag; the last chunk is 1..65,536 bytes |
| Chunks | at most 1,024 (64 MiB); far below the 2³² STREAM limit |
| Max plaintext | **64 MiB** (`MAX_MEDIA_PLAINTEXT_BYTES`); empty media refused |
| Media ID | 16 random bytes generated in Rust (never derived from content) |

### Object format (format v1)

```text
header (25 B) = "SHMD" | format u16 BE = 1 | nonce prefix [19]
body          = chunk_0 ‖ … ‖ chunk_last      (each = XChaCha20-Poly1305 ciphertext ‖ tag)
size          = 25 + plaintext_len + 16 × ceil(plaintext_len / 65,536)
```

The size is a pure function of the plaintext length. Rust checks it before
decrypting anything.

### Associated data: STREAM's schedule

STREAM is the published construction's schedule (HRRV 2015, Fig. 8):
the **media AAD** below is the AD of the **first** chunk only, and **every
later chunk uses the empty AD**. The chunk's position (and so the binding of
later chunks to the same stream) comes from the STREAM nonce
`prefix ‖ be32(i) ‖ flag`, under the object's single fresh key.

*Pre-production correction (2026-10-19, D-093 review F4):* the first
implementation passed the media AAD to every chunk. That deviated from
Fig. 8, so Theorem 2 did not literally apply. It was corrected before any
release. **No compatibility mode exists:** objects written with the old
schedule (two or more chunks) fail to open (`authentication_failure`).
One-chunk objects are identical under both schedules. There is no
production data, so nothing needs migrating.

```text
media AAD (101 bytes) = "SirfHum-MediaAAD" | aad version u8 = 1 | media schema u16 = 1
| conversation id [16] | media id [16] | sender device id [16]
| media class u8 | plaintext length u64 BE | header [25]
```

Built only in Rust, never by the caller. On decryption every field comes
from the **sealed history record of the MLS message that delivered the
key**. That record's conversation and sender device were authenticated by
MLS (D-089). Because the first chunk carries it, and later chunks are
tied to that chunk by the stream's nonce sequence under one fresh key, an
object fails to decrypt unless it was encrypted:

- for this conversation;
- under this media ID;
- by the device that sent the key;
- with this class, length and header.

Any mismatch is `authentication_failure`: fail closed, no partial plaintext.

### The `media_ref` payload (inside MLS only)

```text
version u8 = 1 | kind u8 = 2 | client time ms u64 | media id [16] | class u8
| plaintext length u64 | ciphertext length u64 | ciphertext SHA-256 [32] | key [32]
= 107 bytes
```

Kinds: 1 = text (built by Dart, unchanged), 2 = media (built **only** by
Rust). `send_message` refuses a Dart payload that claims kind 2, so every
media key is generated inside the core.

**Public view (what Dart sees):** the first 43 bytes (version, kind, time,
media ID, class, both lengths), without the hash and key.
`receive_message` and `history` return the view for kind-2 payloads. Media
keys never cross the FFI. They go Rust → sealed history → MLS ciphertext →
Rust.

Media class (`image` 1, `video` 2, `audio` 3, `file` 4) exists only inside
the encrypted payload and the AAD, never on the server.

### D-093 review brief (for human security review)

**Status: APPROVED FOR PRE-PRODUCTION IMPLEMENTATION** (human security
review, 2026-10-19). **NOT independently reviewed, NOT audited, NOT approved
for production.** `aead::stream` remains unaudited. Investigation:
[D-093-SECURITY-REVIEW](D-093-SECURITY-REVIEW.md). Nothing below claims an audit of the STREAM implementation, and
no audit should be inferred. Every fact was checked against the pinned
sources in `Cargo.lock` on 2026-10-19.

| Question | Answer |
| --- | --- |
| Implementation | RustCrypto **`aead` 0.5.2**, module `aead::stream`, type **`StreamBE32`** (`EncryptorBE32` / `DecryptorBE32`), in-place API. Enabled through the `stream` feature of **`chacha20poly1305` 0.10.1** (`chacha20 0.9.1`, `poly1305 0.8.0`). Lockfile checksums: `aead` `d122413f…62b0`, `chacha20poly1305` `10cd7943…dc35`. SHA-256: **`sha2` 0.10.9** (`a7507d81…b283`). All are exact pins, already in OpenMLS' dependency tree; no crate was added to the lockfile. Code: `packages/sirf_hum_crypto/native/src/engine/media.rs` |
| Source of the construction | STREAM, "Rogaway-flavoured": Hoang, Reyhanitabar, Rogaway, Vizár, *Online Authenticated-Encryption and its Nonce-Reuse Misuse-Resistance*, CRYPTO 2015, ePrint 2015/189 (§7, Fig. 8, Theorem 2; read from the co-author's copy, see [D-093-SECURITY-REVIEW §13](D-093-SECURITY-REVIEW.md)). `StreamBE32` as used matches the paper's nonce encoding (`N ‖ i ‖ d`, with i counted from 0 as `be32(i−1)`), final flag, state machine and **AD schedule (A on the first segment, ε afterwards)**. The AD schedule was corrected before release (F4, [review §14](D-093-SECURITY-REVIEW.md)) |
| Independent audit of the implementation | **None known for `aead::stream`.** The `chacha20poly1305` README cites one NCC Group review (published 2020-02-26, "RustCrypto AES-GCM and ChaCha20+Poly1305 implementation review"). It predates 0.10.1 and did not cover the `aead::stream` module, so we claim **no** audit for the version or the module we use. Our use of it (format, AAD, composition) is also unreviewed. For comparison, libsodium's 2017 audit (1.0.12–1.0.13) also predates `crypto_secretstream` (added in 1.0.14), so neither stream construction has a known audit (finding F2) |
| Security properties (Theorem 2, which now applies to the implemented schedule) | nOAE, nonce-based online authenticated encryption, assuming XChaCha20-Poly1305 is a secure nonce-based AEAD, the encoding is injective, and no stream nonce repeats under a key: confidentiality of each chunk and integrity of the **whole segmented message**, including chunk order, no duplication, no deletion and no truncation (the last-block flag). The paper proves properties of STREAM only, not of Sirf Hum's AAD contents, object digest or MLS key transport. Not provided: nonce-misuse resistance; key commitment; hiding of length (exact sizes are visible, E45) |
| Key commitment | **Not provided** by the AEAD (ChaCha20-Poly1305 is not key-committing), and **not provided by the SHA-256 digest either**: the digest is an *authenticated ciphertext digest* (an integrity check against an expected value that MLS already authenticated). Key commitment is unnecessary here for a different reason. The key and the digest arrive together in one MLS-signed reference that every member receives identically, so every recipient decrypts exactly that object with exactly that key. Key substitution is prevented by MLS authentication of the reference, not by the hash. See [D-093-SECURITY-REVIEW §6](D-093-SECURITY-REVIEW.md) (finding F1) |
| Nonce generation and uniqueness | 24-byte XChaCha20 nonce = **19-byte prefix** ‖ **u32 BE chunk counter** ‖ **last-block flag byte**. The prefix comes from `OsRng` per object and is stored in the header. Uniqueness comes from the **key**: every object has a fresh 32-byte `OsRng` key and is encrypted exactly once, so within a key each (counter, flag) pair is used once (the counter starts at 0 and only increases; the flag is 1 only on the final chunk). The random prefix is defence in depth, not what uniqueness relies on. Re-sending a queued message re-encrypts only the small MLS message, never the object |
| Chunk ordering and integrity | Each chunk is a separate XChaCha20-Poly1305 encryption with a 16-byte tag, under the nonce for its position. A reordered, repeated or swapped chunk decrypts under the wrong nonce and fails its tag. Tested both with and without the hash check (`media.rs` unit tests bypass the hash on purpose) |
| Finalization and truncation | The final chunk alone is encrypted with flag = 1 (`encrypt_last_in_place`), and the decryptor demands flag = 1 at the expected final position. Dropping trailing chunks makes the new last chunk fail (it was sealed with flag 0); tested with the hash bypassed. Before decrypting we also check: exact size = `25 + len + 16·⌈len/64 KiB⌉`, SHA-256, magic and format version. Bytes after the final chunk cannot pass the size check |
| AAD | The **first chunk** carries the media AAD; **every later chunk uses the empty AD** (STREAM's published schedule; corrected before release, F4). The media AAD is built only in Rust: `"SirfHum-MediaAAD"` ‖ AAD version u8 = 1 ‖ media schema u16 BE = 1 ‖ conversation ID[16] ‖ media ID[16] ‖ sender device ID[16] ‖ media class u8 ‖ plaintext length u64 BE ‖ header[25] (`"SHMD"` ‖ format u16 BE = 1 ‖ nonce prefix[19]). On decryption every field comes from the sealed history record of the MLS message that delivered the key (MLS-authenticated conversation and sender). Fixed-width fields only, so the encoding is unambiguous. Golden vector shared by Rust tests |
| Key lifecycle | **Generated:** 32 bytes from `OsRng` in `send_media`, held in `Zeroizing`. **Used:** once, to encrypt one object. **Delivered:** only inside the `media_ref` MLS application message (MLS encryption and signature, D-089 AAD). **Stored:** in the sealed history record (kind 5, platform store key) on the sender and on every recipient device. **Never:** returned over the FFI, given to Dart, written to Firestore or Storage, logged, or rotated. **Destroyed:** zeroized in memory after use; on disk when the history record is deleted ("delete for me") or the account slot is removed (crypto-erasure: store key first) |
| Maximum size | Construction: 2³² − 1 chunks (the counter limit; the crate refuses past it) × 64 KiB, about 256 TiB. **Implementation limit: 64 MiB plaintext** (1,024 chunks; object ≤ 67,125,273 B), enforced before reading; empty input refused. The limit exists because decryption returns memory, not because of the construction |
| Custom composition around STREAM | **Yes, and it is the part most in need of review:** (1) the object format (header, chunk layout) and the binding of the header into the AAD; (2) the AAD encoding and its fields; (3) the authenticated SHA-256 ciphertext digest, checked before decryption (an integrity check, not key commitment); (4) key transport inside an MLS application message, and the rule that the AAD's sender is the MLS sender of that message; (5) two-pass decryption (hash, then decrypt) with a re-opened file. **No new primitive** is designed: no own cipher, MAC, KDF, nonce scheme or chunking logic. Chunking and nonces are the crate's STREAM |

**Open for review:**
- Is STREAM from an unaudited module acceptable? libsodium `secretstream` is not covered by libsodium's 2017 audit either, and would add a second native library.
- Confirm the analysis that key commitment is unnecessary because the key and object digest arrive in one authenticated reference ([D-093-SECURITY-REVIEW §6](D-093-SECURITY-REVIEW.md)).
- Should the AAD include the format version separately from the header (it is inside the header today)?
- Size padding (D-099).

- F4 (AD schedule) was resolved by option (b): the implementation now follows the paper's schedule ([review §14](D-093-SECURITY-REVIEW.md)). The adapted-proof discussion of §13.6 is no longer needed for the design. Review the change itself as part of the sign-off.

D-093 stays as recorded until that review; it is not replaced yet.

## 3. Key lifecycle and the model evaluated (D-094)

```mermaid
sequenceDiagram
    participant A as Device A (Rust core)
    participant S as Cloud Storage (rules)
    participant F as Firestore (rules)
    participant B as Device B (Rust core)
    A->>A: send_media: key, media ID, prefix ← CSPRNG; STREAM-encrypt file → media dir/<conv>_<media>.shm (temp + rename); SHA-256
    A->>A: same call: media_ref (with key) → MLS encrypt (AAD D-089) → sealed history (queued)
    A->>S: create conversations/{c}/media/{m} (create-only, member, active device, size cap)
    A->>F: messages/{id} transaction (D-088/D-089), as for text
    B->>F: sync: receive_message → MLS verify/decrypt → full media_ref sealed; Dart gets the view
    B->>S: download object (member) → local .shm cache
    B->>B: open_media: size == ref, SHA-256 == ref, STREAM-decrypt with AAD from history → plaintext (memory only)
```

The prompt's suggested model, evaluated:

| Attack | Outcome | Why |
| --- | --- | --- |
| Replay of the `media_ref` message | Dropped | MLS generation keys and history dedupe by message ID (D-091) |
| Message substitution (server swaps envelope) | Rejected | D-089 AAD binding inside MLS |
| Object substitution / modification (malicious server or storage) | `authentication_failure` before decryption | authenticated SHA-256 object digest in the signed MLS payload; AEAD per chunk |
| Media key substitution | Impossible for the server | The key is inside MLS ciphertext; a malicious *member* can only send its own broken ref (DoS of its own message) |
| Cross-conversation reuse of an object | Rejected | Conversation ID in the AAD; Storage path and rules per conversation |
| Re-attribution (a member re-sends the partner's ref as its own) | Rejected | The sender device in the AAD must equal the MLS sender of the delivering message |
| Cross-account access | Denied | Rules: members only. Without the key the bytes are useless anyway |
| Revoked device | No **new** keys | MLS (§9 of the messaging design). Keys it already received stay with it |
| Deleted or not-yet-uploaded object | `media_unavailable`, retry later | Never fake content |
| Stale reference after re-encryption | Same object, same key | Re-encrypting a queued message (D-091) re-sends the same ref |
| Compromised storage dump | Ciphertext + sizes only | Keys are never on the server |
| Unauthorized device of a member account | Can download ciphertext | Storage rules cannot see devices on reads (as for Firestore); the key comes only through MLS |
| Metadata | §5 | |

**Decision:** keep the model (random per-object key delivered in an MLS
message), with three refinements:

1. Rust generates and keeps the key.
2. The AAD binds the delivering message's sender.
3. The ciphertext hash is committed in the signed payload.

## 4. Storage model and rules (D-095)

- **Path:** `conversations/{conversationId}/media/{mediaId}` (both 32 lowercase
  hex). Opaque; no filename, extension or class.
- **No Firestore media document.** The `media_ref` already carries
  everything the recipient needs. A routing document would add metadata
  without adding security.
- **Object metadata:** `contentType = application/octet-stream`. One custom
  field `sd` (uploading device ID), which the rules need to check that the
  device is `active`. Device IDs are already visible on message envelopes.
  Nothing else; `cacheControl` is not set.

| Operation | Rule |
| --- | --- |
| `get` (download, metadata) | Signed in **and** a member of the conversation (`firestore.get(conversations/{c}).members`) |
| `list` | Denied (no enumeration) |
| `create` | Member of an **active** conversation; `sd` names an `active` device of the caller's own account; object did not exist; size 1..67,125,273 B (64 MiB + overhead); content type exactly `application/octet-stream`; metadata keys exactly `{sd}`; IDs match the hex pattern |
| `update` (overwrite or metadata change) | Denied. Objects are immutable |
| `delete` | Denied (server-side retention deferred) |
| Everything else | Default deny |

Rules authorize access to ciphertext; the application layer supplies
confidentiality and integrity. Rules are tested in the Storage + Firestore
emulators. They need Blaze to deploy (a Cloud Storage bucket needs Blaze).
Cross-service rules also need the Storage service agent's Firestore read
permission, granted on first deploy.

**Uploads.** The Firebase SDK upload is resumable within one app session. A
crash or restart starts the object again from the sealed outbox. The object
appears only when an upload completes. If an earlier attempt landed but its
acknowledgement was lost, the create-only rule refuses the retry. The client
then reads the object's metadata: same size and `sd` = this device means
uploaded. Anything else is `rejected`. A wrong object at our path cannot
decrypt anyway (hash, AAD).

**Order.** The object is uploaded before the `media_ref` message. A
recipient that sees the reference first (eventual consistency) gets
`media_unavailable` and retries.

**Deletion and expiry.** Not in Phase 0. A missing object is
`media_unavailable`. "Delete for me" removes the local record and cached
file only. Server retention and remote deletion need a Function (Blaze) and
a product decision.

## 5. Metadata (minimised, not hidden)

| The server learns | Avoided |
| --- | --- |
| That an object exists in a conversation; its exact ciphertext size (≈ plaintext size + 25 B + 16 B per 64 KiB); upload time; uploader device ID and account (via auth/IP); that a message followed | Filename, extension, MIME type or class, caption, EXIF, dimensions, duration, thumbnails, keys, hashes of plaintext |

The MLS ciphertext of a `media_ref` has a constant size, so the message
document could hint that it carries media. The upload timing reveals the
same thing anyway.

**Residual (E45):** exact sizes. Padding to size buckets is deferred
(format v2 can add it without changing keys or AAD layout). It needs a
review of the scheme.

**EXIF:** it never reaches the server in clear (it is inside the
ciphertext). Stripping it before sending, so the *partner* does not get
location data, is a media-UI decision, deferred and noted.

## 6. Thumbnails and previews (D-099)

**Deferred.** No server-side thumbnails, ever. Functions never receive
media. When previews arrive, they will be generated on device and encrypted
as their own objects under their own keys with this same construction.
Notifications never carry previews.

## 7. Local media security (D-096)

| Topic | Behaviour |
| --- | --- |
| Cache | **Ciphertext only**: `<account slot>/media/<conversation>_<media>.shm`. The slot directory is per account and in `noBackupFilesDir` (D-066) |
| Cache key protection | No separate cache key: the cached object is the transport ciphertext, and its key lives only in the sealed history record (platform store key) |
| Plaintext at rest | **Never written by the app.** `open_media` decrypts to memory (≤ 64 MiB) and returns it for rendering. Native copies are wiped; the Dart copy is wiped by the caller where possible (GC limit, CRYPTO-CORE-ARCHITECTURE) |
| Input files | `send_media` reads the plaintext from the path the caller gives (e.g. a picker file the OS owns) and never copies it in the clear |
| Write atomicity | The core names the object itself (`<conversation hex>_<media hex>.shm` in the media directory the caller passes), so a queued message's object can always be found again. Ciphertext goes to a temp file, then fsync, then rename, **before** the message is queued. If the MLS step fails, the file is deleted; a crash in between leaves only an orphan object, never a message without its object. A queued message whose object was lost locally and never uploaded is dropped from the outbox (`media_send_abandoned`) |
| Corruption | Hash or AEAD failure deletes the cached file and downloads again once; then `media_corrupted` |
| Wrong account | Another account's core has no history record for the message: `invalid_input`; its slot key cannot open the other slot |
| Lifetime | Until "delete for me" (record + file) or account removal (slot deleted recursively, key first) |
| Logout | Slot stays sealed (D-071); the cache is useless without the slot key |
| Revoked device | `sendMedia` refuses, and so does every new download (`deviceNotTrusted`): Storage rules cannot tell devices apart on reads, so the client enforces this itself. Media already **cached** stays openable on that device, like its text history: the keys and ciphertext are already there, so refusing would protect nothing against a modified app. It stays until the user removes the account (crypto-erasure). Revocation **cannot** delete plaintext a user already exported or screenshotted |

## 8. Notifications (D-097)

### Principle

FCM is outside the trust boundary (TB4). A push is a **content-free wake-up**.
The device then syncs and decrypts locally. The server decides who gets a
wake-up from routing metadata it already has (accounts, devices, statuses);
it never reads ciphertext, keys or plaintext.

### Payload (complete; nothing else is ever sent)

```json
{
  "token": "<device FCM token>",
  "data": { "v": "1", "k": "m" },
  "android": {
    "priority": "high",
    "collapseKey": "sh_m",
    "notification": { "title": "Sirf Hum", "body": "You have a new message", "tag": "sh", "visibility": "private" }
  }
}
```

| Kind `k` | When | To | Visible |
| --- | --- | --- | --- |
| `m` (message) | A message document is created | Active devices of the **other** member account | Yes: the generic text above |
| `s` (sync) | A message (sender's own other devices), a commit (all active devices except the committer), a device revocation (remaining active devices of the account and its partner) | As listed | No: data-only, normal priority |

- No conversation, message, media, device or account IDs.
- No names, no counts, no ciphertext, no previews.
- No topics: per-device tokens only, so there is no server-side group
  membership. Collapse keys are constants. The notification tag is a constant,
  so a new notification replaces the old one.
- No `apns` or `webpush` blocks (iOS out of scope; Web has no registration).
- Wording: "Sirf Hum" and "You have a new message". Neither names a person
  nor shows content. `visibility: private` hides even that on a secure lock
  screen. Showing it on Android 13+ needs the POST_NOTIFICATIONS
  permission. Requesting that permission is UI work, deferred.

### Fan-out (Functions, `functions/src/notification/`)

Firestore triggers (Blaze, emulator-tested as pure functions):

- `onConversationMessageCreated` (`conversations/{c}/messages/{m}`);
- `onConversationCommitCreated` (`.../commits/{e}`);
- `onDeviceStatusChanged` (`users/{u}/devices/{d}`).

Each handler reads only `senderAccountId` / `senderDeviceId` / `status`. The
event snapshot contains ciphertext (Firestore delivers whole documents). The
handler never reads, copies or logs it. Recipients are computed from the
conversation's `members` and each account's devices **whose server status is
`active` right now**. Logs carry counts and categories only.

## 9. Push token lifecycle (D-098)

Tokens are delivery addresses, never identity. The device's certificate and
server status stay authoritative.

| Event | Behaviour |
| --- | --- |
| Registration | `requestPushTokenChallenge({deviceId, tokenHash})` issues a single-use challenge bound to `sha256(token)` (or to clearing). The device signs it with its device key (`ProofPurpose.push_token = 3`, D-070 format). `registerPushToken({deviceId, challengeId, token, proof})` then verifies, in one transaction: challenge (account, device, purpose, expiry, hash), device `active`, proof against the stored certificate. It writes `pushTokens/{deviceId}` = `{accountId, deviceId, token, updatedAt}` |
| Why a proof | A password alone (E24) must not redirect another device's wake-ups or silence them |
| One token, one device | Registering a token deletes every other `pushTokens` document holding the same token. This covers the same install switching accounts: account A's wake-ups never reach account B's session |
| Rotation (`onTokenRefresh`) | Register again; the document is replaced |
| Logout | Signed clear (`token: null`), then `deleteToken()` locally. If offline, the local `deleteToken()` makes FCM refuse the old token, and the server deletes it on the next send |
| Device revoked / identity reset | The trigger deletes `pushTokens/{deviceId}` at once. Fan-out sends only to devices that are `active` at send time, so a stale document is never used |
| Pending / rejected / expired device | Cannot register (must be `active`); never targeted |
| Newly approved device | Registers after activation |
| Reinstall | New device identity and new token. The old device's token becomes invalid at FCM (uninstall) and is deleted on the first failed send |
| Invalid / unregistered token | FCM `registration-token-not-registered` / `invalid-registration-token` → document deleted |
| Stale token | `updatedAt` older than 60 days → skipped and deleted. Clients re-register on start |
| Multiple devices | One document per device ID |
| Storage | `pushTokens/*` is server-only (rules deny every client read and write). Partners never see tokens |
| Rate limits | `pushToken`: 20 per hour per account; failed proofs count against the shared failure budget (D-077) |
| Web | No device identity → no registration (fails closed) |

## 10. Revocation interaction

| Situation | What happens | What revocation cannot do |
| --- | --- | --- |
| Device revoked | Writes (Firestore, Storage create) refused at once. Token deleted. Remaining devices get `s` and refresh lineage, so the E33 window shrinks to push latency. They stage the MLS Remove | It cannot stop the revoked device reading **ciphertext** its account can still read, until the Remove. Firebase reads are per account |
| Media uploaded before revocation | The object stays; members can fetch it | — |
| `media_ref` received before revocation | The revoked device has the key and may already have the plaintext | No remote deletion of downloaded plaintext or keys |
| `media_ref` sent after revocation | Senders refuse to encrypt while the roster holds an untrusted device (D-085). After the Remove it cannot decrypt the new epoch | — |
| Notification generated before revocation | May still arrive: content-free, so it reveals timing only | — |
| Old token, references, cached ciphertext, MLS state | None of them grants new access. Tokens are not identity, references need keys, keys come only through MLS, and old MLS state cannot decrypt epochs after the Remove | — |
| Pending device | No token, no Storage writes, no keys | — |
| Identity reset / recovery | Reset revokes the old devices (tokens deleted, `s` sent). A recovered device is a new device: it registers its own token and gets only new epochs (no history) | — |

## 11. Failure states

| Failure | Category (Dart) | Retry |
| --- | --- | --- |
| Input file missing, empty, over 64 MiB, or changed size while being read | `MediaFailure.invalidInput` / `tooLarge` | No |
| Outbox full / not joined / commit pending / untrusted member / device not active | existing `MessagingFailure` | As for text |
| Upload interrupted / offline | `SendOutcome.queued` (object + message stay in the sealed outbox) | `flushOutbox` |
| Upload refused (not member, device revoked, size) | `MessagingFailure.rejected` | No |
| Duplicate upload (ack lost) | Treated as uploaded after the metadata check | — |
| Object missing (not yet uploaded, deleted) | `MediaFailure.unavailable` | Later |
| Download interrupted | Temp file discarded; `MediaFailure.unavailable` | Later |
| Download larger than the ref says | Refused before writing; `MediaFailure.corrupted` | No |
| Hash or AEAD failure, truncated object | Cache deleted, one re-download, then `MediaFailure.corrupted` | No |
| Message is not media / not in history (wrong account, deleted) | `MediaFailure.notMedia` | No |
| Local state corruption | `state_corruption` surfaces (never counted as a bad message) | — |
| Push token proof invalid / challenge expired | Category errors from the callable | New challenge |

## 12. Security invariants (tested)

1. Media plaintext and media keys never leave the device. The server holds
   only ciphertext objects. Keys exist in Rust memory, in sealed history and
   inside MLS ciphertext.
2. Media keys never cross the FFI. Dart sees a 43-byte public view.
   `send_message` refuses kind-2 payloads from Dart.
3. A media object decrypts only for the conversation, media ID, sender
   device, class and length of the authenticated message that delivered its
   key, and only if its SHA-256 matches. Otherwise it fails closed with no
   partial plaintext.
4. The app never writes media plaintext to disk. The cache holds ciphertext
   only, per account slot, backup-excluded.
5. Storage objects are create-only, member-readable, written only by an
   active device of a member account, opaque in name and content type.
6. Push payloads are constant except for the token and the kind. They
   contain no identifiers, text or ciphertext.
7. Only devices `active` at send time are targeted. A token is registered
   only with a fresh proof from that device's key. One token maps to one
   device.
8. Functions and logs never contain plaintext, keys, tokens, ciphertext or
   identifiers (counts and categories only).
9. Web and iOS: no private media, no token registration.

**Unaudited:** the media format, AAD, `aead::stream` usage, the payload
format, ABI v6, Storage rules, the push-token protocol and the fan-out. The
D-054 review conditions remain open. **No security claim may be made.**

## 13. Tests (map)

| Area | Where |
| --- | --- |
| Media core: round trip, tampering (header, chunk, tag, swap, reorder, truncate, extend), wrong key / media / conversation / sender / schema / class / length, hash, limits, replay, re-attribution, wrong account, revoked sender/recipient, golden vectors, baseline | `native/src/engine/media.rs` (unit), `native/tests/media.rs` |
| FFI / Dart bindings, key-free view, Web stub | `packages/sirf_hum_crypto/test/media_*_test.dart` |
| Service: outbox order, interrupted upload/download, duplicate upload, stale reference, corrupted cache, wrong account cache, revoked device | `test/security/media/media_service_test.dart` (real cores, fake object store) |
| Storage rules | `firebase/tests/storage/media_storage.test.js` |
| Push tokens: Firestore rules | `firebase/tests/push_tokens.test.js` |
| Push: payload, no plaintext, no identifiers, log guard | `functions/test/notification.test.mjs` |
| Push: registration, rotation, one-token-one-device, revocation, reset, stale cleanup, multiple devices | `functions/test/emulator/notification.test.mjs` |
| Dart push registrar and signals | `test/security/notifications/push_tokens_test.dart` |
| Android device | `integration_test/media_test.dart` (platform key store, baseline) |

## 14. Performance

Recorded in [E2EE-TEST-PLAN](../testing/E2EE-TEST-PLAN.md) §Prompt 11:

- host figures from `native/tests/media.rs` (`media_baseline`);
- Android emulator figures from the integration test log.

Memory is O(chunk) while encrypting (streamed file to file). While
decrypting it is O(plaintext) plus one chunk: two streamed passes (hash,
then decrypt) into a buffer the size of the plaintext.

## 15. Known limitations

- Not reviewed; not production E2EE; deployment BLOCKED (Blaze: Storage
  bucket, Functions, Firestore triggers, FCM sends).
- Exact object sizes are visible (no padding yet).
- No thumbnails, no streaming playback (whole object decrypted to memory,
  64 MiB cap), no server-side retention or remote deletion.
- New devices cannot open media sent before they joined (no history, as for
  text).
- Uploads restart from zero after an app restart (no persisted resumable
  session).
- A revoked device with its account's session can download ciphertext until
  peers remove it from MLS. It only gains keys for messages it can decrypt.
- POST_NOTIFICATIONS permission, notification channels, quiet hours and
  per-category preferences are UI work, deferred. Background handling of
  `s` only acts while the app runs; otherwise the device catches up on
  resume.
- Notification timing is visible to Google (FCM) and to anyone looking at
  the lock screen.
