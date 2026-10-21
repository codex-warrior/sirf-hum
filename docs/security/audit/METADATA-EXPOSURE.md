# Metadata Exposure

Status: **Prompt 17, 2026-10-20**, from the implemented schema and code (not
the design intent). Sirf Hum claims **no metadata privacy** beyond what is
listed as hidden below. Anyone with Firestore/Storage/log access (a Firebase
admin, Google, a compromised server, a database dump) sees the "visible"
column.

## Hidden from the server

Message text, moment captions and dates, notebook titles/notes/dates,
photos, media class, file names, EXIF, the media key, MLS secrets and
private keys, and the kind of a private payload (text, media reference,
moment, notebook), although sizes and timing allow guesses (below). MLS
encrypts the sender inside a PrivateMessage, but Sirf Hum's envelope names
the sending account and device in clear (D-089), so the sender is **not**
hidden.

## Visible to the server (Firestore, Storage, Functions)

| Where | What is visible |
| --- | --- |
| `users/{uid}` | Display name, profile created/updated times |
| `users/{uid}/devices/*` | Every device ever registered: status history (pending/active/revoked/…), platform, certificate (public PIK and device key, issued-at), `implementation`, timestamps, approver lineage (`approvedBy`, signed evidence), revocation reason (removed/lost/stolen/compromised) and revoker |
| `accountTrust/{uid}` | Trust epoch (a counter of trust events), first device, reset requests/cancellations/completions and timing, identity epoch, recovery key public half and when it was registered/used |
| `pairings/*`, `couples/*`, `accountPartners/*` | Who invited whom, which devices acted, when, how it ended (accepted/rejected/cancelled/expired/invalidated), the couple and its conversation: **the relationship graph** |
| `conversations/{c}` | Both members, pairing/couple IDs, epoch (counts membership changes), creation time |
| `.../messages/*` | Sender account and device, epoch, server time, ciphertext **size (to within 256 bytes, D-126)**, message count and rate |
| `.../commits/*`, `.../welcomes/*`, `.../keyPackages/*` | Who changed membership and when, which device was added (Welcome target), every device's KeyPackage |
| Storage `conversations/{c}/media/{m}` | **Exact object size** (≈ plaintext size + 16 B per 64 KiB; padding deferred, D-099), uploading device (`sd`), upload time, object count |
| `pushTokens/*` | Each active device's FCM token, mapped to device and account |
| `rateLimits/*`, `deviceChallenges/*`, `deviceApprovalRequests/*` | Per-account activity counters and short-lived challenge records |
| Firebase Auth | Sign-in identifiers of the chosen provider (D-107 open), sign-in times |
| Cloud Logging | That a callable or trigger ran, its outcome category and counts; platform request logs (time, latency, and caller IP at the Google layer) |

Correlations the server can make: a media upload followed by a message is
a photo/moment; a burst of small messages after a manifest-sized one;
which person is typing to whom and when; device changes and revocations
over time; when a couple formed.

## Visible to Google / FCM (once deployed)

| Signal | Detail |
| --- | --- |
| Token ↔ app instance ↔ phone | FCM tokens identify an app installation on a device |
| Timing and kind | Each wake-up's time and kind: `m` (visible "new message" for the partner's devices, high priority) or `s` (silent sync: own-device sends, commits, revocations) |
| Payload | Constant: `{v:'1', k}` plus the generic title/body; no IDs, counts, names or ciphertext (D-097) |
| Lock screen | The app name and the generic text; `visibility: private` |

## Visible on the phone to someone holding it

Content shown while the app is open; notification timing; the app's
existence. Local files are sealed (store key in the Keystore); a rooted or
compromised phone sees everything the person sees (T4).

## Not yet decided

Retention of any of the above (nothing is deleted today, P17-18),
coarse timestamps, media size buckets, and metadata minimisation of device
records (revocation reasons, platform) are open design work (PRODUCTION-BLOCKERS P2-8, P3-1, P3-2).
