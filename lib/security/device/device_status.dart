/// A device record's lifecycle state (D-069, DEVICE-IDENTITY.md).
///
/// ```text
/// unknown ──client──► pending ──server (proof verified)──► active
///                        │                                   │
///                        └──────client or server──► revoked ◄┘
/// ```
///
/// `revoked` is terminal. There is no way back, not even through
/// re-registration: a device that must work again gets a NEW device
/// identity (new keys, new device ID), never the old one reactivated.
enum DeviceStatus {
  /// No record exists on the server.
  unknown,

  /// Registered by the client; not yet trusted by the server.
  pending,

  /// Proof of possession verified by the server.
  active,

  /// Retired. Terminal.
  revoked;

  /// Who may perform a transition. Mirrors firebase/firestore.rules and
  /// functions/src/device/registration.ts; the server enforces it, this copy
  /// only lets the client avoid asking for the impossible.
  static const Map<(DeviceStatus, DeviceStatus), DeviceTransitionActor>
  transitions = {
    (unknown, pending): DeviceTransitionActor.client,
    (pending, active): DeviceTransitionActor.server,
    (pending, revoked): DeviceTransitionActor.clientOrServer,
    (active, revoked): DeviceTransitionActor.clientOrServer,
  };

  bool canTransitionTo(DeviceStatus next) =>
      transitions.containsKey((this, next));

  /// Parses the server's `status` field. Unrecognised values return null so
  /// callers fail closed instead of guessing (a future state is never
  /// treated as active).
  static DeviceStatus? fromServer(Object? value) => switch (value) {
    'pending' => pending,
    'active' => active,
    'revoked' => revoked,
    _ => null,
  };
}

enum DeviceTransitionActor { client, server, clientOrServer }
