# Future and Us

Status: **Implemented (Prompt 16): a security-layer notebook service, the
Future and Us areas, one editor, and a Home summary. Development only,
undeployed, unreviewed. Sirf Hum is NOT production E2EE.** Production wires
no notebook backend yet (D-121): a real build shows honest entry states.
Decisions D-118–D-121. Threats E69–E76 in the
[Threat Model](../security/THREAT-MODEL.md).

- **Future** answers *"What do we want to do together?"* — a shared private
  notebook of plans, not a task manager.
- **Us** answers *"Who are we together?"* — names, the day you got
  together, your story, your little things, your rituals and the days that
  matter. Not a profile, a feed, a score or an analysis.

Classification used below: **IMPLEMENTED** (in code, tested) ·
**PRE-PRODUCTION** (works in development, not reviewed or deployed) ·
**DEFERRED** (deliberately not built) · **BLOCKED BY BLAZE** · **FUTURE**
(a later prompt).

## 1. One notebook, composed from what exists (D-118)

Future and Us store the same kind of thing: small, private, editable
records that belong to the couple. They are **one notebook** with five
sections, carried exactly as a moment's manifest is (D-113):

| Need | Provided by |
| --- | --- |
| Which couple | The couple's MLS conversation, provisioned by the server at pairing (D-104). Its ID comes from the pairing answer, never from the client |
| Who may read/write on the server | Existing Firestore rules for messages: members only, active devices only, create-only (D-088) |
| Device trust, revocation | `MessagingService`: active status before every write, verified lineage on refresh, MLS roster (D-085) |
| Confidentiality of titles, notes, dates | MLS application message, sealed local history (D-089, D-090) |
| Offline, retries, duplicates | The sealed outbox, create-only messages, lost-ack recognition (D-091) |
| Serialization with Moments | `MessagingService.exclusive`: one lock per conversation for every feature (new, D-118) |

```text
create  "Go to Udaipur"   → kind-4 message M1          record ID = M1 (chosen by the core)
update  M1 → done         → kind-4 message M2 (target M1, every field)
remove  M1                → kind-4 message M3 (target M1, no content)
all in conversations/{couple conversation}: the server sees ciphertext messages only
```

- **No server schema, Security Rules, Functions, crate, cryptographic
  primitive or ABI change.** The core already refuses only kind 2 (media
  references it builds itself); kind 4 is a Dart-built payload like kind 3.
- **No `coupleId`, account or device field** in a record: the couple is
  the conversation (bound into the MLS AAD), the author is the
  MLS-authenticated sender device.
- **Alternatives rejected:** Firestore `future/*` or `us/*` documents
  (plaintext private content on the server, or a second key system if
  encrypted outside MLS); a dedicated conversation (server provisioning:
  Functions, Blaze, a second MLS group, no security gain); keeping Us
  content only on one phone (not shared — not "ours").

### The shared lock (found and fixed in this prompt)

Moments serialized its own operations, but a second feature on the same
`MessagingService` could have run a `sync` while a moment was being sealed
or flushed. `MessagingService.exclusive` now serializes every
state-changing feature operation on the conversation; `MomentsService` and
`NotebookService` both use it (tested: concurrent notebook writes, a moment
save and a refresh all arrive once each, in order).

## 2. The payload and the rules (D-119)

```text
version u8 = 1 | kind u8 = 4 | client time ms u64 BE | notebook schema u16 BE = 1
| op u8 (1 create, 2 update, 3 remove) | target record id [16] (zero for create)
| section u8 | category u8 | status u8
| date: year u16 BE | month u8 | day u8            (all zero: no date)
| title len u16 BE | title UTF-8 | note len u16 BE | note UTF-8
| detail len u8 | detail UTF-8
```

- Code: `lib/security/notebook/notebook_payload.dart`; golden vector in
  `test/security/notebook/notebook_payload_test.dart`.
- **Strict decode:** exact length, known version/kind/schema/op/section,
  values valid for the section, a real calendar day (1900–2199) or none,
  valid UTF-8 that is already trimmed, one-line titles and details. A
  remove carries no content. Anything else is **unreadable**, never guessed.
- **Per-section fields:**

| Section | Category | Status | Date | Title | Note | Detail |
| --- | --- | --- | --- | --- | --- | --- |
| `future` | plan, place, try, important date | planned / done | optional, any real day | required | optional | — |
| `story` | — | — | optional, not in the future | required | the story | — |
| `littleThing` | 8 kinds | — | — | required | optional | — |
| `ritual` | — | — | — | required | optional | "how often" text |
| `togetherSince` | — | — | required, not in the future | — | — | — |

- **Wire limits:** title 400 bytes, note 4,000 bytes, detail 160 bytes (the
  screens ask for less: 100 / 500–1,500 / 40 characters).

**Assembly** (`assembleNotebook`, pure, unit-tested):

1. Operations apply in server order: server time (this phone's time for a
   change still in the outbox), then message ID — so both phones reach the
   same notebook once they hold the same messages (tested).
2. `create` starts a record whose handle is its own message ID.
3. `update` replaces **every field** of a live record of the **same
   section**; the last change wins. The section can never change.
4. `remove` ends a record for good; later updates and removes do nothing.
5. **Either partner may change or remove anything** — the notebook is
   shared. Authorship is shown ("Added by you / by Ravi"), never enforced.
6. A change to a record that is not here does nothing; a change that names
   the wrong section, or a payload that cannot be decoded, is counted as
   unreadable and changes nothing ("One change couldn't be opened").

## 3. Product model (D-120)

**Future** files plans the way people think of them:

- **Coming up** — planned, dated from today on, soonest first.
- **Plans / Places / Things to try** — the rest still planned: no date, or a
  day that has passed. A passed day is just a day: never "missed", "late"
  or "overdue" (tested).
- **Important dates** — anniversaries, birthdays, trips, milestones; a day
  each, no recurrence.
- **Done together** — what you have done, most recent first.

Completion is a quiet circle that fills and a line through the words, plus
the word "Done" (not colour alone). No confetti, counts, progress bars,
percentages, streaks, reminders or "you missed" copy.

**Us** shows: the couple mark and names (from the session, D-106); "Together
since …" if you have said it; **Our story** (named parts — suggestions "How
we started", "Our first date", "The day we knew" only fill the name); **Our
little things** (favourite food, comfort food, favourite movie, our song,
favourite place, inside joke, something we always do, another little
thing); **Rituals** (a name, "how often" as free text, a note — no
schedule); **Important dates** (the same records as Future's, added from
either place); and sign-out.

**V1 limits (live records):** Future 200, story 12, little things 30,
rituals 12, together-since 1. A full part says "That's all the room there is
here for now." instead of offering more.

**Not built (scope):** calendars, recurrence, reminders or any notification
engine, external calendar sync, time zones, money, AI analysis or scoring,
location, presence or activity history, public profiles, likes, followers,
feeds.

## 4. Client behaviour (D-121)

```text
presentation  features/future/presentation/future_screen.dart
              features/us/presentation/us_screen.dart
              features/notebook/presentation/ (editor, status views, copy)
     │ reads
application   features/notebook/application/notebook_controller.dart (one controller for both)
     │ produces
domain        features/notebook/domain/notebook_state.dart (sealed, ID-free)
              features/future/domain/future_sections.dart   (pure filing rules)
     │ over
security      security/notebook/ (payload, assembly, NotebookService over MessagingService)
              — production: notebookBackendProvider = null
              — tests only: test/support/notebook_fakes.dart
```

- `NotebookController` is the **only** producer of `NotebookState`:
  unavailable (not paired / needs phone / not yet available), loading,
  ready (snapshot, refreshing, notice), blocked, failed. It runs only for a
  paired session on a platform that may hold private content, with a
  backend, and **rebuilds from nothing on any session change**; late
  refresh answers and late writes are dropped by a generation check
  (tested: account A → sign out → account B never shows A's notebook).
- **Writes** go only through the controller and only while ready. A device
  that is not trusted is `blocked`: entries dropped, writes refused.
- **Local first:** this phone's notebook shows at once, also offline; then
  `refresh` = `refreshTrust` → `sync` → `flushOutbox`.
- **Write flow** (`NotebookService`): under the conversation lock, validate
  and check the record or limit → seal one message (`queuePayload`) →
  `flushOutbox` → `saved` | `savedOnPhone`. Before sealing, any failure
  keeps nothing. After sealing, a transient failure is `savedOnPhone` (never
  a failure that invites a duplicate); a permanent refusal (not a member,
  not trusted) discards it if the server has not taken it, and is reported.
- **Editor:** one pushed page for every section (never a URL). Save is in
  the app bar (reachable with the keyboard open), single flight; the page
  cannot be left while saving; a failure says nothing was saved and keeps
  what was typed. Remove asks first: "It will disappear for both of you."
- **Home** shows the soonest dated plan ahead, or the existing empty state.

| Failure | Shown as |
| --- | --- |
| Device revoked / pending / removed from MLS | `NotebookBlocked`: no entries, no writes |
| Offline, server unreachable | Notebook stays + "Couldn't check for changes" + Try again |
| No shared MLS group yet, device to remove | Notebook stays + "Your phones are still connecting" |
| Account no longer in the couple | `NotebookFailed(notPaired)` |
| Local state corrupted | `NotebookFailed` + Try again |
| Malformed / newer / contradicting change | Counted: "One change couldn't be opened on this phone." |
| Edited or removed on the other phone meanwhile | "This was changed or removed on the other phone. Nothing was saved." |

**Logs:** `notebook_write_started|completed|failed|deferred {outcome, op,
section}`, `notebook_refreshed {outcome, received}`,
`notebook_state_changed {state, entries}`. Never titles, notes, dates,
handles, message/device/account IDs (tested in service and controller).

## 5. Web and iOS

Web shows the Future and Us shells, the couple's names (already on the
server, D-100) and sign-out, with "Future/Us stays private to your phones.
Open it in the Sirf Hum app." It never builds a backend, never reads or
writes private content and has no plaintext fallback (D-046; tested). iOS is
out of scope (D-092) and untouched.

## 6. Security review (F1–F20)

| # | Check | Result |
| --- | --- | --- |
| F1 | Unauthorized Future access | Server: message rules admit members' active devices only (D-088). Client: controller only for a paired session with a backend built for this account |
| F2 | Unauthorized Us access | Same records, same path as F1 |
| F3 | Forged couple ID | No couple ID exists in a record; the conversation comes from the server's pairing answer and is bound into the MLS AAD (tested: another conversation shares nothing) |
| F4 | Account-switch leakage | Controller rebuilds per session; late refresh answers and late writes dropped; another account's core is refused (`accountMismatch`) (tested) |
| F5 | Revoked-device writes | `queuePayload` and `flushOutbox` require `active`; a change sealed while trusted never leaves once revoked (tested); rules refuse writes |
| F6 | Stale-device writes | `pending`/`unknown` treated as revoked (tested); a revoked partner device gets no new change until removed from MLS (tested) |
| F7 | Signed-out access | No controller state, no backend call, editor unreachable (shell gone); rules deny anonymous |
| F8 | Plaintext private notes | Only inside MLS ciphertext and the sealed history; scanned for in server data and both slots (tested, native and on-device) |
| F9 | Private notes in logs | Categories, ops, sections and counts only (tested) |
| F10 | Private content in notifications | None: notifications are constant and content-free (D-097). Residual: once deployed, a notebook change triggers the generic "You have a new message" (E75) |
| F11 | Cross-couple leakage | One conversation per couple; records cannot reference another conversation's messages (assembly is per history) |
| F12 | Stale backend responses | Generation check drops answers for an earlier session (tested) |
| F13 | Local plaintext persistence | None: no cache, file or preference; records live only in the sealed core history |
| F14 | Unsafe offline fallback | Offline writes use the existing sealed outbox; if device status cannot be checked before sealing, nothing is kept ("Nothing was saved") |
| F15 | Malformed backend state | Strict decode; contradicting changes counted as unreadable; corrupted local state is `failed`, never "empty" (tested) |
| F16 | Race conditions | Shared conversation lock across features (fixed here); validation under the lock; editor single flight; deterministic last-change-wins (tested) |
| F17 | Duplicate creation | Single-flight editor; retries flush the same sealed message; lost acknowledgements recognized (tested) |
| F18 | Deletion inconsistency | Remove is a terminal tombstone that both phones apply in the same order; late edits do nothing (tested). **Not erasure** (E72) |
| F19 | Public/private boundary | No public surface: no profile pages, links, sharing or URLs for records (pushed pages only) |
| F20 | Web privacy fallback | Web never loads or writes the notebook; explanation shown; no plaintext path (tested) |

**Unaudited:** the kind-4 format, the assembly rules and the shared lock.
No security claim may be made.

## 7. Known limitations

- **No production backend (BLOCKED):** needs a sign-in method (D-107),
  deployed device activation (Blaze, D-025), partner PIK verification UI,
  and wiring a `MessagingService` for the paired account — the same
  blockers as Moments (D-116).
- **Remove is not erasure (accepted, E72):** the removed record's earlier
  versions stay in both phones' sealed histories and as ciphertext on the
  server until a retention design exists. Editing likewise keeps earlier
  versions sealed locally.
- **Last change wins:** two simultaneous edits of the same record keep the
  one the server ordered last; the other is silently replaced (E73).
- **Edits consume history:** each change is one record of the core's
  10,000-record bound per conversation, shared with chat and Moments
  (E74). Compaction is deferred.
- **Together since:** if both partners add it at the same moment, the most
  recently added one shows; the other stays hidden.
- **Notifications:** once deployed, each change wakes the partner's phone
  with the generic message notification (E75).
- New devices do not see records from before they joined (no history
  transfer, as for messages).
- A future chat view MUST filter `notebookProtocolMessageIds(history)`, as
  it filters `momentProtocolMessageIds` (recorded in E2EE-MESSAGING-DESIGN).

## 8. Deferred and future

| Item | Classification |
| --- | --- |
| Production notebook backend | BLOCKED BY BLAZE (and D-107) |
| Notifications for changes, reminders for dates | DEFERRED (needs a notification design; content-free only) |
| Retention / true deletion of removed records | DEFERRED (needs a Function, Blaze, a retention decision) |
| History compaction of superseded versions | DEFERRED (needs native verification of re-receive behaviour) |
| Recurring dates, calendar views, external calendars | FUTURE (explicitly out of V1) |
| Letters, devices and privacy settings in Us | FUTURE |
| Independent review of kind 4 and the lock | PRE-PRODUCTION requirement |
