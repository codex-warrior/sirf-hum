import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/device/device_status.dart';

void main() {
  const legal = {
    (DeviceStatus.unknown, DeviceStatus.pending),
    (DeviceStatus.pending, DeviceStatus.active),
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

  test('revoked is terminal: never back to active or pending', () {
    for (final to in DeviceStatus.values) {
      expect(DeviceStatus.revoked.canTransitionTo(to), isFalse);
    }
  });

  test('only the server activates; the client registers', () {
    expect(
      DeviceStatus.transitions[(DeviceStatus.pending, DeviceStatus.active)],
      DeviceTransitionActor.server,
    );
    expect(
      DeviceStatus.transitions[(DeviceStatus.unknown, DeviceStatus.pending)],
      DeviceTransitionActor.client,
    );
  });

  test('server values parse strictly; unknown values fail closed', () {
    expect(DeviceStatus.fromServer('pending'), DeviceStatus.pending);
    expect(DeviceStatus.fromServer('active'), DeviceStatus.active);
    expect(DeviceStatus.fromServer('revoked'), DeviceStatus.revoked);
    for (final bad in ['ACTIVE', 'approved', '', null, 1, 'unknown']) {
      expect(DeviceStatus.fromServer(bad), isNull, reason: '$bad');
    }
  });
}
