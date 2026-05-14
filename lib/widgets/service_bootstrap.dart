/// Eagerly initializes all required keepAlive services via [ref.watch].
///
/// Place near the widget tree root. It renders [child] unchanged — its only
/// purpose is to ensure Riverpod providers that manage system-level services
/// (tray, hotkeys, autostart, STT) are alive for the app lifetime.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart' show activePageProvider;
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

  @override
  void initState() {
    super.initState();
    // Start UI thread jank detection.
    UiThreadWatchdog.instance.start();
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

    // ── System tray + callbacks ──
    ref.watch(trayServiceProvider);
    final tray = ref.read(trayServiceProvider.notifier);
    tray.onToggleRecording = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };
    tray.onNavigate = (page) {
      ref.read(activePageProvider.notifier).setPage(page);
    };

    // ── Global hotkey (toggle or Push-to-Talk depending on settings) ──
    ref.watch(hotkeyServiceProvider);
    final hotkeySvc = ref.read(hotkeyServiceProvider.notifier);
    final triggerHandler = RecordingTriggerHandler(
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
    hotkeySvc.onHotkeyPressed = triggerHandler.onKeyDown;
    hotkeySvc.onHotkeyReleased = triggerHandler.onKeyUp;

    // ── Autostart sync ──
    ref.watch(autostartServiceProvider);

    // ── Native floating button (desktop only) ──
    ref.watch(floatingButtonServiceProvider);

    // ── Native floating overlay (desktop only) ──
    ref.watch(floatingOverlayServiceProvider);

    return widget.child;
  }
}
