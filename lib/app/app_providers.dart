import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sirf_hum/app/app_config.dart';
import 'package:sirf_hum/infrastructure/firebase/firebase_bootstrap.dart';

/// Root providers. Both are overridden in `main.dart` (and in tests) with
/// values computed before `runApp`; reading them un-overridden is a bug.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

final firebaseStatusProvider = Provider<FirebaseStatus>(
  (ref) =>
      throw UnimplementedError('firebaseStatusProvider must be overridden'),
);
