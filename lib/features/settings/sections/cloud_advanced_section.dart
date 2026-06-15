/// Advanced settings section.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_provider.dart';
import '../../../core/data/analytics_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/data/database.dart' show historyDatabaseProvider;
import '../../../core/data/history_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart' show activePageProvider;
import '../../../services/factory_reset/factory_reset_coordinator.dart';
import '../../../services/hardware_info_service.dart';
import '../../../services/model_download_service.dart';
import '../../../services/path_service.dart' as paths;
import '../../../services/stt/stt_bundle.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Test seam: the „App schließen" action on the factory-reset-failed toast
// calls [factoryResetExitFn]. Production wires it to `dart:io`'s `exit(…)`;
// widget tests overwrite it with a spy so they can assert the action
// fires without actually terminating the test isolate. Kept at the
// top-level (rather than passed through the widget tree) so the single
// `WpToastAction` callback stays trivial — the seam is documented at the
// only call site below.
typedef ExitFn = void Function(int code);
ExitFn factoryResetExitFn = io.exit;

final _log = AppLogger('AdvancedSection');

// ---------------------------------------------------------------------------
// Advanced section
// ---------------------------------------------------------------------------

class AdvancedSection extends ConsumerWidget {
  const AdvancedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsAdvanced,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _AutoPasteBlocklistField(settings: settings, ref: ref),
          SettingRow(
            icon: LucideIcons.shieldCheck,
            label: l10n.settingsErrorReporting,
            subtitle: l10n.settingsErrorReportingSubtitle,
            semanticToggledValue: settings.errorReporting,
            trailing: settingsToggle(
              value: settings.errorReporting,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(errorReporting: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.rotateCcw,
            label: l10n.settingsResetToDefaults,
            trailing: OutlinedButton(
              onPressed: () => _confirmReset(context, ref),
              child: Text(l10n.settingsResetConfirm),
            ),
          ),
          SettingRow(
            icon: LucideIcons.trash2,
            label: l10n.settingsFactoryReset,
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
              onPressed: () => _confirmFactoryReset(context, ref),
              child: Text(l10n.settingsFactoryResetConfirm),
            ),
          ),
        ],
      ),
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

    await ref.read(settingsProvider.notifier).resetToDefaults();
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

    // Clear GPU detection cache — this is in-memory only, cheap, and
    // there is no reason to defer it into the coordinator.
    clearGpuCache();

    // Build a coordinator per reset attempt. The coordinator owns the
    // subprocess-stop ↔ delete-models ↔ erase-db ↔ erase-secure-store ↔
    // reset-settings sequence; the UI only orchestrates the modal
    // progress dialog and the post-reset navigation.
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final coordinator = FactoryResetCoordinator(
      subprocess: WhisperServerSubprocessController(
        pidFilePath: p.join(paths.appDataDir(), '.whisper-server.pid'),
        cooperativeStop: () async {
          try {
            ref.read(localSttBundleProvider.notifier).stop();
          } catch (e) {
            _log.debug(
              'STT cooperative stop failed during factory reset (non-fatal): $e',
            );
          }
        },
      ),
      modelDirPath: paths.sttDir(),
      logsDirPath: defaultLogsDirPath(paths.appDataDir()),
      eraseDatabase: () async {
        try {
          await ref.read(historyDatabaseProvider).deleteAllData();
        } catch (e) {
          _log.warning(
            'DB erase failed during factory reset (partial wipe continues): $e',
          );
        }
      },
      eraseSecureStore: () => settingsNotifier.eraseSecureStore(),
      resetSettings: () => settingsNotifier.factoryResetFinalize(),
    );

    if (!context.mounted) return;
    final result = await _runFactoryResetWithDialog(context, coordinator);
    if (!context.mounted) return;

    // Invalidate all data-backed providers so UI reflects the empty state.
    ref.invalidate(historyEntriesProvider);
    ref.invalidate(archivedEntriesProvider);
    ref.invalidate(trashEntriesProvider);
    ref.invalidate(analyticsProvider);
    ref.invalidate(modelDownloadProvider);

    // Navigate back to history page so the onboarding overlay is visible.
    // Done regardless of outcome — even on partial failure, the in-memory
    // state has been reset to defaults (settingsResettingPhase persists
    // the in-memory AppSettings.defaults before any throw can land).
    ref.read(activePageProvider.notifier).setPage('history');

    if (!context.mounted) return;
    if (result == ResetPhase.done) {
      WpToast.show(
        context,
        message: L10n.of(context).settingsFactoryResetSuccess,
        type: WpToastType.success,
      );
    } else {
      final failL10n = L10n.of(context);
      WpToast.show(
        context,
        message: failL10n.factoryResetFailedToast,
        type: WpToastType.error,
        duration: const Duration(seconds: 8),
        // loam-ignore: a11y-interactive-semantics – semantics provided by TextButton in WpToast._ToastCard.build
        action: WpToastAction(
          label: failL10n.factoryResetFailedAction,
          // [factoryResetExitFn] is a test seam (see top of this file).
          // Production: `dart:io`'s `exit(0)` — the desktop platforms
          // collapse the OS process cleanly; the user can re-launch from
          // their dock / start menu, which is the recovery path the PRD
          // hands them.
          onPressed: () => factoryResetExitFn(0),
        ),
      );
    }
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
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) =>
            _FactoryResetProgressDialog(phaseStream: stream),
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

// ---------------------------------------------------------------------------
// Auto-paste blocklist field (moved here from AfterTranscriptionSection)
// ---------------------------------------------------------------------------

/// Text field for per-app auto-paste blocklist (comma-separated bundle IDs).
/// Rendered inside [AdvancedSection] so it is visually scoped as a niche option.
class _AutoPasteBlocklistField extends StatefulWidget {
  const _AutoPasteBlocklistField({required this.settings, required this.ref});

  final AppSettings settings;
  final WidgetRef ref;

  @override
  State<_AutoPasteBlocklistField> createState() =>
      _AutoPasteBlocklistFieldState();
}

class _AutoPasteBlocklistFieldState extends State<_AutoPasteBlocklistField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settings.autoPasteBlocklist,
    );
  }

  @override
  void didUpdateWidget(_AutoPasteBlocklistField old) {
    super.didUpdateWidget(old);
    if (old.settings.autoPasteBlocklist != widget.settings.autoPasteBlocklist) {
      _controller.text = widget.settings.autoPasteBlocklist;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      widget.ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(autoPasteBlocklist: value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingRow(
      icon: LucideIcons.shieldBan,
      label: l10n.settingsAutoPasteBlocklist,
      subtitle: l10n.settingsAutoPasteBlocklistSubtitle,
      trailing: settingsTextField(
        context: context,
        controller: _controller,
        hintText: l10n.settingsAutoPasteBlocklistPlaceholder,
        onChanged: _onChanged,
      ),
    );
  }
}

/// Modal progress dialog rendered during [FactoryResetCoordinator.run].
/// Subscribes to the phase stream and re-renders a labelled progress
/// indicator on every emission. Pops itself when the stream emits a
/// terminal phase ([ResetPhase.done] or [ResetPhase.failed]).
class _FactoryResetProgressDialog extends StatelessWidget {
  const _FactoryResetProgressDialog({required this.phaseStream});

  final Stream<ResetPhase> phaseStream;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.settingsFactoryResetProgressTitle),
        content: StreamBuilder<ResetPhase>(
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
                const SizedBox(height: 16),
                Text(_phaseLabel(l10n, phase)),
              ],
            );
          },
        ),
      ),
    );
  }

  String _phaseLabel(L10n l10n, ResetPhase phase) {
    return switch (phase) {
      ResetPhase.stoppingSubprocess =>
        l10n.settingsFactoryResetPhaseStoppingSubprocess,
      ResetPhase.deletingModels => l10n.settingsFactoryResetPhaseDeletingModels,
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
      ResetPhase.failed => l10n.settingsFactoryResetFailedMessage,
    };
  }
}
