/// Eagerly initializes all required keepAlive services via [ref.watch].
///
/// Place near the widget tree root. It renders [child] unchanged — its only
/// purpose is to ensure Riverpod providers that manage system-level services
/// (tray, hotkeys, multi-window, autostart, STT) are alive for the app
/// lifetime.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart' show activePageProvider;
import '../core/logging/ui_thread_watchdog.dart';
import '../services/autostart_service.dart';
import '../services/hotkey_service.dart';
import '../services/multi_window_service.dart';
import '../services/recording_orchestrator.dart';
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

    // ── Global hotkey (Ctrl+Shift+D → toggle recording) ──
    ref.watch(hotkeyServiceProvider);
    ref.read(hotkeyServiceProvider.notifier).onHotkeyPressed = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };

    // ── Autostart sync ──
    ref.watch(autostartServiceProvider);

    // ── Multi-window service (desktop only) ──
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      ref.watch(multiWindowProvider);
    }

    return widget.child;
  }
}
