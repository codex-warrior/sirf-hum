import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The local clock for the "together for …" display, injectable for tests.
final togetherClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
