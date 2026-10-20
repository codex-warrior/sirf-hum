# Moments

Status: **Implemented (Prompt 15) as a security-layer service, timeline,
detail and "new memory" flow. Development only, undeployed, unreviewed.
Sirf Hum is NOT production E2EE.** Production wires no moments backend yet
(D-116): a real build shows an honest entry state. Decisions D-113–D-117.
Threats E61–E68 in the [Threat Model](../security/THREAT-MODEL.md).

*Your memories, just for the two of you.* A private photo timeline for one
couple — not a feed. No likes, comments, sharing, followers, discovery,
suggestions, AI, location or background scanning.

## 1. Composition, not a new system (D-113)

A moment adds **no server schema, no rules, no cryptography and no ABI
change**. It is carried by what Prompts 07–12 built:

| Need | Provided by |
| --- | --- |
| Which couple | The couple's conversation, provisioned by the server at pairing (D-104). Its ID comes from the server's pairing answer, never from the client |
| Who may read/write on the server | Existing Firestore and Storage rules: members only, active devices only, create-only (D-088, D-095) |
| Device trust, revocation | `MessagingService`: active status, verified lineage, MLS roster (D-085); downloads refused on a non-active device (D-096) |
| Photo encryption, keys | Prompt 11 media: STREAM/XChaCha20-Poly1305, per-object keys generated and kept in Rust, delivered only inside MLS (D-093, D-094) |
| Caption and date confidentiality | MLS application message, sealed local history (D-089, D-090) |
| Offline, retries, duplicates | The sealed outbox, create-only objects, message-ID dedupe (D-091, D-095) |

```text
Moment = photo 1 … photo n   (kind 2 media_ref messages, built only by Rust; keys never in Dart)
       + manifest            (kind 3 message, built by Dart: caption, date, photo message IDs)
all in conversations/{couple conversation} — the server sees n ciphertext objects + n+1 ciphertext messages
```

The moment's **creator binding** is the MLS-authenticated sender device of
the manifest; its **couple binding** is the conversation ID in the MLS AAD
(D-089) plus server membership. No `coupleId` field exists anywhere in a
moment: it would be client-controlled and redundant.

**Alternatives rejected:** a Firestore `moments/*` document with a
plaintext caption (private content on the server); an encrypted moment
document outside MLS (a second key system); a dedicated moments
conversation (needs server provisioning — Functions, Blaze — and a second
MLS group for no security gain).

## 2. The manifest (kind 3, D-114)

```text
version u8 = 1 | kind u8 = 3 | client time ms u64 BE | moment schema u16 BE = 1
| memory date: year u16 BE | month u8 | day u8        (all zero: no date)
| photo count u8 (1..8) | count × photo message id [16]
| caption length u16 BE | caption UTF-8 (0..2,000 bytes, trimmed)
```

- Code: `lib/security/moments/moment_payload.dart`; golden vector in
  `test/security/moments/moment_payload_test.dart`.
- No key, hash, file name, MIME type, size, dimensions, location, EXIF,
  device model or OS field. The caption and date are the only content.
- Strict decode: exact length, known version/kind/schema, a real calendar
  date (1900–2199) or none, 1–8 distinct photos, valid normalized UTF-8.
  Anything else is an **unreadable** moment, never guessed at.

**Timeline rules** (`assembleMoments`, pure and unit-tested). A manifest is a
moment only if every listed photo on this phone is:
1. a media message of class `image`;
2. sent by the **same device** as the manifest (both MLS-authenticated), so
   nobody can put the partner's photos in their own moment;
3. not already claimed by an earlier moment (earliest claim wins).

Otherwise the whole moment is unreadable ("This memory couldn't be opened").
A photo that simply has not arrived yet is counted as missing and said so,
never invented.

**Limits (V1):** 8 photos per moment, 64 MiB per photo (D-093), 2,000-byte
caption. Photos only: video needs playback without plaintext at rest
(streaming decryption), deferred. A moment uses n + 1 of the 100 outbox
slots and n + 1 of the core's 10,000 history records per conversation.

## 3. Creating a moment

```text
choose photos (system picker) → preview → note + date (optional) → Save
MomentsService.create:
  validate (count, sizes, caption, date not in the future)   — nothing touched yet
  room for n+1 in the outbox
  queueMedia × n   (Rust encrypts each file to a ciphertext object + sealed media_ref; no upload)
  queuePayload     (the kind-3 manifest, sealed; no upload)
  ── any failure above: discardQueued every sealed part → nothing left, nothing sent
  flushOutbox      (objects, then messages, in creation order; media first within one ms)
  → saved | savedOnPhone (offline/interrupted: finishes on refresh)
  ── permanent refusal (not a member / device not trusted): discard what the server has not taken, report failure
```

- **Single flight:** the composer ignores a second Save; a saved composer
  cannot save again; the service serializes all state-changing operations.
- **Retry never re-creates:** "Try again" flushes the sealed outbox; message
  IDs and objects are reused, create-only rules refuse duplicates, and a lost
  acknowledgement is recognized (same uploader and size / same ciphertext).
- **Plaintext:** the picker's files are read only inside the core. Their
  temporary copies are deleted when the composer goes away, after any save
  still reading them (D-117). The screen cannot be left mid-save.

## 4. Timeline and detail (D-115)

- `MomentsController` is the only producer of an ID-free `MomentsState`:
  unavailable (not paired / needs phone / not yet available), loading,
  ready (entries, total, earlier pages, refreshing, notice), blocked,
  failed. It runs only for a paired session on a platform that may hold
  private content, and rebuilds from nothing on any session change
  (generation check drops late answers).
- **Local first:** this phone's timeline shows at once (also offline); then
  `refresh()` checks trust (`refreshTrust`: active device + lineage),
  fetches (`sync`) and finishes saves (`flushOutbox`).
- **Bounded:** the core's history is already bounded (10,000 records); the
  screen shows pages of 24 moments ("Show earlier memories"). Server reads
  are the existing per-epoch sync. No infinite scroll.
- **Order:** newest day first, filed by month. A moment's day is its memory
  date, else the day it was added.
- **Photos:** decrypted on demand (`momentPhotoProvider`), one at a time,
  decoded at display size; bytes wiped when no widget shows them; never
  auto-retried (Riverpod's default retry is off) so a corrupted photo is not
  re-downloaded in a loop. Retry is offered only when it can help
  (`unavailable`).
- **Detail:** photos full width, caption, memory date, who added it and
  when, photo count, saving/arriving notes. No social controls, IDs or
  crypto state. Navigation is a pushed page, so no moment is ever in a URL.
- **Home** says "You've kept N memories together." only when the timeline
  holds them.

| Failure | Shown as |
| --- | --- |
| Device revoked / pending / removed from MLS | `MomentsBlocked`: no timeline; decoded photos evicted from memory |
| Offline, server unreachable | Timeline stays + "Couldn't check for new memories" + Try again |
| No shared MLS group yet, device to remove | Timeline stays + "Your phones are still connecting" |
| Account no longer in the couple | `MomentsFailed(notPaired)` |
| Local state corrupted | `MomentsFailed` + Try again (never treated as a bad moment) |
| Malformed / newer / forged manifest | An unreadable tile: "This memory couldn't be opened." |
| Photo corrupted (hash/AEAD, after one fresh download) | "This photo couldn't be opened." No retry |
| Photo not here yet | "This photo isn't on this phone yet." + Try again |

## 5. Web and iOS

Web shows the Moments area with "Moments stay private to your phones" and
never builds a backend, a picker, or a photo request (D-046). No WASM or
plaintext fallback. iOS is out of scope (D-092) and untouched.

## 6. Couple isolation and device trust (tested)

| Case | Result | Evidence |
| --- | --- | --- |
| Partner reads the couple's moment | Allowed | rules `moments_isolation.test.js`; service test |
| Another couple reads or writes | Denied | rules: objects, messages, conversation, listing |
| Forged conversation / couple ID | Denied | rules (other couple's, invented, couple ID as conversation); service: another conversation shares nothing |
| Wrong account | Denied | rules; service: core of another account → `accountMismatch` |
| Revoked / pending (stale) device | No create, no fetch, no download | rules; service test for all three statuses |
| Revoked partner device | No moment encrypted to it until removed; it fetches nothing | service test (signed revocation, D-081) |
| Signed out | Nothing | rules (anonymous); controller/screen tests |
| Account removed from couple | Never "saved" | service test (found and fixed in this prompt) |
| Forged moment claiming the partner's photos | Unreadable on both phones | timeline unit test + native service test |

## 7. Deletion and editing (D-116)

**Not implemented, deliberately.** A truthful delete would need (1) server
deletion of the ciphertext objects and messages, which the rules forbid and
which needs a Function (Blaze) and a retention decision; and (2) the
partner's device to drop keys it already holds, which cannot be enforced. A
local-only "delete for me" would look like deletion while the moment stays
on the partner's phone and the server. Editing would create a second
manifest and a second claim on the same photos (refused by the timeline
rules by design). Both need a product and security design first.

## 8. Logs

`moment_upload_started {photos}`, `moment_upload_completed {outcome, photos}`,
`moment_upload_failed {outcome}`, `moment_upload_deferred {outcome}`,
`moments_refreshed {outcome, received}`, `moment_photo_opened {outcome}`,
`moments_state_changed {state, shown}`. Never captions, dates, photos,
paths, handles, message/media/device/account IDs (tested).

## 9. Security review (S1–S25)

| # | Check | Result |
| --- | --- | --- |
| S1 | Plaintext media upload | None: the core encrypts files to ciphertext objects; uploads read only those. Tested by scanning stored objects |
| S2 | Plaintext media storage | Storage holds STREAM ciphertext only; constant content type; metadata exactly `{sd}` |
| S3 | Media-key exposure | Keys stay in Rust (D-094); Dart sees the 43-byte key-free view; `queuePayload` cannot send kind 2 (tested) |
| S4 | Unauthorized couple access | Rules: members only (tested for a second couple) |
| S5 | Forged couple ID | No couple ID exists in a moment; conversation from the server; forged conversation IDs denied (tested) |
| S6 | Forged moment ID | Message IDs are random from the core; a forged or re-used reference makes the moment unreadable; replays are refused by create-only rules and MLS dedupe |
| S7 | Revoked device access | No create/fetch/download (client), no writes (rules), no new keys (MLS removal). Residual: content it already holds (D-096) |
| S8 | Stale device access | `pending`/`unknown` treated like revoked (tested) |
| S9 | Replayed upload | Create-only objects/messages; MLS replay protection (D-091) |
| S10 | Duplicate upload | Lost-ack recognition; one object, one message each (tested) |
| S11 | Metadata leakage | Server learns: object count and exact sizes, timing, uploader device, message count (residual E45; padding deferred). No class, names, EXIF, captions, dates |
| S12 | Caption leakage | Caption only inside MLS ciphertext and sealed history; scanned for in server data, both slots and logs (tested) |
| S13 | Local plaintext fallback | None. No plaintext cache or file is written by the app; web fails closed |
| S14 | Insecure cache | Ciphertext-only object cache in the backup-excluded slot (D-096); decrypted bytes in memory only, wiped on dispose; decoded images evicted on sign-out/lost trust |
| S15 | Insecure logs | Categories and counts only (tested in service and controller) |
| S16 | Signed-out access | No backend calls (gated on a paired session); rules deny anonymous |
| S17 | Account switching | Controller rebuilds; late answers dropped; a core of another account is refused (`accountMismatch`) |
| S18 | Race conditions | Service operations serialized; photo opens serialized; composer single-flight |
| S19 | Concurrent uploads | Two concurrent saves → two moments, no duplicates (tested) |
| S20 | Partial upload | Nothing leaves before the whole moment is sealed; objects before references; a manifest arriving early shows "photos on their way" |
| S21 | Interrupted encryption | A failed photo discards every sealed part (tested). A crash between photos and manifest can leave sealed photos without a manifest; they upload as orphan media messages that no moment shows (residual, E66) |
| S22 | Interrupted upload | Sealed outbox resumes; object first (tested) |
| S23 | Corrupted ciphertext | Hash + AEAD fail closed, one re-download, then "couldn't be opened" (tested) |
| S24 | Unauthorized deletion | No client can delete objects or messages (rules, tested); deletion is not offered (D-116) |
| S25 | Server-side plaintext visibility | The server never holds keys, captions, dates or photos; Functions are not involved |

**Unaudited:** the manifest format, the timeline rules, and their
composition with the Prompt 10/11 formats. No security claim may be made.

## 10. Known limitations

- No production backend: needs a sign-in method (D-107), deployed device
  activation (Blaze, D-025), partner PIK verification UI, and wiring a
  `MessagingService` for the paired account (D-116).
- Storage and Functions deployment BLOCKED on Blaze (D-025).
- Photos only; no video, voice notes or letters yet.
- No thumbnails (D-099): covers decrypt the full photo (downscaled decode).
  Decryption runs on the UI isolate (synchronous FFI); large photos can
  stutter.
- EXIF (including location) inside a photo reaches the partner's device
  inside the ciphertext; the server never sees it. Stripping needs on-device
  re-encoding without plaintext at rest — deferred (D-117).
- The picker's temporary plaintext copies live in the app's private cache
  until the save finishes (deleted best effort).
- A revoked device that is offline still shows the moments already on it
  (D-096): revocation cannot reach into a device.
- No deletion, editing, albums, search or notifications for moments.
- New devices do not see moments from before they joined (no history
  transfer, as for messages).
- A future chat must hide kind-3 manifests and the media they claim.
