# App Shell, Navigation and Session State

Status: **Implemented (Prompt 13) — first user-facing foundation.** Not
production-ready: there is no sign-in method yet (D-107), pairing has no UI,
and Functions are not deployed (D-025), so a real build reaches only the
welcome screen. Decisions D-106–D-110.

## 1. Layers

```text
presentation   lib/app/entry/*, lib/app/shell/*, lib/features/<area>/presentation
     │  reads
application    lib/session/session_controller.dart  (Riverpod)  · features/<area>/application
     │  produces
domain         lib/session/session_state.dart (sealed, ID-free) · features/home/domain
     │  through ports
ports          lib/security/account/account_session.dart · lib/security/couple/couple_profiles.dart
               lib/security/couple/pairing.dart (PairingBackend, read-only use)
     │  implemented by
infrastructure lib/infrastructure/firebase/{firebase_account_session, firestore_couple_profiles,
               callable_pairing_backend}.dart     ← wired only in lib/main.dart
```

- `lib/session/` is new: couple-aware state shared by the router and every
  area. It depends on `core` and `security` ports, never on Firebase or on
  `app/`, so features can read it without depending on the router.
- Widgets never import Firebase and never write to Firestore. Home and the
  areas take navigation as callbacks (wired in `lib/app/router.dart`).

## 2. Session state (D-106)

| State | Means | Route |
| --- | --- | --- |
| `SessionStarting` | restoring the session or asking the server | `/start` (Home-shaped skeleton) |
| `SessionSignedOut` | no account | `/welcome` |
| `SessionNotPaired(canPairHere)` | signed in; server: no couple, no open pairing | `/pair` |
| `SessionPairing(stage, canPairHere)` | server: open pairing (`invitationSent`, `partnerAccepted`, `waitingForPartner`) | `/pair` |
| `SessionPaired(names)` | server: this account is in a couple | shell (`/home` …) |
| `SessionUnavailable(unreachable)` | backend/network failed on the first answer | `/start`, "Try again" |
| `SessionUnavailable(signInAgain)` | server rejected the sign-in (`unauthenticated`) | `/start`, "Sign out" |
| `SessionUnavailable(startFailed)` | Firebase could not start in a configured build | `/start`, "reopen the app" |

Rules (enforced in `SessionController`, tested in
`test/session/session_controller_test.dart`):

- **Server-authoritative.** The couple comes only from `getPairingState`
  (strictly parsed by `PairingState.parse`). A malformed or unknown answer is
  `unavailable`, never a state. No backend means `unavailable`, never "not
  paired". No URL, deep link, query parameter, cache or widget can produce
  `SessionPaired`.
- **ID-free.** States carry no account, couple, pairing, conversation or
  device IDs, no tokens and no confirmation code. Rendering any state cannot
  leak one. Display names are re-validated with the rules' constraint
  (`CoupleNames.sanitize`) and never logged.
- **Account changes win.** Each account change bumps a generation; answers
  for an earlier account (or after sign-out) are dropped.
- **Content already shown stays.** A failed *refresh* keeps the current
  state; only a first answer can fail into `unavailable`. A refresh that finds
  the sign-in rejected always replaces it.
- **Refresh triggers:** app resumed (`AppLifecycleListener`), "Try again",
  "Check again". No polling.
- **Nothing persisted.** No session, couple or name is written to local
  storage or preferences.
- **Logs:** `session_resolved {state, kept_previous}` with the state kind
  only.

`canPairHere` is false on web: pairing steps are signed by the device key
(D-102), and web never holds one (`LocalDeviceIdentityService` refuses web).

## 3. Navigation (D-108)

- **Entry routes** (`/start`, `/welcome`, `/pair`) sit outside the shell.
- **Shell:** `StatefulShellRoute.indexedStack`, one branch per
  `ProductArea` (Home, Together, Moments, Future, Us). A bottom
  `NavigationBar` on compact windows and a `NavigationRail` from 600 dp.
  Re-selecting an area returns to its root. No drawer, no hamburger, no
  nested tabs.
- **Redirect** (`redirectFor`, pure and unit-tested) runs on every navigation
  and whenever the session changes. The shell renders only for
  `SessionPaired`. Everything else is sent to its entry route. This is
  navigation, not authorization: rules and callables decide access.
- **Deep links** to an area opened while loading are carried as
  `/start?from=/moments` and honoured once paired. Only exact area paths
  survive; anything else falls back to Home.

## 4. Screens

| Screen | Content | Primary action |
| --- | --- | --- |
| Start | Home-shaped skeleton; or an error state | Try again / Sign out / none |
| Welcome | What Sirf Hum is; "Signing in opens in an upcoming version" | none (no fake button) |
| Pair | Pairing explained in three steps, or the open pairing's stage | Check again |
| Home | Greeting + couple mark + names; "Start something together" → Together; Recently (Moments empty state); Coming up (Future empty state); web notice | Go to Together |
| Together / Moments / Future | Area title and purpose + an honest entry state ("… is on its way") | none yet |
| Us | The couple's names, what will live here, sign-out (confirmed) | Sign out |

Home shows only what exists. Presence, calls, moments and plans are not
built, so their places are deliberate empty states that lead to the area
where each will live. There is no sample data anywhere.

## 5. Loading, empty and error conventions

- **Loading:** a `Skeleton` shaped like the destination (Home's layout), one
  screen-reader label ("Opening Sirf Hum"), a pulse that stops under reduced
  motion. No full-screen spinners.
- **Empty:** `EmptyState` with a human title ("Your first memory is
  waiting."), one sentence of value, and the one next step when one exists.
  Never "No data available".
- **Error:** `ErrorState` takes copy, not exceptions. It says what happened
  and what to do, with one action, or none when no tap can help. It never
  shows codes, Firebase messages, IDs, paths or crypto errors.
- **Notice:** a quiet inline line for facts about the screen (web boundary,
  "coming in an upcoming version").

## 6. Web and private content

Web renders the shell and non-private UI only (WEB-SECURITY Option C,
D-046). `privateContentAvailableProvider` is false on web. Home, Together and
Moments then say where private content lives ("…open in the Sirf Hum app on
your phone"). Pairing on web points to the phone. Nothing on web reads, caches
or decrypts private content, and nothing tries to work around this.

## 7. Firebase start-up (D-110)

On web, `Firebase.initializeApp` also waits for Firebase Auth to restore its
session from IndexedDB. Where IndexedDB never settles (blocked storage,
some private modes, headless browsers), it never returns, and the app would
stay blank. `FirebaseBootstrap` bounds the wait (10 s). Past it, the status
is `failed`, and a configured build then reports `startFailed` (never
"signed out").

## 8. Not done

- Sign-in (method undecided, D-107), pairing screens (invite link or QR,
  code comparison, confirm), profile editing, device management, partner
  presence, calls, moments, plans, notifications permission UI.
- `FirestoreCoupleProfiles` has no automated test (no Firestore fake in the
  project). The rules it relies on are covered by the rules emulator tests.
- Visual identity is still provisional (DESIGN-TOKENS). The platform font,
  Material icons and the provisional palette are used.
