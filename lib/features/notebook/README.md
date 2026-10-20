# Notebook (shared by Future and Us)

Not an area: the couple notebook that Future, Us and Home read (Prompt 16,
D-118–D-121, `docs/architecture/FUTURE-AND-US-ARCHITECTURE.md`).

- `domain/notebook_state.dart`: the sealed, ID-free `NotebookState`.
- `application/notebook_controller.dart`: its only producer, and
  `notebookBackendProvider` (production: `null`, D-121).
- `presentation/`: the one editor, the shared non-ready states, copy.

The security-sensitive part (kind-4 format, assembly rules, the service over
`MessagingService`) is in `lib/security/notebook/`. Fakes for tests are in
`test/support/notebook_fakes.dart`.
