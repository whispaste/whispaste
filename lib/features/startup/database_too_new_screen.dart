/// Start screen for a database written by a newer WhisPaste build.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/data/database_too_new_exception.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../services/graceful_shutdown.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';

/// Explains that the data needs a newer WhisPaste and offers only quitting.
/// Nothing is opened, changed or deleted, so the next step is an update.
class DatabaseTooNewScreen extends ConsumerWidget {
  const DatabaseTooNewScreen({super.key, required this.exception});

  final DatabaseTooNewException exception;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Scaffold(
      key: const ValueKey('database-too-new-screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.databaseTooNewTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  WpErrorNotice(
                    cause: l10n.databaseTooNewCause(
                      exception.storedVersion,
                      exception.supportedVersion,
                    ),
                    nextStep: l10n.databaseTooNewNextStep,
                  ),
                  const SizedBox(height: 24),
                  WpButton(
                    key: const ValueKey('database-too-new-quit'),
                    label: l10n.databaseTooNewQuit,
                    variant: WpButtonVariant.primary,
                    onPressed: () => _quit(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _quit(BuildContext context) async {
    await runGracefulEngineShutdown(ProviderScope.containerOf(context));
    await windowManager.destroy();
  }
}
