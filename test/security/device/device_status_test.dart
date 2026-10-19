import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/device/device_status.dart';

void main() {
  // Prompt 08 (D-069, D-075): registration moved server-side and `rejected`
  // / `expired` were added; every trust-creating step is server-only.
  const legal = {
    (DeviceStatus.unknown, DeviceStatus.pending),
    (DeviceStatus.pending, DeviceStatus.active),
    (DeviceStatus.pending, DeviceStatus.rejected),
    (DeviceStatus.pending, DeviceStatus.expired),
    (DeviceStatus.pending, DeviceStatus.revoked),
    (DeviceStatus.active, DeviceStatus.revoked),
  };

  test('exactly the documented transitions are legal', () {
    for (final from in DeviceStatus.values) {
      for (final to in DeviceStatus.values) {
        expect(
          from.canTransitionTo(to),
          legal.contains((from, to)),
          reason: '$from -> $to',
        );
      }
    }
  });

  test('revoked, rejected and expired are terminal: no way back', () {
    for (final terminal in [
      DeviceStatus.revoked,
      DeviceStatus.rejected,
      DeviceStatus.expired,
    ]) {
      expect(terminal.isTerminal, isTrue);
      for (final to in DeviceStatus.values) {
        expect(terminal.canTransitionTo(to), isFalse, reason: '$terminal');
      }
    }
    for (final live in [
      DeviceStatus.unknown,
      DeviceStatus.pending,
      DeviceStatus.active,
    ]) {
      expect(live.isTerminal, isFalse);
    }
  });

  test('only the server registers, activates, rejects and expires', () {
    for (final t in [
      (DeviceStatus.unknown, DeviceStatus.pending),
      (DeviceStatus.pending, DeviceStatus.active),
      (DeviceStatus.pending, DeviceStatus.rejected),
      (DeviceStatus.pending, DeviceStatus.expired),
    ]) {
      expect(
        DeviceStatus.transitions[t],
        DeviceTransitionActor.server,
        reason: '$t',
      );
    }
    // The owner may revoke (a safety action), never anything else.
    expect(
      DeviceStatus.transitions[(DeviceStatus.active, DeviceStatus.revoked)],
      DeviceTransitionActor.clientOrServer,
    );
    expect(
      DeviceStatus.transitions.values,
      isNot(contains(DeviceTransitionActor.client)),
    );
  });

  test('server values parse strictly; unknown values fail closed', () {
    expect(DeviceStatus.fromServer('pending'), DeviceStatus.pending);
    expect(DeviceStatus.fromServer('active'), DeviceStatus.active);
    expect(DeviceStatus.fromServer('revoked'), DeviceStatus.revoked);
    expect(DeviceStatus.fromServer('rejected'), DeviceStatus.rejected);
    expect(DeviceStatus.fromServer('expired'), DeviceStatus.expired);
    for (final bad in ['ACTIVE', 'approved', '', null, 1, 'unknown']) {
      expect(DeviceStatus.fromServer(bad), isNull, reason: '$bad');
    }
  });
}
