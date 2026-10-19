import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The local clock, injectable so the greeting is testable.
final homeClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
