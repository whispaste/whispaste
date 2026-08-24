/// Eagerly initializes all required keepAlive services via [ref.watch].
///
/// Place near the widget tree root. It renders [child] unchanged — its only
/// purpose is to ensure Riverpod providers that manage system-level services
/// (tray, hotkeys, autostart, STT) are alive for the app lifetime.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation/page_state.dart'
    show activePageProvider, settingsScrollTargetProvider;
import '../core/config/settings_provider.dart';
import '../core/logging/ui_thread_watchdog.dart';
import '../core/recording/recording_state.dart' show RecordingTarget;
import '../services/autostart_service.dart';
import '../services/clipboard_history/clipboard_history_monitor_service.dart';
import '../services/floating_button/floating_button_service.dart';
import '../services/floating_overlay/floating_overlay_service.dart';
import '../services/hotkey_service.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/recording_orchestrator.dart';
import '../services/recording_trigger_handler.dart';
import '../services/side_panel/side_panel_service.dart';
import '../services/tray_service.dart';

/// Invisible wrapper that eagerly boots keepAlive service providers.
class WpServiceBootstrap extends ConsumerStatefulWidget {
  const WpServiceBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpServiceBootstrap> createState() => _WpServiceBootstrapState();
}

class _WpServiceBootstrapState extends ConsumerState<WpServiceBootstrap> {
  bool _orchestratorInitialized = false;

  /// The single [RecordingTriggerHandler] instance for this state's lifetime.
  ///
  /// Must NOT be recreated on every [build] — the handler holds keyDown/keyUp
  /// state (`_keyDownAt`, `_keyUpBreadcrumbSent`) and losing it between
  /// hotkey events breaks Push-to-Talk (see issue 06 of the
  /// `hotkey-modifier-storage-fix` PRD).
  late final RecordingTriggerHandler _triggerHandler;

  /// Trigger handler for the quick-note hotkey (ticket 20). Same class, same
  /// held-for-lifetime rule as [_triggerHandler] — a second instance rather
  /// than a shared one, since each hotkey needs its own PTT/toggle mode
  /// (this action is always toggle-only) and its own recording target.
  late final RecordingTriggerHandler _quickNoteTriggerHandler;

  @override
  void initState() {
    super.initState();
    // Start UI thread jank detection.
    UiThreadWatchdog.instance.start();

    // ── Trigger handler — created once and kept for the state's lifetime ──
    // Reads (`ref.read`) stay closure-bound to the live `ref`, so settings
    // and orchestrator look-ups always see the current values, not a snapshot.
    final hotkeySvc = ref.read(hotkeyServiceProvider.notifier);
    _triggerHandler = RecordingTriggerHandler(
      startRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).startRecording(),
      stopRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
      toggleRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording(),
      pushToTalkEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults).pushToTalk,
      registrarSupportsKeyUp: () => hotkeySvc.supportsKeyUp,
    );
    hotkeySvc.onHotkeyPressed = _triggerHandler.onKeyDown;
    hotkeySvc.onHotkeyReleased = _triggerHandler.onKeyUp;

    // ── Quick-note trigger handler (ticket 20) — toggle-only, no PTT ──
    _quickNoteTriggerHandler = RecordingTriggerHandler(
      startRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .startRecording(target: RecordingTarget.quickNote),
      stopRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
      toggleRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording(target: RecordingTarget.quickNote),
      // Hardcoded false: the quick-note hotkey never wires a keyUpHandler
      // (see HotkeyService.updateQuickNoteHotkey), so onKeyUp never fires
      // for it anyway — this just documents the invariant at the call site.
      pushToTalkEnabled: () => false,
      registrarSupportsKeyUp: () => hotkeySvc.supportsKeyUp,
    );
    hotkeySvc.onQuickNoteHotkeyPressed = _quickNoteTriggerHandler.onKeyDown;

    // ── Snippet-Picker hotkey (ticket 26) — one-shot, no recording, so no
    // RecordingTriggerHandler needed: just a direct closure into the
    // orchestrator's dedicated method. ──
    hotkeySvc.onSnippetPickerHotkeyPressed = () => ref
        .read(recordingOrchestratorProvider.notifier)
        .openSnippetPickerViaHotkey();

    // ── Tray callbacks — stateless closures, safe to wire once ──
    final tray = ref.read(trayServiceProvider.notifier);
    tray.onToggleRecording = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };
    tray.onNavigate = (page) {
      ref.read(activePageProvider.notifier).setPage(page);
    };
    tray.onActionNeededTap = (key) {
      // A blocked Auto-Paste permission is handled where it broke, not in
      // settings: run the same recovery the failed-paste notification and
      // the in-app toast offer. Sending the user to a settings page to find
      // the fix themselves is what made this flow feel unguided, and the
      // tray is the surface that outlives the other two — a notification
      // expires, so this entry is often the only one still there when the
      // user gets around to acting.
      if (key == kTrayPastePermissionActionNeededKey) {
        unawaited(
          ref
              .read(pasteCapabilityNotifierProvider.notifier)
              .runMissingPermissionRecovery(),
        );
        return;
      }
      // Every other action-needed item is a paste failure the user resolves
      // by changing a setting (no target app, elevation, unknown), so those
      // still jump to the Auto-Paste settings and its capability indicator.
      if (key == kTrayPasteActionNeededKey) {
        ref
            .read(settingsScrollTargetProvider.notifier)
            .set('afterTranscription');
        ref.read(activePageProvider.notifier).setPage('settings');
      }
    };
  }

  @override
  void dispose() {
    UiThreadWatchdog.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Recording orchestrator ──
    // Defer first init until after the first frame so the window paints fast.
    if (!_orchestratorInitialized) {
      _orchestratorInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(recordingOrchestratorProvider);
      });
    } else {
      ref.watch(recordingOrchestratorProvider);
    }

    // ── Keep the keepAlive service providers alive for the app lifetime ──
    ref.watch(trayServiceProvider);
    ref.watch(hotkeyServiceProvider);
    ref.watch(autostartServiceProvider);
    ref.watch(floatingButtonServiceProvider);
    ref.watch(floatingOverlayServiceProvider);
    // Without this watch, nothing in production ever reads
    // sidePanelServiceProvider, so it gets disposed immediately after each
    // native hover-trigger call -- tearing down its onControllerReady
    // ref.listen subscriptions and losing the row-content maps between
    // open() and the next row click.
    //
    // Gated on the setting on purpose, not just watched unconditionally: a
    // user who turns the panel off wants its native edge sensors gone, not
    // merely unreachable. Dropping the watch lets the (autoDispose) provider
    // tear down through the same disposeController -> controller.dispose()
    // path a hover-triggered auto-dispose already exercises; flipping the
    // setting back on re-runs build() and recreates the native host.
    final sidePanelEnabled = ref.watch(
      settingsProvider.select(
        (s) => s.value?.interface_.sidePanelEnabled ?? true,
      ),
    );
    if (sidePanelEnabled) {
      ref.watch(sidePanelServiceProvider);
    }
    // Registers the clipEntryDetected method-call handler for the native
    // clipboard monitors (issues 04-06); same keepAlive rationale as above.
    ref.watch(clipboardHistoryMonitorServiceProvider);

    return widget.child;
  }
}
