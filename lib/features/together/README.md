# Together

The Together hub (Prompt 14, D-111, D-112):

- `domain/`: `TogetherActivity`, the sealed ID-free `TogetherState`, and the
  `TogetherBackend` realtime port (no identifiers).
- `application/together_controller.dart`: the only producer of
  `TogetherState`. It runs only for a paired session and fails closed.
- `presentation/together_screen.dart`: partner and presence, activities, and
  the session panel.

Production wires no backend, so nothing is startable yet. The fake backend
is in `test/support/together_fakes.dart`. Design:
`docs/architecture/TOGETHER-ARCHITECTURE.md`.
