/// Advanced settings section.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/secure_key_store.dart'
    show SecureKeysNotRemovedException;
import '../../../core/config/settings_provider.dart';
import '../../../core/data/analytics_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/data/database.dart' show eraseHistoryForReset;
import '../../../core/data/history_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart' show activePageProvider;
import '../../../core/theme/tokens.dart';
import '../../../services/factory_reset/factory_reset_coordinator.dart';
import '../../../services/hardware_info_service.dart';
import '../../../services/linux_desktop_shortcut.dart';
import '../../../services/model_download_service.dart';
import '../../../services/path_service.dart' as paths;
import '../../../services/stt/stt_bundle.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../widgets/wp_settings_group.dart';

final _log = AppLogger('AdvancedSection');

// ---------------------------------------------------------------------------
// Advanced section
// ---------------------------------------------------------------------------

class AdvancedSection extends ConsumerWidget {
  const AdvancedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    return WpSettingsGroup(
      heading: l10n.settingsAdvanced,
      children: [
        WpSettingsRow(
          rowId: 'advanced-reset-defaults',
          title: l10n.settingsResetToDefaults,
          subtitle: l10n.settingsResetToDefaultsSubtitle,
          trailing: WpButton(
            label: l10n.settingsResetConfirm,
            variant: WpButtonVariant.secondary,
            onPressed: () => _confirmReset(context, ref),
          ),
        ),
        WpSettingsRow(
          rowId: 'advanced-factory-reset',
          title: l10n.settingsFactoryReset,
          subtitle: l10n.settingsFactoryResetSubtitle,
          trailing: WpButton(
            label: l10n.settingsFactoryResetConfirm,
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.danger,
            onPressed: () => _confirmFactoryReset(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsResetTitle,
      message: l10n.settingsResetMessage,
      confirmLabel: l10n.settingsResetConfirm,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(settingsProvider.notifier).resetToDefaults();
    } on SecureKeysNotRemovedException {
      // Settings were reset; the keys stayed behind. Never report success.
      if (!context.mounted) return;
      WpToast.show(
        context,
        message: L10n.of(context).settingsSecureKeysNotRemoved,
        type: WpToastType.error,
        duration: const Duration(seconds: 8),
      );
      return;
    }
    if (!context.mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).settingsResetSuccess,
      type: WpToastType.success,
    );
  }

  Future<void> _confirmFactoryReset(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsFactoryResetTitle,
      message: l10n.settingsFactoryResetMessage,
      confirmLabel: l10n.settingsFactoryResetConfirm,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    final overlayContext = Overlay.of(context, rootOverlay: true).context;
    final container = ProviderScope.containerOf(context);
    await _runFactoryReset(overlayContext, container);
  }

  /// Runs the reset under the progress dialog and reports the outcome.
  ///
  /// Takes the root overlay context and the app container instead of the
  /// section's own context and [WidgetRef]: the navigation after the reset can
  /// unmount this section, and a failed reset offers a retry from its toast.
  Future<void> _runFactoryReset(
    BuildContext context,
    ProviderContainer container,
  ) async {
    // Resetting the settings can switch the app language mid-reset; the
    // dialog and the outcome stay in the language the reset started in
    // (XP-6-11).
    final l10n = L10n.of(context);

    // Clear GPU detection cache — this is in-memory only, cheap, and
    // there is no reason to defer it into the coordinator.
    clearGpuCache();

    // Build a coordinator per reset attempt. The coordinator owns the
    // subprocess-stop ↔ delete-models ↔ erase-db ↔ erase-secure-store ↔
    // reset-settings sequence; the UI only orchestrates the modal
    // progress dialog and the post-reset navigation.
    final settingsNotifier = container.read(settingsProvider.notifier);
    final coordinator = FactoryResetCoordinator(
      subprocess: WhisperServerSubprocessController(
        pidFilePath: p.join(paths.appDataDir(), '.whisper-server.pid'),
        cooperativeStop: () async {
          try {
            container.read(localSttBundleProvider.notifier).stop();
          } catch (e) {
            _log.debug(
              'STT cooperative stop failed during factory reset (non-fatal): $e',
            );
          }
        },
      ),
      modelDirPath: paths.sttDir(),
      logsDirPath: defaultLogsDirPath(paths.appDataDir()),
      // A failure must reach the coordinator, which marks the phase failed.
      eraseDatabase: () async {
        try {
          await eraseHistoryForReset(container, paths.appDataDir());
        } catch (e) {
          _log.warning('DB erase failed during factory reset: $e');
          rethrow;
        }
      },
      eraseSecureStore: () => settingsNotifier.eraseSecureStore(),
      resetSettings: () async {
        try {
          await removeDesktopShortcutForReset(
            container.read(gnomeToggleShortcutProvider),
          );
        } finally {
          await settingsNotifier.factoryResetFinalize();
        }
      },
    );

    final result = await _runFactoryResetWithDialog(context, coordinator, l10n);
    if (!context.mounted) return;

    // Invalidate all data-backed providers so UI reflects the empty state.
    container.invalidate(historyEntriesProvider);
    container.invalidate(archivedEntriesProvider);
    container.invalidate(trashEntriesProvider);
    container.invalidate(analyticsProvider);
    container.invalidate(modelDownloadProvider);

    // Navigate back to history page so the onboarding overlay is visible.
    // Done regardless of outcome — even on partial failure, the in-memory
    // state has been reset to defaults (settingsResettingPhase persists
    // the in-memory AppSettings.defaults before any throw can land).
    container.read(activePageProvider.notifier).setPage('history');

    if (!context.mounted) return;
    if (result == ResetPhase.done) {
      WpToast.show(
        context,
        message: l10n.settingsFactoryResetSuccess,
        type: WpToastType.success,
      );
      return;
    }
    // Never a success message after a partial failure: name the areas that
    // still hold data and offer to run the reset again.
    WpToast.show(
      context,
      message: factoryResetFailureMessage(coordinator.failedPhases, l10n),
      type: WpToastType.error,
      duration: const Duration(seconds: 8),
      action: WpToastAction(
        label: l10n.factoryResetRetryAction,
        testId: 'settings-factory-reset-retry',
        onPressed: () => unawaited(_runFactoryReset(context, container)),
      ),
    );
  }

  /// Drives [coordinator.run] under a modal progress dialog and returns
  /// the terminal phase ([ResetPhase.done] on success, [ResetPhase.failed]
  /// on error). The dialog is dismissed automatically when the stream
  /// closes — the user cannot cancel the destructive operation mid-flight
  /// (intentional; an interrupted reset leaves a more confused state than
  /// a completed one).
  Future<ResetPhase> _runFactoryResetWithDialog(
    BuildContext context,
    FactoryResetCoordinator coordinator,
    L10n l10n,
  ) async {
    final stream = coordinator.run().asBroadcastStream();
    final terminalFuture = stream.firstWhere(
      (phase) => phase == ResetPhase.done || phase == ResetPhase.failed,
      orElse: () => ResetPhase.failed,
    );

    // Show the dialog as a non-awaited future so we can await the
    // coordinator stream in parallel. The dialog closes itself when it
    // sees the terminal phase via its internal StreamBuilder.
    unawaited(
      showWpDialog<void>(
        context: context,
        title: l10n.settingsFactoryResetProgressTitle,
        // A reset in flight must not be walked away from — no barrier tap,
        // no Esc. The dialog pops itself on the terminal phase.
        dismissible: false,
        useRootNavigator: true,
        content: _FactoryResetProgressContent(phaseStream: stream, l10n: l10n),
      ),
    );

    final terminal = await terminalFuture;

    // Ensure the dialog has had a frame to render the terminal phase
    // before we pop it from underneath. The dialog itself pops on the
    // terminal phase, but we double-check from here in case the
    // StreamBuilder lost the race.
    if (context.mounted) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }
    return terminal;
  }
}

/// Body of the modal progress dialog rendered during
/// [FactoryResetCoordinator.run]. Subscribes to the phase stream and
/// re-renders a labelled progress indicator on every emission. Pops itself
/// when the stream emits a terminal phase ([ResetPhase.done] or
/// [ResetPhase.failed]).
///
/// The card, the title and the "cannot be dismissed" behaviour come from
/// [showWpDialog] — this widget only owns the progress content.
class _FactoryResetProgressContent extends StatelessWidget {
  const _FactoryResetProgressContent({
    required this.phaseStream,
    required this.l10n,
  });

  final Stream<ResetPhase> phaseStream;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResetPhase>(
      stream: phaseStream,
      builder: (context, snapshot) {
        final phase = snapshot.data ?? ResetPhase.stoppingSubprocess;

        // Self-dismiss on terminal phase so callers do not have to
        // race a manual `Navigator.pop` against the StreamBuilder
        // rebuild. `addPostFrameCallback` is used because calling
        // Navigator.pop synchronously during a build is illegal.
        if (phase == ResetPhase.done || phase == ResetPhase.failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final nav = Navigator.of(context, rootNavigator: true);
            if (nav.canPop()) nav.pop();
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: WpSpacing.md),
            Text(
              _phaseLabel(l10n, phase),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        );
      },
    );
  }

  String _phaseLabel(L10n l10n, ResetPhase phase) {
    return switch (phase) {
      ResetPhase.stoppingSubprocess =>
        l10n.settingsFactoryResetPhaseStoppingSubprocess,
      ResetPhase.deletingModels => l10n.settingsFactoryResetPhaseDeletingModels,
      ResetPhase.deletingAudio => l10n.settingsFactoryResetPhaseDeletingAudio,
      ResetPhase.deletingDatabase =>
        l10n.settingsFactoryResetPhaseDeletingDatabase,
      ResetPhase.resettingSecureStore =>
        l10n.settingsFactoryResetPhaseResettingSecureStore,
      ResetPhase.resettingSettings =>
        l10n.settingsFactoryResetPhaseResettingSettings,
      // Terminal phases — the dialog is about to dismiss, but render the
      // last running phase's label until the post-frame pop fires so the
      // dialog does not flash blank.
      ResetPhase.done => l10n.settingsFactoryResetPhaseResettingSettings,
      ResetPhase.failed => l10n.settingsFactoryResetPhaseResettingSettings,
    };
  }
}

/// The fixed UI terms of the areas a failed reset phase left behind, joined
/// for the failure message. Duplicates are dropped; a failure with no data
/// area (the subprocess stop) names the background process.
String factoryResetFailedAreas(Iterable<ResetPhase> phases, L10n l10n) {
  final names = <String>[];
  for (final phase in phases) {
    final name = switch (phase) {
      ResetPhase.stoppingSubprocess => l10n.factoryResetAreaProcess,
      ResetPhase.deletingModels => l10n.factoryResetAreaModels,
      ResetPhase.deletingAudio => l10n.factoryResetAreaAudio,
      ResetPhase.deletingDatabase => l10n.factoryResetAreaDb,
      ResetPhase.resettingSecureStore => l10n.factoryResetAreaSecure,
      ResetPhase.resettingSettings => l10n.factoryResetAreaSettings,
      ResetPhase.done || ResetPhase.failed => null,
    };
    if (name != null && !names.contains(name)) names.add(name);
  }
  return names.join(', ');
}

/// The message after a partial reset. When the API keys stayed in the
/// keyring, it tells the user how to remove them by hand (XP-6-11).
String factoryResetFailureMessage(Iterable<ResetPhase> phases, L10n l10n) {
  final message = l10n.settingsFactoryResetFailedMessage(
    factoryResetFailedAreas(phases, l10n),
  );
  if (!phases.contains(ResetPhase.resettingSecureStore)) return message;
  return '$message ${l10n.factoryResetKeyringHint}';
}
