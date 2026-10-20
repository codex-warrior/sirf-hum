# Moments

The couple's private memory timeline (Prompt 15, D-113–D-117,
`docs/architecture/MOMENTS-ARCHITECTURE.md`):

- `domain/moments_state.dart`: the sealed, ID-free `MomentsState`.
- `application/moments_controller.dart`: the only producer of that state,
  `momentsBackendProvider` (production: `null`, D-116) and the in-memory
  photo loader. `application/moment_composer.dart`: the new-memory flow.
  `application/moment_photo_picker.dart`: the picker port.
- `data/system_photo_picker.dart`: the port over `image_picker` (Android,
  wired in `main.dart`; it implements the application port).
- `presentation/`: timeline, tile, detail, new memory.

The security-sensitive part (manifest format, timeline rules, the service
over `MessagingService`) is in `lib/security/moments/`. Fakes for tests are
in `test/support/moments_fakes.dart`. No sample data.
