import 'package:flutter/material.dart';
import '../../widgets/empty_state.dart';

/// Voice Shortcuts (Replacements) page.
class ReplacementsPage extends StatelessWidget {
  const ReplacementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement replacements list + edit panel
    return const WpEmptyState(
      icon: Icons.find_replace_rounded,
      title: 'No voice shortcuts yet',
      hint: 'Add shortcuts to auto-replace words during dictation.',
      actionLabel: 'Add Shortcut',
    );
  }
}
