import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/design_system.dart';

/// Signed out. Sign-in is not built yet and its method is an open product
/// decision (D-107), so this screen says so plainly instead of offering a
/// button that does nothing.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPage(
        title: 'Sirf Hum',
        subtitle: 'A private home for the two of you.',
        children: [
          Text(
            'One place to talk, spend time together, keep your memories '
            'and plan what’s next. Just the two of you.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.xxl),
          const Notice(
            icon: Icons.schedule_outlined,
            message: 'Signing in opens in an upcoming version of Sirf Hum.',
          ),
        ],
      ),
    );
  }
}
