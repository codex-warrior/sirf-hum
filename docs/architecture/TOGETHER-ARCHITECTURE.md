# Together

Status: **Implemented (Prompt 14) as domain, state machine, realtime port and
hub UI. No production backend (D-112):** a real build shows the hub with
nothing startable. Sessions run only over a test-only fake. Decisions D-111,
D-112.

## 1. Layers

```text
presentation  features/together/presentation/together_screen.dart   (hub + session panel)
     │ reads
application   features/together/application/together_controller.dart (TogetherController, Riverpod)
     │ produces
domain        features/together/domain/together_state.dart     (sealed TogetherState, ID-free)
              features/together/domain/together_activity.dart  (TogetherActivity)
              features/together/domain/together_backend.dart   (TogetherBackend port, snapshots, failures)
     │ implemented by
              — production: none (togetherBackendProvider = null)
              — tests only: test/support/together_fakes.dart (FakeTogetherBackend)
```

The UI never imports Firebase. No Firebase implementation exists.

## 2. State machine (D-111)

| State | Means | Shown as | Actions |
| --- | --- | --- | --- |
| `TogetherUnavailable(notPaired / needsPhone / notYetAvailable)` | no couple; web; no backend | activity list, nothing startable, one notice | — |
| `TogetherLoading` | first backend answer pending | skeleton | — |
| `TogetherIdle(presence, supported)` | no session | presence + "What do you want to do?" | Start (supported only) |
| `TogetherStarting` | our start is with the server | "Starting time together…" + progress | — |
| `TogetherWaiting` | started, partner not in | "Waiting for Ravi…" | Cancel |
| `TogetherInvited` | partner started | "Ravi wants some time together." | Join, Not now |
| `TogetherJoining` | our join is with the server | "Joining…" + progress | — |
| `TogetherActive(since)` | both in | "You're together." + clock | End together |
| `TogetherEnding` | our leave is with the server | "Ending…" + progress | — |
| `TogetherEnded(reason)` | ended: you left / partner left / expired | "Time together ended." + reason | Back to Together |
| `TogetherFailed(failure)` | unavailable, startRefused, sessionGone, deviceNotTrusted, notPaired, unexpected | human error copy | Try again (none for a revoked device) |

Rules (enforced in `TogetherController`; tested in
`test/features/together/together_controller_test.dart`):

- **Only for a paired session.** The controller rebuilds from nothing on
  every session change (sign-out, account switch, couple lost). The old
  backend subscription is cancelled, and in-flight start/join/leave answers
  are dropped (generation check). Authentication alone opens nothing.
- **Server-led.** Local states (`starting`, `joining`, `ending`) only bridge
  until the server answers. Waiting, invited, active and ended come from
  snapshots.
- **Fails closed.**
  - A stream error is `failed`, never idle or "not active".
  - A session that vanishes while active is `ended(expired)`, never still
    on.
  - A snapshot naming an activity this client cannot run is
    `failed(unexpected)`.
  - `failed` and `ended` hold: no later event on the stream changes them.
    "Try again" or "Back to Together" starts a fresh subscription and shows
    what the server says then.
- **No identifiers.** No state carries an account, couple, partner, device
  or session ID. The partner's name comes from the session's display names.
- **Logs:** `together_state_changed {state}`, `activity_start_failed`,
  `activity_join_failed`, `activity_leave_failed` and
  `together_watch_failed`, each with `{failure}` only.

## 3. Activities and the port

- `TogetherActivity`: `timeTogether`, `call`, `watch`, `listen`. The hub
  lists all four. Only those in `TogetherBackend.supportedActivities` get a
  Start button; the rest say "Coming soon" and are not tappable.
  `TogetherController.start` refuses unsupported activities too.
- **Time together** is the validation activity: a shared session with a
  running clock. It carries no content, media or messages.
- `TogetherBackend` takes **no identifiers**: `watch()`, `start(activity)`,
  `join()`, `leave()`. A real implementation must:
  - derive the account from the authenticated server context;
  - derive the couple from the server's couple record, so the client cannot
    aim Together at anyone else;
  - require an **active** device for every step (D-069–D-085), via the
    existing device-proof mechanism. No second trust system.

## 4. Why there is no backend yet (D-112)

- **Privacy:** session and presence records are relationship metadata the
  product has so far refused to store. D-100 says no presence or activity
  fields on the server, and THREAT-MODEL T10 covers an abusive partner
  monitoring presence. Storing them needs its own design and decision.
- **Device trust:** Firestore rules alone cannot check that the caller's
  device is active. That takes a device proof verified by a Function, and
  Functions need Blaze (D-025).
- **Media:** Call, Watch and Listen need LiveKit token minting (a Function)
  and a decision on media E2EE (FIREBASE-ARCHITECTURE, "LiveKit
  integration"). No media provider is added.

**Candidate directions (not decided):**
- carry Together signals as application messages in the couple's MLS
  conversation (no new server metadata beyond ciphertext; needs the
  messaging service in production);
- or a server session record with explicit presence controls, retention
  and an abuse review.

## 5. Presence

`PartnerPresence`: `unavailable`, `online`, `away`, `offline`,
`inActivity`. There are no timestamps, last-seen values, location, device or
network details. Presence is shown as words plus an icon shape, never colour
alone. Production shows "Presence isn't shared yet": no presence is
collected.

## 6. Web

Web shows the hub with nothing startable and "Time together happens in the
Sirf Hum app on your phone". Together needs a trusted device identity, and
web never has one. No private content is involved.

## 7. Not done

- A production backend: needs the D-112 design and decision, plus Blaze for
  device-trust checks.
- Call, Watch, Listen, games, chat during an activity.
- Notifications for invitations (content-free, D-097 style).
- Real presence and its controls.
