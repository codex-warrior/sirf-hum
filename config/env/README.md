# Build-time environment configuration

One file per environment, passed to every build:

```sh
flutter run --flavor development --dart-define-from-file=config/env/development.json
```

| File | Committed? | Contents |
| --- | --- | --- |
| `<env>.example.json` | Yes | Shape and non-sensitive defaults, `<generated>` placeholders |
| `development.json`, `staging.json`, `production.json` | **No** (git-ignored) | Real values for that environment |

Generate the real file from the live Firebase project (requires
`firebase login` and access to the project):

```sh
node tool/generate_env_config.mjs development
```

- Values are **client identifiers, not secrets**; they ship inside the app.
  Never put a secret here (LiveKit API secret, service-account keys, signing
  keys, App Check debug tokens).
- `production.json` is not kept on developer machines by default; CI writes it
  from the `production` GitHub Environment secret `SH_ENV_CONFIG_JSON`.
- With no file, the app runs as `development` with Firebase "not configured".
- The app refuses to start if the file's project does not belong to the
  build's environment/flavor (`lib/app/environment_guard.dart`).

Keys: `SH_ENV`, `SH_FIREBASE_*` (per-platform app IDs and API keys),
`SH_APPCHECK_PROVIDER` (`debug` | `attestation`),
`SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY`, `SH_CRASH_REPORTING` (`true` | `false`).
See `docs/architecture/ENVIRONMENTS.md`.
