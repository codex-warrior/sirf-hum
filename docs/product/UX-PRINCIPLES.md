# UX Principles

Status: **Ratified — Prompt 01.** These rules are acceptance criteria for
every screen, not aspirations.

Sirf Hum must be usable by people with zero technical knowledge. It should
feel as immediately understandable as the best consumer apps while keeping
an entirely original identity. We learn from others' **usability**, never
copy their **look**.

## The ten rules

| #  | Rule | What it means in practice |
| -- | ---- | ------------------------- |
| 1  | **Zero learning curve** | Download → Open → Understand → Pair → Use. No step needs explanation. |
| 2  | **Familiar interactions** | Tap, swipe, long-press, pull-to-refresh, bottom navigation — patterns people already know. No novel gestures for core actions. |
| 3  | **Minimize configuration** | Never ask what the product can determine (timezone, language, partner's device, notification channel). |
| 4  | **Intelligent defaults** | The simplest path is the recommended path. Defaults are privacy-protective. |
| 5  | **One primary action** | Each screen has one obvious primary action where practical. |
| 6  | **Advanced stays hidden** | Power features are reachable (overflow, settings, long-press) but never crowd first use. |
| 7  | **Human language** | "Send a little voice", not "create audio message object". "Plan something together", not "create shared calendar event". No engineering terms in UI, errors, or notifications. |
| 8  | **Discoverability over tutorials** | Teach through interaction and empty states. No multi-page tutorial carousels. |
| 9  | **Motion communicates** | Animate to show state, connection, success, transition, presence, interaction. Never just to impress. Respect reduced motion. |
| 10 | **Failure states matter** | Every feature designs loading, empty, error, offline, permission denied, retry, recovery and accessibility states. |

## Writing guidelines

- Short, warm, second person ("Your person is here").
- Say what happened and what to do next. Never blame the user.
- Error copy never exposes codes or stack traces; log those privately.
- Avoid relationship pressure or guilt ("You haven't talked in 3 days").
- Use gender-neutral language by default; do not assume relationship type.

## Failure-state checklist (per screen)

- [ ] Loading: skeleton or progress that matches final layout; no layout jump.
- [ ] Empty: explains the value and offers the one primary action.
- [ ] Error: human message + retry. Content already shown stays visible.
- [ ] Offline: clearly indicated; queued actions shown as pending.
- [ ] Permission denied: explains why it's needed; links to settings when permanently denied.
- [ ] Recovery: returning to the app restores context.
- [ ] Accessibility: semantics labels, 48dp targets, 200% text, reduced motion, contrast.

## One-handed use

Primary actions sit in the thumb zone on phones (lower half of the
screen). Navigation lives at the bottom on compact windows and moves to a
side rail on wider windows (implemented in `lib/app/shell/app_shell.dart`).

## Accessibility constitution

Accessibility is architecture, not polish. Every feature supports:
readable typography, WCAG AA contrast, 48dp minimum touch targets, screen
readers with semantic labels, dynamic text size (tested at 200%), reduced
motion, color-blind safety (color never the sole carrier of meaning),
clear error states, simple language, and one-handed mobile use.

Enforcement already in place: contrast tests for all semantic color pairs,
and Flutter accessibility guideline tests (tap targets, labels, text
contrast) on the app shell in light and dark mode. See
[../testing/TESTING-STRATEGY.md](../testing/TESTING-STRATEGY.md).
