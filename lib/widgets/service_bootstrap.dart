/// Eagerly initializes all required keepAlive services via [ref.watch].
///
/// Place near the widget tree root. It renders [child] unchanged — its only
/// purpose is to ensure Riverpod providers that manage system-level services
/// (tray, hotkeys, autostart, STT) are alive for the app lifetime.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart' show activePageProvider, settingsScrollTargetProvider;
import '../core/config/settings_provider.dart';
import '../core/logging/ui_thread_watchdog.dart';
import '../services/autostart_service.dart';
import '../services/floating_button/floating_button_service.dart';
import '../services/floating_overlay/floating_overlay_service.dart';
import '../services/hotkey_service.dart';
import '../services/recording_orchestrator.dart';
import '../services/recording_trigger_handler.dart';
import '../services/tray_service.dart';

/// Invisible wrapper that eagerly boots keepAlive service providers.
class ServiceBootstrapWidget extends ConsumerStatefulWidget {
  const ServiceBootstrapWidget({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ServiceBootstrapWidget> createState() =>
      _ServiceBootstrapState();
}

class _ServiceBootstrapState extends ConsumerState<ServiceBootstrapWidget> {
  bool _orchestratorInitialized = false;

  /// The single [RecordingTriggerHandler] instance for this state's lifetime.
  ///
  /// Must NOT be recreated on every [build] — the handler holds keyDown/keyUp
  /// state (`_keyDownAt`, `_keyUpBreadcrumbSent`) and losing it between
  /// hotkey events breaks Push-to-Talk (see issue 06 of the
  /// `hotkey-modifier-storage-fix` PRD).
  late final RecordingTriggerHandler _triggerHandler;

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

    // ── Tray callbacks — stateless closures, safe to wire once ──
    final tray = ref.read(trayServiceProvider.notifier);
    tray.onToggleRecording = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };
    tray.onNavigate = (page) {
      ref.read(activePageProvider.notifier).setPage(page);
    };
    tray.onActionNeededTap = (key) {
      // Currently the only action-needed item is the paste-failure entry
      // — jump straight to the Auto-Paste settings so the user lands on
      // the capability indicator + "Grant permission" buttons.
      if (key == 'paste_action_needed') {
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

    return widget.child;
  }
}
