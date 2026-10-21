import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sirf_hum/app/router.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/session/sign_in_controller.dart';

/// Where an email sign-in App Link lands (D-138). Hands the link to the
/// sign-in controller once, then shows the welcome, which reflects the
/// result. The link is validated there, never trusted because it arrived
/// as a deep link.
class AuthLinkScreen extends ConsumerStatefulWidget {
  const AuthLinkScreen({required this.location, super.key});

  /// Path and query as the router received them.
  final Uri location;

  @override
  ConsumerState<AuthLinkScreen> createState() => _AuthLinkScreenState();
}

class _AuthLinkScreenState extends ConsumerState<AuthLinkScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(signInProvider.notifier).receiveLink(widget.location.toString());
      context.go(EntryRoutes.welcome);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: AppPage(title: 'Sirf Hum', children: []),
  );
}
