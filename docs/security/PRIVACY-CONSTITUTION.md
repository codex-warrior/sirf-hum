# Privacy Constitution

Status: **Ratified — Prompt 01.** Privacy is a product feature and an
architectural constraint. It is never a paid upgrade.

## The three principles

1. **If Sirf Hum does not need data, Sirf Hum should not collect it.**
2. **If Sirf Hum needs to store private content, Sirf Hum should store
   ciphertext whenever practical.**
3. **If Sirf Hum can perform a function without knowing private content,
   Sirf Hum should not know private content.**

## Rules that follow

| Area | Rule |
| --- | --- |
| Collection | Every collected field has a documented purpose in the phase doc that introduces it. No "might be useful later". |
| Private content | Messages, photos, videos, voice, letters, vault items and private memories are encrypted on device before upload ([E2EE-REQUIREMENTS](E2EE-REQUIREMENTS.md)). |
| Partner boundary | Being a couple does not grant access to the other person's account, devices, contacts, or settings. |
| Notifications | No private content in push payloads by default. *"You have a new message ❤️"*, never *"Rahul: I miss you ❤️"*. |
| Analytics | Behavioural events only, never content ([ANALYTICS-POLICY](ANALYTICS-POLICY.md)). |
| Logs & crashes | No private content, keys, tokens or decrypted payloads in logs or crash reports. Use `AppLogger` only. |
| Advertising | No behavioural advertising. No monetization of conversations, relationship information, memories or emotional data. |
| Third parties | Each third-party SDK is reviewed for data it collects before adoption, recorded in the Decision Log. |
| Ownership | Users can access and export their own data and delete their account. Paying is never required to access one's own data. |
| Claims | We never claim "end-to-end encrypted" until E2EE is implemented and reviewed for that specific feature. TLS, Firebase Auth and Security Rules are **not** E2EE. We never claim a security audit that has not happened. |

## Relationship changes

Relationships end. The product must handle unpairing safely and
humanely. Requirements to design in the identity/E2EE phases:

- Either person can unpair without the other's consent.
- After unpairing, neither person can access *new* content from the other.
- What happens to shared history (both keep a copy? either can delete?) is
  an **open product and legal decision** — not to be decided implicitly by
  engineering. Note: E2EE cannot force deletion of content already on the
  other person's device.
- An abusive partner scenario must be considered for every shared feature
  (see [THREAT-MODEL](THREAT-MODEL.md)).

## Regulatory note

Applicable law (e.g. India's Digital Personal Data Protection Act 2023,
GDPR if serving the EU, app-store privacy disclosures) has **not yet been
reviewed**. Legal review is required before public launch.
