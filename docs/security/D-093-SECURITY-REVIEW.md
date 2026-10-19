# D-093 Security Review: Media Encryption Construction

**D-093 status: PROPOSED — PENDING HUMAN SECURITY REVIEW.** This document is
an internal engineering investigation. It is **not** an independent review
or an audit, and it does not approve D-093. Nothing here establishes that
the construction is "secure" in a production sense.

- Date: 2026-10-19. Scope: PR #10 at commit `251a53d`
  (`packages/sirf_hum_crypto/native/src/engine/media.rs` and the parts of
  the core it relies on).
- Method: read the lockfile, the pinned dependency source and our code, and
  verify the nonce layout empirically (§3).
- No implementation code was changed. A temporary, uncommitted unit test
  was used for §3 and reverted.

Labels used below: **VERIFIED (source)** means read in the pinned source.
**VERIFIED (test)** means demonstrated by a test run in this review or in
CI. **ARGUED** means a reasoning step from stated assumptions. **NOT
ESTABLISHED** means it could not be confirmed here.

## 1. Executive verdict

The construction is a direct use of an established design, with a small
amount of our own composition on top.

| Question | Answer | Basis |
| --- | --- | --- |
| Does the code use STREAM as its crate documents it? | Yes. Stateless nonce derivation `prefix ‖ i ‖ flag`, the counter starts at 0, the final chunk alone carries flag 1, `next` refuses at the maximum counter, and `last` consumes the encryptor or decryptor | VERIFIED (source, test) |
| Is nonce uniqueness sound? | Yes, because every object gets a fresh random key and is encrypted once. Within an object each (index, flag) pair is used once. Collision probabilities are bounded below, not "impossible" | ARGUED from the code paths in §4 |
| Order, truncation and duplication | Detected, by the per-chunk AEAD under position-specific nonces plus the authenticated chunk count | VERIFIED (test), ARGUED |
| Composition (AAD, object digest, MLS key transport) | Sound for v1. Every AAD field except the header comes from an authenticated source; the header is bound by being in the AAD and by the digest | VERIFIED (source) |
| SHA-256 "key commitment" | **The terminology is inaccurate.** It is an *authenticated ciphertext digest*. Key commitment is unnecessary in this design for a different reason (§6) | Finding F1 |
| Audit status | `aead::stream` has **no** known audit. The libsodium alternative's 2017 audit also **predates** `crypto_secretstream` | Finding F2 |
| Exact correspondence to the paper's notation | **NOT ESTABLISHED.** ePrint 2015/189 could not be retrieved in this session (HTTP 403). The security argument in §3–§4 does not depend on it | Finding F4 |

**Decision: MERGE WITH SPECIFIC SECURITY CHANGES (§11).** The required
changes are corrections of security claims in the documentation, made in
this review's commit, plus human sign-off. No code change is required for
format v1.

## 2. Exact dependency and implementation chain

Resolved by `Cargo.lock` and `cargo tree --locked` (VERIFIED):

| Crate | Version | Lockfile checksum (SHA-256) | Role |
| --- | --- | --- | --- |
| `chacha20poly1305` | 0.10.1 | `10cd79432192d1c0f4e1a0fef9527696cc039165d729fb41b3f4f4f354c2dc35` | `XChaCha20Poly1305 = ChaChaPoly1305<XChaCha20, U24>`; features `alloc`, `getrandom`, `stream` |
| `aead` | 0.5.2 | `d122413f284cf2d62fb1b7db97e02edb8cda96d769b16e443a4f6195e35662b0` | `aead::stream::{EncryptorBE32, DecryptorBE32}` = `Encryptor/Decryptor<A, StreamBE32<A>>`; `AeadInPlace` buffer wrappers |
| `chacha20` | 0.9.1 | `c3613f74bd2eac03dad61bd53dbe620703d4371614fe0bc3b9f04dd36fe4e818` | `XChaCha20`, `hchacha::<U10>` (the 0.10.2 also in the lockfile belongs to another dependency) |
| `poly1305` | 0.8.0 | `8159bd90725d2df49889a078b54f4f79e87f1f8a8444194cdca81d38f5393abf` | One-time MAC |
| `universal-hash` | 0.5.1 | `fc1de2c688dc15305988b563c3854064043356019f97a4b46276fe734c4f07ea` | MAC trait; tag verification via `subtle` |
| `subtle` | 2.6.1 | `13c2bddecc57b384dee18652358fb23172facb8a2c51ccc10d74c157bdea3292` | Constant-time tag compare |
| `cipher` | 0.4.4 | `773f3b9af64447d2ce9850330c473515014aa235e6a783b02db81ff39e4a3dad` | `StreamCipher`, `StreamCipherSeek` |
| `generic-array` | 0.14.7 | `85649ca51fd72272d7821adaf274ad91c288277713d9c18820d8499a7ff69e9a` | Nonce and key arrays |
| `sha2` | 0.10.9 | `a7507d819769d01a365ab707794a4084392c824f54a7a6a7862f8c3d0892b283` | Object digest (also used by `ed25519-dalek`, `p256`, `p384` in the tree) |
| `digest` | 0.10.7 | `9ed9a281f7bc9b7576e61468ba615a66a5c8cfdff42420a70aa82701a3b1e292` | `Digest` trait |
| `zeroize` | 1.9.1 | `e13084392c5e4bc371903e2935a5eaeed24905a7511356b883835e18a78f6879` | Key and plaintext buffers |
| `rand_core` (`OsRng`) | 0.6.4 | (lockfile) | Keys, media IDs, prefixes. `fill_bytes` **panics** on OS RNG failure; the panic is caught at the FFI and becomes `internal`, never a zero key (VERIFIED source) |

**Implementation path for one chunk (VERIFIED source):**

```text
media.rs encrypt_file
 └─ EncryptorBE32::<XChaCha20Poly1305>::new(key, prefix[19])            aead/src/stream.rs (impl_stream_object!, position = 0)
     └─ encrypt_next_in_place / encrypt_last_in_place(aad, buf)          refuses next at position == u32::MAX; last consumes self
         └─ StreamBE32::encrypt_in_place(position, last, aad, buf)       stream.rs ~L406
             └─ aead_nonce = prefix[19] ‖ position.to_be_bytes() ‖ (last as u8)   stream.rs ~L437
                 └─ AeadInPlace::encrypt_in_place → encrypt_in_place_detached + append tag   aead/src/lib.rs
                     └─ ChaChaPoly1305::encrypt_in_place_detached → Cipher::new(XChaCha20::new(key, nonce24))  chacha20poly1305/src/lib.rs
                         ├─ XChaChaCore::new: subkey = HChaCha20(key, nonce[0..16]); ChaCha20 nonce = 0^4 ‖ nonce[16..24]  chacha20/src/xchacha.rs
                         └─ cipher.rs: Poly1305 key = keystream block 0; seek block 1; encrypt;
                            MAC = Poly1305(pad16(AAD) ‖ pad16(CT) ‖ le64(|AAD|) ‖ le64(|CT|))   (RFC 8439 layout)
```

Decryption mirrors this. `decrypt_in_place` rejects a buffer shorter than
the tag. The tag is verified (constant-time, `subtle`) **before** the
keystream is applied, and the buffer is truncated only on success
(VERIFIED source: `impl_decrypt_in_place!`, `cipher.rs`).

**Consequence for XChaCha:** HChaCha20 consumes nonce bytes 0–15. Those are
entirely our random prefix, so **all chunks of one object share one
subkey**. Each chunk's 12-byte ChaCha20 nonce is
`0x00000000 ‖ prefix[16..19] ‖ i (BE) ‖ flag`, distinct per chunk within
the object.

## 3. STREAM construction verification

**Variant.** `StreamBE32` is documented by the crate as "the original
'Rogaway-flavored' STREAM as described in [ePrint 2015/189]", with "a 32-bit
big endian counter and 1-byte 'last block' flag stored as the last 5-bytes
of the AEAD nonce". The paper text could not be retrieved in this session,
so whether this matches the paper's figure **bit for bit** (field widths,
the flag encoded as a byte) is **NOT ESTABLISHED** (F4). Structurally it is
the nonce-based STREAM: segment *i* is encrypted by the base AEAD under
nonce `N ‖ i ‖ d`, where *d* marks the final segment.

| Property | Implementation | Status |
| --- | --- | --- |
| Nonce construction | `prefix(19) ‖ u32_be(i) ‖ u8(last)`; prefix stored in the header | VERIFIED (source); VERIFIED (test, below) |
| Chunk counter | Starts at 0 (`Default`), +1 per `next`; `next` at `u32::MAX` returns an error; `last` may use any position | VERIFIED (source) |
| Final-chunk flag | 1 only for `*_last*`, which consumes the object (no further chunks possible); 0 otherwise | VERIFIED (source, test) |
| Chunk numbering | Position equals the zero-based chunk index; the decryptor advances in step and cannot skip | VERIFIED (source) |
| Tag handling | 16-byte Poly1305 tag appended per chunk; constant-time verify before decryption; buffer untouched on failure | VERIFIED (source) |
| Associated data | Caller-supplied, per chunk. We pass the **same** 101-byte AAD to every chunk. Per-chunk distinctness comes from the nonce, not the AAD | VERIFIED (source, test) |
| Ordering | A chunk moved to another position is decrypted under a different nonce → tag failure | VERIFIED (test: swapped, hash bypassed); ARGUED (INT-CTXT of the AEAD) |
| Truncation | The final chunk must verify with flag 1 at its position. Dropping trailing chunks makes the new last chunk fail (sealed with flag 0). Our decryptor also takes the chunk count from the authenticated plaintext length | VERIFIED (test: truncated at a chunk boundary, hash bypassed) |
| Duplication and replay within an object | A repeated chunk sits at a different index → wrong nonce → failure | VERIFIED (test: repeated) |
| Maximum size | Construction (this crate): positions 0..2³²−1, so up to 2³² chunks of ≤ 64 KiB. Per chunk, ChaCha20 block-counter use (≤ 1,026 blocks) is far below the 2³² limit. **Ours: 64 MiB = 1,024 chunks**, enforced before encryption and in `MediaRef::decode` | VERIFIED (source) |
| Failure behaviour | Any chunk failure → `AuthenticationFailure`. The partial plaintext buffer (`Zeroizing`, exact capacity) is wiped on drop; nothing is returned | VERIFIED (source, tests) |

**Empirical mapping (VERIFIED, test).** A temporary unit test, not
committed, encrypted a 4-chunk object (3 × 64 KiB + 7 B) with `encrypt_file`.
It then decrypted every chunk by hand with plain `XChaCha20Poly1305`, using
the nonce `prefix ‖ i.to_be_bytes() ‖ flag`. Results:
- every chunk opened, and the concatenation equalled the input;
- the wrong flag, the wrong index and an empty AAD each failed;
- the prefix is stored verbatim in header bytes 6..25;
- the AAD is exactly 101 bytes.

So the on-disk format really is "STREAM-BE32 over XChaCha20-Poly1305 with
counter from 0", independent of the crate's documentation.

## 4. Nonce uniqueness

Nonce uniqueness is required **per key**. Every code path that touches a
media key (VERIFIED source):

| Question | Answer and evidence |
| --- | --- |
| Does every object get a fresh key? | **Yes.** `send_media` is the only caller of `encrypt_file` outside tests. It draws `key ← OsRng(32 B)`, `media_id ← OsRng(16 B)` and `prefix ← OsRng(19 B)` on every call, before encrypting |
| Can a key be reused? | **No code path does it.** After `encrypt_file`, the key moves into `MediaRef` and is only ever: encoded into the MLS payload; sealed in history; decoded for **decryption** (`open_media`). No API takes a key as input, keys never cross the FFI (D-094), and `send_message` refuses caller-built kind-2 payloads |
| Can one key encrypt two objects? | **No.** `encrypt_file` runs once per `send_media` call, with that call's key. `reencrypt_message` (stale-epoch resend) re-encrypts the **MLS message** carrying the same reference; it never re-encrypts the object |
| Can encryption be retried with the same key? | **No.** Every retry is a new `send_media` call → new key, media ID and prefix. A failed attempt deletes its temp/output file, and its key is dropped (zeroized) |
| Can a partial object be resumed? | **No.** `encrypt_file` always starts at position 0 into a freshly created temp file; nothing persists encryptor state. Interrupted *uploads* resend the complete finished object (no re-encryption) |
| Can an object accidentally be encrypted twice? | Only as two `send_media` calls, which means two keys and two objects. Same plaintext → different ciphertext (tested: `every_class_round_trips_and_keys_are_fresh_per_object`) |
| Can concurrent encryption reuse a key? | **No.** Keys are local to each call. The FFI also serialises calls on a handle (`Mutex<CryptoCore>`); two handles on two cores still draw independent keys. Not stress-tested (no concurrency test) |
| Can nonce prefixes collide? | Yes, with probability ≤ q²/2¹⁵³ for q objects (19 random bytes). **It does not matter:** uniqueness does not rely on the prefix (next row) |
| Counter overflow within 64 MiB? | **No.** At most 1,024 chunks, positions 0..1023; the crate's limit is 2³²−1 |

**Which mechanism carries uniqueness: B (a fresh per-object key).** The
random prefix (A) is defence in depth.
- Within one object (one key), the nonces are `prefix ‖ i ‖ 0` for
  i = 0..n−2 and `prefix ‖ (n−1) ‖ 1`. These are pairwise distinct for any
  prefix, because the (i, flag) pairs are distinct. This holds with the
  prefix fixed, so no probability is involved.
- Across objects, the keys are independent uniform 256-bit values, so no
  (key, nonce) pair repeats unless two keys collide. For q objects that
  probability is ≤ q²/2²⁵⁷ (ARGUED: birthday bound; assumes `OsRng` is a
  sound CSPRNG, the OS assumption already made for every other key).
- XChaCha detail: equal prefixes under *different* keys give different
  HChaCha20 subkeys, so no keystream relation arises.

**Assumption:** the OS CSPRNG (`getrandom`) is not compromised or
predictable. RNG failure panics, which becomes `internal`; it never yields
a fixed key (VERIFIED source).

## 5. Custom composition review

Pipeline: plaintext file → STREAM-BE32/XChaCha20-Poly1305 (fresh key) →
object `header ‖ chunks` → SHA-256(object) → `media_ref = {media_id, class,
lengths, digest, key}` → MLS application message (D-089 AAD, signature,
sealed history) → recipient: size → digest → header → STREAM decrypt with
the AAD recomputed from authenticated history.

| Component | Property provided | Attack prevented | Relies on | New attack surface |
| --- | --- | --- | --- | --- |
| Fresh key per object | Nonce uniqueness; per-object compartmentalisation | Keystream reuse; cross-object decryption | OS CSPRNG | None |
| Header `"SHMD" ‖ fmt u16 ‖ prefix` | Self-describing object, carries the nonce prefix | Accidental format confusion | Header bound via AAD and digest | Header bytes are attacker-supplied input to the parser, but fixed-size (25 B) and checked strictly. The format version is **not** in the authenticated reference (F3) |
| AAD (101 B, fixed width) | Binds object → conversation, media ID, sender device, class, plaintext length, header, and domain, AAD-version and schema constants | Cross-object, cross-conversation and sender substitution; class or length confusion | Fields taken from authenticated history (§7) | None found; the encoding is unambiguous (fixed widths) |
| STREAM-BE32 / XChaCha20-Poly1305 | Confidentiality; integrity of each chunk and of the sequence (order, truncation, duplication) | Tampering, reordering, truncation, chunk splicing | XChaCha20-Poly1305 nAE security (HChaCha20 PRF + ChaCha20-Poly1305) | Unaudited `aead::stream` glue (about 120 lines, read in this review) |
| SHA-256 object digest in the signed reference | Recipients accept only the exact bytes the authenticated sender produced; early rejection before decryption | Server or storage substitution even where the AEAD would be the only line; makes "same key, different object" impossible | SHA-256 collision and second-preimage resistance; MLS authentication of the reference | Pass-1 hashing of attacker-supplied bytes (bounded by the authenticated size) |
| MLS key transport (`media_ref`, kind 2) | Key confidentiality to the current roster; sender authentication; replay protection | Key disclosure to the server; key substitution; replay of the reference | MLS (OpenMLS 0.9.1), D-085 trust policy, D-089 AAD | Key copies inside OpenMLS internal buffers are not zeroized by us. This was **NOT ESTABLISHED** (OpenMLS internals not inspected for this; same residual as text, E23) (F5) |
| Sender binding (AAD sender = MLS sender of the delivering message) | Media is attributable only to the device that encrypted it | Re-attribution by another member | `process_inner` sets the history sender only after `validated.device_id == routing.sender` (VERIFIED source) | None |
| Two-pass open (size, then digest, then decrypt) | No decryption work or plaintext for bytes not committed by the sender; the re-read file is still AEAD-checked | Partial-plaintext release; TOCTOU between passes | Local file system; AEAD | Twice the read I/O; an attacker who can write the file between passes only causes failure |
| 64 MiB limit | Bounded memory and allocation (decrypt to memory) | Memory exhaustion from a forged size (the size is also authenticated) | Limits checked before allocation | None |

**Wrong-key behaviour.** The recipient decrypts with exactly one key: the
one inside the authenticated reference. A wrong key, for example a buggy
sender, fails at the first tag. No "decrypts under several keys" situation
can arise for the server, because it controls neither key nor reference
(§6).

## 6. The SHA-256 digest (and "key commitment")

| Question | Answer (VERIFIED source) |
| --- | --- |
| What is hashed | SHA-256 over the **entire object file**: header (25 B) ‖ every ciphertext chunk **including its tag**, in order |
| When | During encryption, over exactly the bytes written (`hash.update(header)`, then `hash.update(buf)` after each chunk is sealed). Stored in `media_ref.ciphertext_sha256` |
| Header included | **Yes** |
| AAD included | **No** (the AAD is never transmitted; the recipient recomputes it) |
| Complete ciphertext | Yes, the exact length is checked first and the digest covers every byte up to that length |
| Can anything be modified without changing the expected hash | Not the object bytes, short of a SHA-256 second preimage. The expected digest itself is inside the MLS-encrypted, signed reference, so the server cannot change it |
| Key commitment? | **No.** Key commitment means a ciphertext cannot be opened validly under two different keys. The digest says nothing about keys. What the design *does* guarantee is that the **(key, object)** pair is fixed by one authenticated message, delivered identically to every group member. Recipients therefore never decrypt an object under a key the sender did not pair with it, so the multi-key ("invisible salamanders" style) concern does not arise. That follows from the **reference**, not from the hash |
| What it is | An **integrity check against an expected, already authenticated value**: an *authenticated ciphertext digest* |

**Finding F1 (terminology).** The docs called the digest a "substitute for
key commitment" and a "wrong-key / key-substitution defense". That is
inaccurate. The precise terms are **"authenticated ciphertext digest"** or
**"object digest"**. Key substitution is prevented by MLS authentication of
the reference that carries the key; the absence of key commitment is
harmless here because each object has exactly one authenticated key.
Corrected in this review's commit (documentation only).

## 7. AAD analysis (byte for byte, VERIFIED source and test)

```text
off  len  field                 value / source
0    16   context               "SirfHum-MediaAAD" (constant)
16    1   AAD version           0x01 (constant)
17    2   media schema version  0x0001 BE (constant)
19   16   conversation ID       history record's conversation = the MLS group ID the message was processed in (checked == envelope)
35   16   media ID              authenticated media_ref
51   16   sender device ID      history record: set only after validated MLS credential device == envelope sender (D-089)
67    1   media class           authenticated media_ref
68    8   plaintext length BE   authenticated media_ref
76   25   header                OBJECT FILE (untrusted): "SHMD" ‖ format u16 ‖ nonce prefix
= 101 bytes, all fixed width (unambiguous)
```

| Context | Bound? | How |
| --- | --- | --- |
| Conversation ID | Yes, directly | AAD; also MLS group ID = conversation (D-089) |
| Message ID | **No** (informational, F6) | The object is bound to its media ID and sender; the delivering message is authenticated by MLS. A sender can reference one object from two of its own messages; nobody else can |
| Sender account | Indirectly | AAD binds the device. Device → account comes from verified lineage, and the envelope's account is checked against it (D-089) |
| Sender device | Yes, directly | AAD, from the authenticated MLS sender |
| Message protocol version | Not in the media AAD | Bound in the delivering message's MLS AAD (D-089). Only payload version 1 / kind 2 decodes |
| Media schema version | Yes (constant 1) | AAD |
| Media format version | **Indirectly** | It is in the header, the header is in the AAD and in the digest, and decryption rejects anything but 1. The authenticated reference does **not** name the format version (F3) |
| Object identity | Yes | Media ID (AAD) + digest |
| Class, length | Yes | AAD (and authenticated reference) |

**Authenticated sources.** Every AAD field except the header comes from
authenticated state. The header comes from the untrusted file, but a
modified header changes both the AAD and (through the prefix) the nonce,
and it is covered by the authenticated digest. It is bound, not trusted.

**Should the format version be in the AAD or reference independently?** For
v1 it is already bound three ways (AAD via header, digest, explicit check).
The gap appears only when a second format exists: then the *expected*
format must come from the authenticated reference, not from the file, so a
server cannot steer a recipient into parsing an object under another
format's rules. **Finding F3 (Low, pre-v2):** add the format version to the
`media_ref` (payload version 2) *before* any format v2 is introduced. No
change is needed for v1.

## 8. Attack matrix

"Tests" names the committed test, unless noted. Rust tests are in
`native/tests/media.rs` (M), the unit tests in `engine/media.rs` (U),
service tests in `test/security/media/media_service_test.dart` (S), rules in
`firebase/tests/storage/media_storage.test.js` (R).

| # | Attack | Expected | Protection | Tests | Residual |
| --- | --- | --- | --- | --- | --- |
| A | Wrong key | Reject | AEAD tag at chunk 0 | U `stream_layer_round_trips_and_rejects_wrong_bindings` (wrong key) | — |
| B | Wrong conversation | Reject | AAD conversation; conversation-scoped history lookup | M `objects_are_bound_to_their_conversation`; U (AAD conversation) | — |
| C | Wrong message (another message's object, or a non-media ID) | Reject | Digest; AAD media ID; history lookup by message | M `another_objects_ciphertext_is_never_accepted`, `text_messages_and_unknown_ids_are_not_media` | — |
| D | Wrong sender (re-attribution) | Reject | AAD sender = MLS-validated sender | U (AAD sender); M `dart_cannot_send_a_media_reference_itself`; messaging envelope-sender tests | A modified client of a *member* cannot be stopped from sending its own references (by design); it cannot claim another device's object. No end-to-end test with a forged MLS-level reference (F9) |
| E | Wrong device (another device of the same account) | Reject | Same as D (device-level binding) | Same as D | As D |
| F | Modified header | Reject | Digest; AAD includes header; prefix changes the nonce | M tamper bytes 0, 4, 10; U `nonce prefix changed` | — |
| G | Modified AAD | Reject | AAD is recomputed, never transmitted; any field difference fails the tag | U: AAD version, schema, conversation, media, sender, class, length | — |
| H | Modified ciphertext or tag | Reject | Digest; per-chunk tag | M `any_modified_object_fails_closed…`; S | — |
| I | Deleted chunk | Reject | Size, digest; STREAM index and final flag | M `last chunk dropped`; U `truncated at a chunk boundary` (hash bypassed) | — |
| J | Duplicated chunk | Reject | Index-specific nonce | U `repeated` | — |
| K | Reordered chunks | Reject | Index-specific nonce | M `chunks swapped`; U `swapped` | — |
| L | Appended data or chunk | Reject | Exact authenticated size; digest | M `extended` | — |
| M | Truncated object | Reject | Size; digest; final flag | M `truncated by one byte`, `header only`, `empty` | — |
| N | Replayed media object (served for another reference) | Reject | Digest; AAD media ID | M substitution; S substitution | — |
| O | Replayed media key / reference | Duplicate ignored; foreign reuse rejected | MLS replay protection and history dedupe; AAD sender | M `a_replayed_media_message_is_a_duplicate…`; U (sender) | A legitimate recipient keeps the key (inherent to E2EE) |
| P | Cross-account substitution | Reject | No history record in another account's core; rules restrict to members | M `another_account_cannot_open_the_media`; R cross-account | — |
| Q | Revoked-device substitution | Reject new; old content stays | MLS trust (D-085) refuses its new messages; rules refuse its uploads | M `a_revoked_sender…`, `a_revoked_recipient…`; R revoked device; S revoked device | Content received before revocation stays (documented) |
| R | Malicious Firebase server | No content; integrity failures detected | E2EE plus all of the above; D-089 envelope binding | Above, plus messaging suite | Withholding and delay (DoS); metadata (sizes, timing, E45). The server can fake object metadata (`sd`, size) and make a sender believe an upload landed; recipients then see `unavailable` (DoS only) (F7) |
| S | Malicious storage object | Reject | Size precheck before download (service), size, digest, AEAD | S substituted, modified and truncated objects; M | DoS |
| T | Concurrent upload or encryption | No key or nonce reuse | Per-call keys; FFI mutex; create-only rules | Indirect only (fresh-key test, lost-ack test); **no concurrency test** | Low: there is no shared mutable crypto state between calls |
| U | Retry after partial failure | No reuse; nothing left behind | Fresh key per attempt; temp file removed; object deleted if queueing fails | M `inputs_are_bounded_and_failures_leave_nothing_behind`, `a_persistence_failure_removes_the_object…`; S interrupted upload and download | A crash after the object rename but before queueing leaves an orphan **ciphertext** file (no key persisted) |

## 9. Comparison with libsodium `crypto_secretstream_xchacha20poly1305`

| Aspect | Current: `aead 0.5.2` STREAM-BE32 + XChaCha20-Poly1305 | libsodium `secretstream` |
| --- | --- | --- |
| Audit history | **No known audit of `aead::stream`.** `chacha20poly1305` had one NCC Group review (published 2020-02-26) of an earlier release, predating 0.10.1 | libsodium's published audit covered **1.0.12–1.0.13** (2017, as cited in E2EE-ARCHITECTURE §7). `crypto_secretstream` was **added in 1.0.14** (libsodium ChangeLog, checked 2026-10-19), so **that audit predates it**. An audit of `secretstream` itself is **NOT ESTABLISHED** |
| Maturity | Construction from 2015 with a security proof; the RustCrypto implementation is small (about 120 lines read here) and widely depended on | Since 2017; very widely deployed and battle-tested; libsodium has a long track record |
| Nonce management | Stateless: `prefix ‖ i ‖ flag`. Uniqueness from the fresh key per object (§4) | Internal state: a 32-bit counter plus a random nonce from the header. Automatic re-keying on counter wrap or `REKEY`; uniqueness from fresh key + header |
| Chunk authentication | Per chunk: Poly1305 tag (16 B) | Per chunk: Poly1305 tag + an encrypted tag byte (17 B overhead) |
| Truncation | Final flag in the nonce; the decryptor demands it at the expected position | `TAG_FINAL` inside the ciphertext; **the application must check** for it, which is a known misuse risk |
| Reordering | Index in the nonce | Internal counter (and state ratchet) |
| Key lifecycle | Ours (fresh per object, MLS transport) | Ours too: secretstream does not handle key transport |
| Implementation complexity for us | Already implemented; pure Rust, the same crates as our sealed records | New binding: libsodium inside the Rust core (`libsodium-sys`) or a Dart package |
| Native dependency cost | None added (`stream` feature, `sha2` already compiled) | A **second native C crypto library** per Android ABI; build changes; pin and audit policy for C code |
| Flutter integration | None (inside the existing Rust core) | Through Rust: C build in the hook. Through Dart: keys would leave Rust, breaking D-094 |
| Maintenance risk | RustCrypto's `aead` 0.6 moves `stream` to a separate crate (`aead-stream`); a future upgrade will need care. Pinned today | libsodium is stable; another toolchain to maintain |
| Review burden | Review `aead::stream` (small) plus our composition (§5) | Review the binding plus the same composition; the library is better known to reviewers |

**Assessment.** Replacing STREAM with `secretstream` would **not** retire
the larger review item, which is our composition (AAD, digest, MLS key
transport). It would add a second native crypto library, and if bound in
Dart it would break the "keys never leave Rust" invariant. The audit
advantage usually attributed to libsodium **does not cover `secretstream`
itself**. Continuing with `aead::stream` is justified, **provided** a human
reviewer confirms §3 against the paper (F4) and accepts the unaudited status
(F8).

## 10. Findings, ranked

| ID | Severity | Finding | Status |
| --- | --- | --- | --- |
| F1 | **Medium (security claim accuracy)** | The SHA-256 digest was described as a key-commitment substitute and a key-substitution defence. Inaccurate (§6) | **Fixed (docs)** in this commit. Three code comments in `engine/media.rs` still say "commitment"; reword them with the next code change (this review changes no code) |
| F2 | **Medium (security claim accuracy)** | The docs stated libsodium had a published audit as the trade-off against `aead::stream`. That audit predates `secretstream` (§9) | **Fixed (docs)** in this commit |
| F3 | Low (pre-v2) | The media format version is bound only through the file header, not named in the authenticated `media_ref` | Open: required **before** any format v2; no change for v1 |
| F4 | Low (process) | Bit-level correspondence of `StreamBE32` to the paper's definition is **NOT ESTABLISHED** (paper not retrievable here); the security argument (§3–§4) does not depend on it | Open: human reviewer to confirm |
| F5 | Low (memory hygiene) | Copies of the media key inside OpenMLS internal buffers (application plaintext) are not known to be zeroized: **NOT ESTABLISHED** | Open: same residual as text (E23); review with the OpenMLS delta review |
| F6 | Informational | Media is bound to media ID and sender, not to the delivering message ID | Accepted (no attack found) |
| F7 | Low (availability) | Lost-ack recognition trusts server metadata (`sd`, size); a malicious server can make an upload look complete | Accepted: DoS only; recipients fail closed (`unavailable`) |
| F8 | Low (assurance) | `aead::stream` and the composition are unaudited | Open: human or independent review |
| F9 | Low (test coverage) | No end-to-end test with a forged MLS-level `media_ref` from another member (re-attribution is tested at the AAD level with the hash bypassed) | Optional test (§12) |

No finding shows a break of confidentiality, integrity, ordering,
truncation resistance or nonce uniqueness.

## 11. Decision

**2. MERGE WITH SPECIFIC SECURITY CHANGES.**

Required before merge:
1. **Documentation corrections F1 and F2.** Done in this review's commit:
   design doc §2 brief, D-093 entry, THREAT-MODEL E36/E37 wording.
2. **Human security sign-off on D-093**, including confirming §3 against
   ePrint 2015/189 (F4) and accepting the unaudited status (F8). Until then
   D-093 stays **PROPOSED — PENDING HUMAN SECURITY REVIEW**.

Not required for merge (recommended follow-ups; **not implemented**):

| Item | Change | Files | Tests | D-093 rewrite? | New review? |
| --- | --- | --- | --- | --- | --- |
| F3 | `media_ref` payload v2 carrying the object format version; reject an object whose header differs | `engine/media.rs`, Dart `MediaRefView`, golden vectors, design doc | Golden vectors; header version ≠ reference → reject; v1 references still open | Amendment | Yes (format change) |
| F9 | Test-only hook to inject a kind-2 reference sent by device B naming device A's object; assert `open_media` fails | `native/tests/media.rs` (`#[cfg(test)]` helper) | That test | No | No |
| T | Concurrency test: two cores and parallel `send_media` produce distinct keys and prefixes | `native/tests/media.rs` | That test | No | No |

**Replacement is not recommended at this point (§9).** BLOCK is not
warranted: no security-critical property is unestablished. F4 concerns
correspondence with the paper's notation, not the security argument, which
§3–§4 make from the source and tests under standard AEAD assumptions.

## 12. Evidence

- **Files inspected:** `Cargo.lock`, `Cargo.toml`; `aead-0.5.2/src/{stream.rs,lib.rs}`;
  `chacha20poly1305-0.10.1/src/{lib.rs,cipher.rs}`, its README;
  `chacha20-0.9.1/src/xchacha.rs`; `rand_core-0.6.4/src/os.rs`;
  `native/src/engine/{media.rs,conversation.rs}`, `native/src/engine.rs`
  (`process_inner`), `native/src/ffi.rs`; libsodium ChangeLog (web).
- **Not inspected:** ePrint 2015/189 (HTTP 403); OpenMLS internals for F5.
- **Tests run in this review:**
  - `cargo test --lib media` (6 passed);
  - `--test media` (18 passed, 1 ignored);
  - `--test messaging` (30 passed, 1 ignored);
  - a temporary nonce-layout test (1 passed; reverted, not committed).
- **CI on PR #10:** all 17 checks passed.
