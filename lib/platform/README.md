# `lib/platform` — platform services boundary

Wrappers over device capabilities whose behaviour differs between Android,
iOS and Web: permissions, camera/microphone, secure storage, notifications
plumbing, background execution, haptics, share sheets.

Rules:

- Expose a small Dart interface; keep platform branching (`kIsWeb`,
  conditional imports, method channels) inside this folder.
- Every capability must report "unsupported on this platform" explicitly
  rather than failing silently (Web lacks several mobile capabilities).
- Permission flows must have a denied/permanently-denied state the UI can
  explain in human language.

Empty in Prompt 01 by design.
