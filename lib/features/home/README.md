# Home

The couple's front door (Prompt 13):

- a greeting, the couple mark and names;
- "Start something together", leading to Together;
- deliberate empty states for Recently (Moments) and Coming up (Future).

Files:

- `presentation/home_screen.dart`: shown only for a paired session; takes
  navigation as callbacks. Also holds `HomeSkeleton` (loading).
- `domain/greeting.dart`: the greeting and the couple title.
- `application/home_providers.dart`: an injectable clock.

Not yet: partner presence, quick call, quick message, rituals, and real
moment and plan previews. Design:
`docs/architecture/APP-SHELL-AND-NAVIGATION.md`.
