import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../widgets/empty_state.dart';

/// Analytics dashboard page.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WpEmptyState(
      icon: LucideIcons.chartNoAxesColumn,
      title: 'Usage Analytics',
      hint: 'Recording statistics and usage insights will appear here.',
    );
  }
}
