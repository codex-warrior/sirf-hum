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
| Typography | `display 34`, `title 24`, `heading 18`, `body 16`, `bodyStrong 16`, `label 14`, `caption 12` | Font family = platform default (provisional). 12 is the floor. |
| Font weights | `regular 400`, `medium 500`, `semibold 600` | |
| Spacing | `xxs 2, xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, xxxl 48`; gutters 16/24 | 4-pt grid |
| Radii | `none 0, sm 6, md 12, lg 20, pill 999` | Rounding is not a default; use deliberately |
| Elevation | `flat 0, raised 1, overlay 3, modal 6` | Used sparingly |
| Icon sizes | `sm 16, md 24, lg 32` | |
| Touch targets | `minimum 48`, `comfortable 56` | 48 satisfies Material 48dp and Apple 44pt |
| Motion durations | `fast 120ms, standard 220ms, slow 360ms, expressive 560ms` | Always via `Motion.resolve` |
| Motion curves | `enter easeOutCubic, exit easeInCubic, move easeInOutCubic` | |
| Breakpoints | `compact <600, medium 600–839, expanded ≥840`; `maxContentWidth 720` | Material 3 window classes |

Shadows: none defined beyond Material elevation. Add shadow tokens only
when the identity phase specifies them.

## Provisional palette

Warm neutrals ("paper" `#FBF7F2` to "ink" `#120F0D`) with one clay accent.
Chosen only to be warm, calm and accessible while the real identity is
designed. **Not a brand decision.**

## Guarantees enforced by tests

- `test/design_system/semantic_colors_contrast_test.dart` — every text/background
  pair ≥ 4.5:1 and focus ring ≥ 3:1 in both themes.
- `test/design_system/layout_and_motion_tokens_test.dart` — breakpoints,
  touch-target minimums, type floor, reduced-motion behaviour.
- `test/app/app_shell_test.dart` — Flutter tap-target, label and text-contrast
  guidelines in light and dark; no overflow at 200% text.

## Adding or changing tokens

1. Change values in `lib/design_system/tokens/`, never in features.
2. New semantic color → add to both `light` and `dark`, `copyWith`, `lerp`,
   and the contrast test.
3. Update this document and, if it is an identity decision, the Decision Log.

## Open questions

Brand typeface (and Devanagari/other Indic script support), final palette,
iconography set, haptics tokens, illustration/photography treatment.
