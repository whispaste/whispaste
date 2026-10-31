/// Start screen for a database upgrade that stopped on a transient error.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';
import 'startup_screen_frame.dart';

/// Explains that the upgrade was rolled back and offers a retry. The retry
/// opens a fresh [HistoryDatabase]: the failed instance keeps its raw
/// connection open and would skip the upgrade on a second open.
class DatabaseUpgradeInterruptedScreen extends ConsumerWidget {
  const DatabaseUpgradeInterruptedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return StartupScreenFrame(
      key: const ValueKey('database-upgrade-interrupted-screen'),
      title: l10n.databaseUpgradeInterruptedTitle,
      children: [
        // Read out on arrival: focus goes to the retry button, so a
        // screen reader would otherwise announce only its label.
        Semantics(
          liveRegion: true,
          child: WpErrorNotice(
            cause: l10n.databaseUpgradeInterruptedCause,
            nextStep: l10n.databaseUpgradeInterruptedNextStep,
          ),
        ),
        const SizedBox(height: WpSpacing.xl),
        Wrap(
          spacing: WpSpacing.sm,
          runSpacing: WpSpacing.sm,
          children: [
            WpButton(
              key: const ValueKey('database-upgrade-retry'),
              label: l10n.actionRetry,
              variant: WpButtonVariant.primary,
              autofocus: true,
              onPressed: () => ref.invalidate(historyDatabaseProvider),
            ),
            WpButton(
              key: const ValueKey('database-upgrade-quit'),
              label: l10n.databaseTooNewQuit,
              variant: WpButtonVariant.secondary,
              onPressed: () => quitFromStartupScreen(context),
            ),
          ],
        ),
      ],
    );
  }
}
