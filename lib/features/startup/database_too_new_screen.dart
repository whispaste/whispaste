/// Start screen for a database written by a newer WhisPaste build.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database_too_new_exception.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';
import 'startup_screen_frame.dart';

/// Explains that the data needs a newer WhisPaste and offers only quitting.
/// Nothing is opened, changed or deleted, so the next step is an update.
class DatabaseTooNewScreen extends ConsumerWidget {
  const DatabaseTooNewScreen({super.key, required this.exception});

  final DatabaseTooNewException exception;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return StartupScreenFrame(
      key: const ValueKey('database-too-new-screen'),
      title: l10n.databaseTooNewTitle,
      children: [
        WpErrorNotice(
          cause: l10n.databaseTooNewCause(
            exception.storedVersion,
            exception.supportedVersion,
          ),
          nextStep: l10n.databaseTooNewNextStep,
        ),
        const SizedBox(height: WpSpacing.xl),
        WpButton(
          key: const ValueKey('database-too-new-quit'),
          label: l10n.databaseTooNewQuit,
          variant: WpButtonVariant.primary,
          onPressed: () => quitFromStartupScreen(context),
        ),
      ],
    );
  }
}
