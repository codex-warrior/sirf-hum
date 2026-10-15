# Development Environment

How a new developer goes from clone to a verified build. Environment model:
[ENVIRONMENTS.md](ENVIRONMENTS.md).

## 1. Install

| Tool | Version | Used for |
| --- | --- | --- |
| Flutter (stable) | 3.41.5 | App (Android, iOS, Web) |
| Node.js | 22 for Functions; ≥ 24.12 for rules tests | Functions, rules tests, scripts |
| Java (JDK) | 21+ | Firebase emulators, Android builds |
| Firebase CLI | 15.x (`npm i -g firebase-tools`) | Emulators, deploys |
| Android Studio / SDK | API 36 | Android builds, emulator |
| Xcode + CocoaPods | macOS only | iOS builds |
| gitleaks (optional) | 8.30.x | Local secret scanning |

```sh
flutter pub get
(cd functions && npm ci)
(cd firebase && npm ci)
```

## 2. Authenticate (only to reach real projects or deploy)

```sh
firebase login            # account with access to the sirf-hum-* projects
```

Emulators and tests need no login (`demo-sirf-hum` project).

## 3. Configure an environment

```sh
node tool/generate_env_config.mjs development   # writes config/env/development.json (git-ignored)
```

The generator reads the live project, so nobody copies keys by hand. To
start without access, copy `config/env/development.example.json` and leave
Firebase values empty; the app then runs "not configured".

## 4. Run the app

```sh
# Android / iOS (flavor and config must name the same environment)
flutter run --flavor development --dart-define-from-file=config/env/development.json

# Web
flutter run -d chrome --dart-define-from-file=config/env/development.json
```

- A mismatched flavor and config aborts at startup by design.
- On first run with the App Check debug provider, copy the debug token from
  the device log and register it in the **development** project's console.

## 5. Emulator tests

```sh
(cd firebase && npm test)
```

Windows: `firebase emulators:exec` can leave the Firestore emulator Java
process running on port 8080. Stop it before re-running.

## 6. Functions locally

```sh
cd functions
npm run check     # typecheck + lint + build + unit tests
npm run serve     # Functions emulator (demo-sirf-hum)
```

## 7. Validate everything

```sh
tool/verify.sh          # format, analyze, unit + widget tests
tool/verify.sh --all    # + Functions, rules tests, web + Android builds
```

iOS is validated by the `ios` CI job on macOS.

## 8. Deploy

```sh
tool/deploy.sh development                    # Firestore rules + indexes
tool/deploy.sh development --only hosting:app
```

Staging and production go through **Actions → Deploy** (environment
selection, protected `production` environment). Never use `firebase use`,
and never run a bare `firebase deploy`.

## OneDrive caveat

This repository currently lives in a OneDrive-synchronized folder. OneDrive
can lock files during builds (Gradle, Xcode, `dart` tooling), slow builds
down, and upload gigabytes of generated output. Recommended: move the repo
to a non-synced path such as `C:\dev\sirf-hum` (not done automatically).
Until then, exclude these from sync. All are already git-ignored:

`build/`, `.dart_tool/`, `android/.gradle/`, `android/app/.cxx/`,
`ios/Pods/`, `ios/.symlinks/`, `functions/node_modules/`, `functions/lib/`,
`firebase/node_modules/`, `coverage/`, `*.log`.

Never sync `config/env/*.json` or `android/key.properties` to shared
locations.
