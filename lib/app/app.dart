import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/router.dart';
import 'package:sirf_hum/design_system/design_system.dart';

class SirfHumApp extends StatefulWidget {
  const SirfHumApp({super.key, this.initialLocation});

  final String? initialLocation;

  @override
  State<SirfHumApp> createState() => _SirfHumAppState();
}

class _SirfHumAppState extends State<SirfHumApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sirf Hum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
    );
  }
}
