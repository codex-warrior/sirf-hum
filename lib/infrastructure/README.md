# `lib/infrastructure` — backend and external services

Concrete integrations: Firebase (Auth, Firestore, Storage, Functions, FCM,
App Check, Crashlytics, Remote Config) and LiveKit.

Rules:

- Feature `data/` layers depend on interfaces; the Firebase SDK is imported
  only from `lib/infrastructure/**` and feature `data/` folders.
- Private relationship content crosses this layer only as
  `EncryptedEnvelope` (see `lib/security/README.md`).
- Firebase is initialized only by `firebase/firebase_bootstrap.dart`.
- Server-side authorization (Security Rules, Cloud Functions) is the source
  of truth. Client checks are UX, not security.

See `docs/architecture/FIREBASE-ARCHITECTURE.md`.
