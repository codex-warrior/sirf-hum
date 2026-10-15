# Threat Model

Status: **Foundation (Prompt 01).** A living document. Each phase that adds
data, endpoints or devices must update it. Not every threat can be
eliminated; the goal is that each one is *explicit*.

## Sensitive assets

| Asset | Sensitivity | Notes |
| --- | --- | --- |
| Messages, letters, private memories | Critical | Core intimate content |
| Photos, videos, voice recordings | Critical | Includes thumbnails and captions |
| Cryptographic keys (identity, device, content) | Critical | Compromise exposes content |
| Account credentials / auth tokens | High | Account takeover |
| Device identities | High | Impersonation of a device |
| Relationship information (who is paired with whom) | High | Itself revealing; risk in hostile environments |
| Presence information (online, in a call, location-like signals) | High | Enables stalking/monitoring |
| Operational metadata (timestamps, sizes, frequency) | Medium | Can reveal patterns |

## Trust boundaries

```text
[Person] ⇄ [Device: app + OS keystore]  ══ TB1: device / network ══  [Firebase: Auth · Firestore · Storage · Functions]
                                                                         ║ TB3: Google infrastructure & operators
[Partner's device] ═══════ TB2: between partners ═══════                 ║
                                                                      [FCM / APNs / Web Push]  [LiveKit]  TB4: third parties
```

- **TB1 Device ↔ network/server:** everything past the device is untrusted for private content.
- **TB2 Partner ↔ partner:** partners are trusted with *shared* content they
  receive, not with each other's accounts, devices or private settings.
- **TB3 Operator:** Sirf Hum staff and Google infrastructure are untrusted for content.
- **TB4 Third parties:** push services, LiveKit, crash/analytics vendors see only what we send.

## Attack surfaces

Client app (all platforms) · web origin (XSS, extensions) · Firebase Auth
flows (sign-in, recovery) · Firestore/Storage via Security Rules · callable
and HTTP Cloud Functions · LiveKit token endpoint and rooms · push payloads ·
pairing/invite flow · device-linking flow · local storage, caches, OS backups ·
logs and crash reports · CI/CD and developer credentials · third-party SDKs.

## Threat actors

| # | Actor | Example attacks | Planned mitigations | Residual risk |
| --- | --- | --- | --- | --- |
| T1 | **Compromised server** (Functions code, config) | Read data, serve malicious keys | E2EE: server never has content keys; key changes signed by identity keys; partner verification | Server can withhold/delay data, observe metadata, attempt key substitution if users don't verify |
| T2 | **Compromised database** | Dump Firestore/Storage | Ciphertext only for private content; minimised metadata | Metadata and relationship graph exposed |
| T3 | **Malicious administrator** | Browse user data, alter rules | E2EE; least-privilege IAM; audit logs; rules in source control with tests | Admin can disrupt service, view metadata |
| T4 | **Compromised device** (malware, root) | Read decrypted content, steal keys | OS keystore, app lock (future), minimal plaintext caching | Largely unmitigable: an owned endpoint sees what the user sees |
| T5 | **Stolen device** | Open app, read history | Rely on OS lock; optional app lock; remote device revocation; keys in hardware keystore | Unlocked stolen phone exposes content until revoked |
| T6 | **Compromised account** (phished credentials, SIM swap) | Sign in on attacker device | New device requires approval from an existing device / identity key; partner notified of new device; strong auth options | If recovery bypasses device approval, attacker gains future content — recovery design is critical |
| T7 | **Revoked / old device** | Continue reading after removal | Server-side revocation in rules; key rotation on revocation; FCM token removal | Content already on that device remains readable |
| T8 | **Man-in-the-middle** | Intercept/alter traffic, substitute keys | TLS; E2EE with authenticated key exchange; key-change warnings; optional verification | Users who never verify trust the key directory on first use |
| T9 | **Malicious third party** (other users, bots) | Enumerate users, spam invites, abuse endpoints | Default-deny rules, App Check (wired Prompt 02; enforcement pending rollout), rate limits, invite codes that expire, no public profiles; no Auth provider enabled before the identity phase | Determined attackers with genuine devices |
| T10 | **Abusive partner** | Monitoring presence/location, coercing access, refusing to unpair, using shared history as leverage | No partner access to the other's account/devices; either person can unpair; presence controls; no hidden tracking; considered "safety" design per feature | Coercion with physical device access cannot be solved technically; content already shared can be retained |
| T11 | **Notification leakage** | Lock-screen previews, push-provider visibility | Content-free payloads; on-device decryption only if ever enabled; per-category preferences | Notification *timing* still visible to push providers and onlookers |
| T12 | **Cloud-storage compromise** | Download media blobs | Client-side encrypted media with per-file keys; opaque object paths | File sizes and counts visible |

**Environment confusion** (a test build or deploy touching production): separate projects, no default CLI project, runtime and Functions environment guards, gated deploys (docs/architecture/ENVIRONMENTS.md).

Additional cross-cutting threats: supply-chain compromise of dependencies
(pin versions, review new SDKs, CI secret scanning); developer credential
leakage (no secrets in repo, separate prod access); logging/crash-report
leakage (`AppLogger` enforces typed fields and redacts raw strings; Crashlytics receives error types only); OS cloud backups of local databases
(exclude or encrypt local stores).

## Assumptions

- Device OS and hardware keystores are not compromised (outside T4).
- Established cryptographic libraries are correctly implemented.
- Firebase enforces Security Rules as documented.
- Users keep their device lock enabled (we encourage but cannot enforce).

## Unresolved risks (tracked)

1. Account recovery vs. E2EE trade-off — undecided (E2EE phase).
2. Web as a device class — key storage weaker; role undecided.
3. Shared history after unpairing — product/legal decision pending.
4. Metadata minimisation — schema-level decisions pending.
5. Abuse/safety design for presence and location-like features — per-feature.
6. No independent security review has been performed.
