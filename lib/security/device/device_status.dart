/// A device record's lifecycle state (D-069, D-075, DEVICE-IDENTITY.md §3).
///
/// ```text
///                  ┌──server: first device's proof of possession──┐
/// unknown ─server─► pending                                       ├─► active
///  (registerDevice)    │  └─server: approval by a trusted device ─┘     │
///                      │           or the recovery key                 │
///                      ├─server─► rejected (owner rejected it)          │
///                      ├─server─► expired  (never activated in time)    │
///                      └─signed by a trusted device ─► revoked ◄────────┘
///                        (D-081) or identity reset (D-082)
/// ```
///
/// `revoked`, `rejected` and `expired` are terminal: there is no way back,
/// not even through re-registration (records are never deleted and device
/// IDs/keys are indexed forever). A device that must work again gets a NEW
/// identity (new keys, new device ID).
enum DeviceStatus {
  /// No record exists on the server.
  unknown,

  /// Registered; not yet trusted.
  pending,

  /// Trusted: bootstrap proof (first device) or an approval.
  active,

  /// Retired. Terminal.
  revoked,

  /// Rejected by the account owner during approval. Terminal.
  rejected,

  /// Not activated within the server's deadline. Terminal.
  expired;

  bool get isTerminal => this == revoked || this == rejected || this == expired;

  /// Who may perform a transition. Mirrors firebase/firestore.rules and
  /// functions/src/device; the server enforces it, this copy only lets the
  /// client avoid asking for the impossible.
  static const Map<(DeviceStatus, DeviceStatus), DeviceTransitionActor>
  transitions = {
    (unknown, pending): DeviceTransitionActor.server,
    (pending, active): DeviceTransitionActor.server,
    (pending, rejected): DeviceTransitionActor.server,
    (pending, expired): DeviceTransitionActor.server,
    (pending, revoked): DeviceTransitionActor.trustedDeviceSignature,
    (active, revoked): DeviceTransitionActor.trustedDeviceSignature,
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
    'rejected' => rejected,
    'expired' => expired,
    _ => null,
  };
}

/// No transition is a client write (firebase/firestore.rules deny them all).
enum DeviceTransitionActor {
  /// The server decides (bootstrap proof, approval, recovery, expiry).
  server,

  /// The server executes a trusted device's signed request (revocation;
  /// identity reset revokes as the server).
  trustedDeviceSignature,
}
