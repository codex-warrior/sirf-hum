import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Today" for filing plans (coming up or not). Overridable in tests.
final futureClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
