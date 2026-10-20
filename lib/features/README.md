# `lib/features` — product areas

One folder per product area. Each feature grows these layers only when it
needs them (do not create empty layers):

```
features/<area>/
  presentation/   widgets, pages, view-specific state (reads application/)
  application/    Riverpod providers / controllers, use-case orchestration
  domain/         pure Dart models and rules (no Flutter, no Firebase)
  data/           repositories talking to lib/infrastructure and lib/security
```

Dependency direction: `presentation → application → domain ← data`.
Features never import another feature's `data/` or `presentation/`; shared
concepts move to `lib/core` (or a shared domain) after review.

Areas: `home`, `together`, `moments`, `future`, `us`. `notebook` is not an
area: it is the couple notebook shared by Future, Us and Home (D-121), so
those three may import it. "Our Money" is a
future area and must not be created without an explicit, reviewed phase.
