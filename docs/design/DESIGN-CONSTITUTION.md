# Design Constitution

Status: **Ratified — Prompt 01.** The visual identity itself is **not yet
decided**; this document governs how it will be designed.

## Core principle

> **The relationship is the hero. The interface should disappear behind it.**

## The feeling

Premium · warm · intimate · modern · calm · confident · human · slightly
playful · emotionally meaningful.

## How we get there

Use **typography, whitespace, photography, hierarchy, subtle motion,
meaningful interaction and carefully designed touch targets** — not
decoration.

## Sirf Hum must not look AI-generated

Avoid:

- excessive glassmorphism
- generic purple/blue gradients; meaningless gradients
- endless floating cards; every component in a rounded rectangle
- overly symmetrical card grids; template dashboards; generic SaaS layouts
- excessive shadows, icons, hearts, or text
- decorative blobs; fake 3D decoration
- wedding-app or childish romance aesthetics

Do not copy Instagram, TikTok, WhatsApp, Snapchat or any other product.
Learn from their usability, build our own visual language.

## Practical rules

1. **Tokens only.** No hard-coded colors, sizes, durations or curves in
   feature code. Use `package:sirf_hum/design_system/design_system.dart`.
   See [DESIGN-TOKENS.md](DESIGN-TOKENS.md).
2. **Hierarchy from type and space first**, elevation and color last.
3. **One accent.** Color draws attention to the one primary action.
4. **Content-first surfaces.** Photos and the partner's presence are the
   richest visual element on a screen; chrome stays quiet.
5. **Hearts are earned.** Romantic iconography appears only where it
   carries meaning, never as decoration.
6. **Motion has a job** (state, connection, success, transition, presence,
   interaction) and always goes through `Motion.resolve` so reduced-motion
   users get instant transitions.
7. **Both themes are first-class.** Every screen is designed and tested in
   light and dark.
8. **Responsive by default.** Compact (phone), medium (large phone/tablet)
   and expanded (tablet/desktop web) layouts; readable content width capped.

## Process for the identity phase

The future design-identity phase should produce: brand typography choice
(with Indic script support evaluated), final palette, iconography style,
motion language, photography treatment, and a component library — each
recorded in the Decision Log and reflected in tokens, not scattered in code.
