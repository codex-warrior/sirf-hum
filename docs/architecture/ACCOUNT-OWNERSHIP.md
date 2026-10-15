# Account Ownership

Status: **Current state recorded; target structure recommended (Prompt 03).**
Nothing has been transferred. No company or legal entity is assumed to exist.

## Why this matters

Sirf Hum must not depend permanently on one person's personal accounts. If
that person loses access (lost phone, locked account, departure), the
product could lose its production database, signing keys, domains or store
listings. Users' private history depends on that not happening.

## Current state (2026-10-15)

| Asset | Owner today | Single point of failure? |
| --- | --- | --- |
| Firebase / GCP projects `sirf-hum-dev`, `-staging`, `-prod` | Personal Google account `ahamshashvat@gmail.com` (sole owner) | **Yes** |
| Billing | None linked (Spark plan) | — |
| GitHub repository `codex-warrior/sirf-hum` (private) | Personal GitHub account `codex-warrior`, free plan | **Yes** |
| GitHub Actions → GCP deploy identities | Service accounts `github-deployer@<project>` via Workload Identity Federation; no keys | No (no exportable credential) |
| Domain `sirfhum.com` | Unknown / not recorded | To confirm |
| Google Play / Apple Developer accounts | Not created | — |
| Android upload key, Apple certificates | Not created | — |

Two different personal identities are involved (the Google account and the
GitHub account). The relationship between them is not recorded here.

## Recommended target structure

```text
Legal entity (when one exists)
        ↓
Organization accounts owned by the entity
   - Google Cloud Organization (via Cloud Identity / Workspace on the company domain)
   - GitHub Organization
   - Apple Developer (organization enrollment, needs D-U-N-S)
   - Google Play Console (organization account)
   - Domain registrar account
        ↓
At least two administrators per account, each with hardware-key 2FA
        ↓
Least-privilege groups for everyone else (developers, QA, support)
        ↓
Automation identities (Workload Identity Federation, no keys)
```

Principles:

1. **No sole owners.** Every critical account has ≥ 2 owners/admins, using
   company-domain identities rather than personal Gmail where possible.
2. **Groups, not individuals.** Grant IAM roles to groups
   (e.g. `sirfhum-prod-admins@`), so joining or leaving is one change.
3. **Production is special.** Production project Owner limited to the admin
   group; developers get Viewer or narrower roles in production and broader
   roles in development.
4. **Break-glass.** A documented, offline-stored recovery path for each
   critical account (recovery codes in a password manager shared by admins).
5. **Keys live in managed stores.** Signing keys in Play App Signing / an
   HSM-backed secret manager, never on one laptop.

## Migration steps (when ready; none performed yet)

1. Decide the owning entity (or, until one exists, add a second trusted
   co-owner to every account).
2. Create the GitHub Organization; transfer `codex-warrior/sirf-hum` into it
   (GitHub keeps redirects). **Update `REPO_ID`/`OWNER_ID` in
   `tool/setup_github_wif.sh` if the owner ID changes and re-run it**, since
   Workload Identity conditions are bound to the repository owner's numeric ID.
3. Create a Google Cloud Organization (Cloud Identity on the company domain)
   and move the three projects into it; add a second Owner on each project
   before moving.
4. Link billing from an organization billing account when Blaze is needed.
5. Enroll Apple Developer and Google Play as organizations.
6. Record each change in the Decision Log (supersedes D-025).

## GitHub plan limitation

On the current free personal plan, the private repository **cannot** use
branch protection, rulesets, or required reviewers on environments (GitHub
API: "Upgrade to GitHub Pro or make this repository public"). A GitHub
Organization on the Team plan (or Pro for a personal account) enables them.
See ENVIRONMENTS.md for the compensating controls in place meanwhile.
