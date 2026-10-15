# Product Constitution

Status: **Ratified — Prompt 01 (2026-10-15).** Changes require a Decision Log entry.

## 1. Identity

- **Name:** Sirf Hum ("Just Us").
- **Positioning:** *Sirf Hum is the private digital home for two people.*
- **Ambition:** every couple should have a Sirf Hum account.

## 2. What Sirf Hum is — and is not

Sirf Hum **is** a private digital world shared by two people.

Sirf Hum is **not**: another messaging app, a social network, a productivity
tool, a dating app, a generic couples game, or a dashboard of relationship
statistics.

## 3. The core loop

```text
CONNECT → SPEND TIME TOGETHER → CREATE MEMORIES → PLAN THE FUTURE → GROW TOGETHER → RETURN
```

**Test for every feature:** does it strengthen this loop? If not, question
whether it belongs in Sirf Hum. Record the answer in the feature's phase doc.

## 4. Product areas

| Area         | Role                          | Future functionality (not built yet)                                                              |
| ------------ | ----------------------------- | ------------------------------------------------------------------------------------------------- |
| **Home**     | The emotional front door      | Partner presence, quick call, Start Together, quick message, today's ritual/question, upcoming plan, recent moment |
| **Together** | The realtime relationship space | Voice/video call, Watch Together, Listen Together, shared activities, games, voice interactions, screen sharing where appropriate |
| **Moments**  | The couple's private history  | Photos, videos, voice memories, letters, timeline, firsts, important and private memories        |
| **Future**   | Where the couple is going     | Plans, dates, trips, bucket lists, dreams, goals, milestones, reminders                          |
| **Us**       | The deeper relationship layer | Couple profile, rituals, private vault, letters, preferences, privacy, devices, account settings |

Home must answer: *Is my person around? What can we do together? What's
happening today? What's coming next? What happened recently?*

Moments principle: *the longer a couple uses Sirf Hum, the more valuable
their private history becomes* — which is why that history must be private,
durable, and exportable by its owners.

### Future area — Our Money (not V1)

A sixth area, **Our Money** (savings goals, shared financial goals,
planning, regulated investment partnerships), may come after product-market
fit, legal analysis, compliance planning and regulated partnerships.

- Not implemented in V1. No placeholder in the app.
- No fake or simulated investment functionality, ever.
- Sirf Hum will not operate as an unregulated investment platform.

## 5. Experience requirements

The product must be: extremely easy to use, emotionally meaningful,
visually premium, privacy-first, technically robust, fast, accessible,
reliable and scalable. A non-technical person must understand the basics
without a manual. Details: [UX-PRINCIPLES.md](UX-PRINCIPLES.md).

## 6. Human language

The UI hides technical complexity. Users see **Call**, not "initialize
WebRTC session"; **Watch Together**, not "synchronize media state";
**Plan something together**, not "create shared event".

## 7. Identity model

A couple is **two independent people**, not one shared account. Pairing
never grants one partner access to the other's account or devices. See
[../security/E2EE-REQUIREMENTS.md](../security/E2EE-REQUIREMENTS.md#identity-model).

## 8. Definition of done (all future features)

A feature is not done because its happy path works. As applicable it
includes: happy path, loading, empty, error, offline, retry, recovery,
accessibility, responsive layout, server-side authorization, analytics
review (per [ANALYTICS-POLICY.md](../security/ANALYTICS-POLICY.md)), tests,
and documentation updates.

## 9. Related documents

[PRODUCT-VISION.md](PRODUCT-VISION.md) ·
[UX-PRINCIPLES.md](UX-PRINCIPLES.md) ·
[../design/DESIGN-CONSTITUTION.md](../design/DESIGN-CONSTITUTION.md) ·
[../security/PRIVACY-CONSTITUTION.md](../security/PRIVACY-CONSTITUTION.md) ·
[../business/BUSINESS-MODEL.md](../business/BUSINESS-MODEL.md)
