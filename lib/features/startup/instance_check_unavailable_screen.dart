/// Start screen for a launch whose single-instance check could not run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/single_instance_service.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';
import 'startup_screen_frame.dart';

/// The step behind "Open anyway": tries the locks once more, then opens the
/// database gate. False means another WhisPaste turned up and was brought to
/// the front, so this launch quits. Overridable for tests.
final confirmUnverifiedStartProvider = Provider<Future<bool> Function()>(
  (ref) => SingleInstanceService.confirmUnverifiedStart,
);

/// Shown instead of the shell when no single-instance lock could be created
/// (missing rights, #1647). Another WhisPaste may already be open and write
/// to the same data, so the history database stays closed until the user
/// answers: quit, or open anyway. Only the user can see whether another
/// window or tray icon is there; blocking for good would lock them out over
/// a rights problem, opening silently could let two copies overwrite each
/// other.
class InstanceCheckUnavailableScreen extends ConsumerStatefulWidget {
  const InstanceCheckUnavailableScreen({super.key});

  @override
  ConsumerState<InstanceCheckUnavailableScreen> createState() =>
      _InstanceCheckUnavailableScreenState();
}

class _InstanceCheckUnavailableScreenState
    extends ConsumerState<InstanceCheckUnavailableScreen> {
  bool _busy = false;

  Future<void> _openAnyway() async {
    setState(() => _busy = true);
    final mayStart = await ref.read(confirmUnverifiedStartProvider)();
    if (!mounted) return;
    if (!mayStart) {
      await quitFromStartupScreen(context);
      return;
    }
    // The gate is open now: the start gate probes the database again and
    // the shell starts without a restart.
    ref.invalidate(historyDatabaseProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return StartupScreenFrame(
      key: const ValueKey('instance-check-unavailable-screen'),
      title: l10n.instanceCheckUnavailableTitle,
      children: [
        // Read out on arrival: focus goes to the quit button, so a screen
        // reader would otherwise announce only its label.
        Semantics(
          liveRegion: true,
          child: WpErrorNotice(
            cause: l10n.instanceCheckUnavailableCause,
            nextStep: l10n.instanceCheckUnavailableNextStep,
          ),
        ),
        const SizedBox(height: WpSpacing.xl),
        Wrap(
          spacing: WpSpacing.buttonGap,
          runSpacing: WpSpacing.sm,
          children: [
            // Quitting is the safe default and takes the focus: an Enter
            // pressed by habit never opens a second copy.
            WpButton(
              key: const ValueKey('instance-check-quit'),
              testId: 'instance-check-quit',
              label: l10n.databaseTooNewQuit,
              variant: WpButtonVariant.primary,
              autofocus: true,
              onPressed: _busy ? null : () => quitFromStartupScreen(context),
            ),
            WpButton(
              key: const ValueKey('instance-check-open'),
              testId: 'instance-check-open',
              label: l10n.instanceCheckUnavailableOpen,
              variant: WpButtonVariant.secondary,
              onPressed: _busy ? null : _openAnyway,
            ),
          ],
        ),
      ],
    );
  }
}
