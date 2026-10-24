import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/router.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/session/session_controller.dart';

class SirfHumApp extends ConsumerStatefulWidget {
  const SirfHumApp({super.key, this.initialLocation});

  final String? initialLocation;

  @override
  ConsumerState<SirfHumApp> createState() => _SirfHumAppState();
}

class _SirfHumAppState extends ConsumerState<SirfHumApp> {
  // Bumped on every session change so the router re-runs its redirect.
  final _sessionChanged = ValueNotifier<int>(0);
  late final GoRouter _router;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      sessionProvider,
      (_, _) => _sessionChanged.value++,
      fireImmediately: true,
    );
    _router = buildRouter(
      session: () => ref.read(sessionProvider),
      refresh: _sessionChanged,
      initialLocation: widget.initialLocation,
    );
    // Returning to the app asks the server again ("Return" in the core
    // loop): a couple formed or a sign-in ended while away shows up.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(sessionProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    _sessionChanged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sirf Hum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Visual identity v1 is night-first (D-156): the dusk scenes and warm
      // blacks are the brand. The light theme stays complete and tested.
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
