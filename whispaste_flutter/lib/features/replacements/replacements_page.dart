import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../widgets/empty_state.dart';

/// Voice Shortcuts (Replacements) page.
class ReplacementsPage extends StatelessWidget {
  const ReplacementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WpEmptyState(
      icon: LucideIcons.replace,
      title: 'No voice shortcuts yet',
      hint: 'Add shortcuts to auto-replace words during dictation.',
      actionLabel: 'Add Shortcut',
    );
  }
}
