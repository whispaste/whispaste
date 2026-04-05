import 'package:flutter/material.dart';
import '../../widgets/empty_state.dart';

/// Analytics dashboard page.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement usage stats dashboard
    return const WpEmptyState(
      icon: Icons.bar_chart_rounded,
      title: 'Usage Analytics',
      hint: 'Recording statistics and usage insights will appear here.',
    );
  }
}
