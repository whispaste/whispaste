import 'package:flutter/material.dart';
import '../../widgets/empty_state.dart';

/// History page — shows recorded transcriptions with search, filter, and grouping.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement full history page with drift database
    return const WpEmptyState(
      icon: Icons.history_rounded,
      title: 'No recordings yet',
      hint: 'Press the record button or use the hotkey to start dictating.',
    );
  }
}
