# Design Tokens

Status: **Foundation implemented (Prompt 01). Values are provisional.**

Code: `lib/design_system/`. Import only the barrel:

```dart
import 'package:sirf_hum/design_system/design_system.dart';
```

## Architecture

```text
ColorPalette (primitives, private to design_system)
      │
      ▼
SemanticColors (ThemeExtension, light + dark)  ──►  AppTheme.light()/dark()  ──►  MaterialApp
TypeScale / Spacing / Radii / Elevation / IconSizes / TouchTargets / Motion / WindowSize
      │
      ▼
Feature widgets (read Theme / context.colors / token constants — never literals)
```

- **Primitives** (`tokens/color_palette.dart`) are not exported by the
  barrel. Feature code cannot reach them, so the palette can change freely.
- **Semantic colors** (`tokens/semantic_colors.dart`) name *roles*:
  `background`, `surface`, `surfaceMuted`, `textPrimary`, `textSecondary`,
  `accent`, `onAccent`, `border`, `focusRing`, `success`, `warning`, `danger`.
  Access: `context.colors.textPrimary`.
- **Theme** (`theme/app_theme.dart`) maps tokens onto Material `ThemeData`
  so stock widgets inherit them.

## Token catalogue

| Category | Tokens | Notes |
| --- | --- | --- |
| Color (semantic) | see above, light + dark | AA contrast enforced by tests |
| Typography | `display 28`, `hero 22`, `title 20`, `heading 16`, `body 15`, `bodyStrong 15`, `secondary 14`, `label 13`, `caption 12` | Plus Jakarta Sans, bundled (`assets/fonts`, OFL; D-156); calmer scale and explicit letter spacing (D-158). 12 is the floor. |
| Font weights | `regular 400`, `medium 500`, `semibold 600`, `bold 700` | `display` is bold |
| Spacing | `xxs 2, xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, xxxl 48`; gutters 16/24 | 4-pt grid |
| Radii | `none 0, sm 6, md 12, lg 20, xl 28, pill 999` | `xl` is for hero cards only |
| Elevation | `flat 0, raised 1, overlay 3, modal 6` | Used sparingly |
| Icon sizes | `sm 16, md 24, lg 32` | |
| Touch targets | `minimum 48`, `comfortable 56` | 48 satisfies Material 48dp and Apple 44pt |
| Motion durations | `fast 120ms, standard 220ms, slow 360ms, expressive 560ms` | Always via `Motion.resolve` |
| Motion curves | `enter easeOutCubic, exit easeInCubic, move easeInOutCubic` | |
| Breakpoints | `compact <600, medium 600–839, expanded ≥840`; `maxContentWidth 720` | Material 3 window classes |

Shadows: none defined beyond Material elevation. Add shadow tokens only
when the identity phase specifies them.

## Visual identity v1: "night intimacy" (D-156)

Chosen by the owner from reference screens (2026-10-24).

- **Night first.** The app runs in the dark theme (`themeMode: dark`). Warm
  near-blacks: background `#0E0B0A`, tiles `#1A1514`, borders `#241D1B`. The
  light theme stays complete and tested, but is not shown.
- **One peach accent** `#EBA48E`: icons in tiles, the selected tab, the one
  filled button.
- **The dusk scene** (`DuskScene`): a painted evening sky (violet to peach),
  a crescent moon and a leafy silhouette. The brand's only illustration,
  used behind hero cards and as the placeholder for a missing photo. Painted,
  so there are no image assets and no network.
- **Typeface:** Plus Jakarta Sans, bundled. Devanagari is not covered; Hindi
  text falls back to the system font (open question below).

## Components (Prompt 13, D-109)

A deliberately small set in `lib/design_system/components/`, exported by the
barrel. Add one only when a second screen needs it.

| Component | Use |
| --- | --- |
| `AppPage` | Every page: safe area, gutters, max content width, one scroll view, single header |
| `AppSection` | A titled part of a page, separated by space and a hairline (not a card) |
| `EmptyState` + `StateAction` | Human "nothing yet" with at most one next step |
| `ErrorState` | Human copy + one action (or none when no tap helps); takes copy, never exceptions |
| `Skeleton` / `SkeletonBlock` | Layout-shaped loading; one screen-reader label; still under reduced motion |
| `Notice` | Quiet inline fact (web private-content boundary, "coming in an upcoming version") |
| `CoupleMark` | Two overlapping initials in accent rings until photos exist; decorative to screen readers |
| `HeroCard` (+ `HeroIcon`) | The one large card on a screen, over the dusk scene; one button with one label |
| `ActionTile` | Soft square choice (icon + label); an optional badge ("Soon") for what is not built, which still answers a tap to say so |
| `DuskScene` | The painted sky, decorative |

Buttons come from `AppTheme`:

- `FilledButton` (accent, 56 dp high) is the one primary action per screen.
- `OutlinedButton` and `TextButton` (48 dp minimum) are for everything else.

The navigation bar shows the selected destination in the accent with a
bolder label and filled icon (no indicator pill); the others use
`textPrimary`.

## Guarantees enforced by tests

- `test/design_system/semantic_colors_contrast_test.dart` — every text/background
  pair ≥ 4.5:1 and focus ring ≥ 3:1 in both themes.
- `test/design_system/layout_and_motion_tokens_test.dart` — breakpoints,
  touch-target minimums, type floor, reduced-motion behaviour.
- `test/app/app_shell_test.dart`:
  - Flutter tap-target, label and text-contrast guidelines on every area, in
    light and dark;
  - no overflow at 200% text on every area.
- `test/design_system/components_test.dart` and
  `test/app/entry_screens_test.dart`: component semantics, touch targets and
  contrast; entry screens.

## Adding or changing tokens

1. Change values in `lib/design_system/tokens/`, never in features.
2. New semantic color → add to both `light` and `dark`, `copyWith`, `lerp`,
   and the contrast test.
3. Update this document and, if it is an identity decision, the Decision Log.

## Open questions

Devanagari/other Indic script support (pair Plus Jakarta Sans with a Hindi
face), iconography set (Material outlines today), haptics tokens, profile
photos in `CoupleMark`, a light-theme identity.
