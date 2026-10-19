import 'package:flutter/material.dart';
import 'package:sirf_hum/design_system/design_system.dart';

/// Future's entry state. Plans, dates and goals are a later prompt.
class FutureScreen extends StatelessWidget {
  const FutureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppPage(
      title: 'Future',
      subtitle: 'Where the two of you are going.',
      children: [
        EmptyState(
          icon: Icons.event_outlined,
          title: 'Make a plan for the two of you.',
          message:
              'Dates, trips and dreams you plan together will live here. '
              'Planning is on its way.',
        ),
      ],
    );
  }
}
