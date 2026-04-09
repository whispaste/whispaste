import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/settings_provider.dart';
import 'core/logging/app_monitoring.dart';
import 'screens/floating_button_screen.dart';
import 'services/audio_service.dart';
import 'services/hardware_info_service.dart' as hw;
import 'services/multi_window_service.dart';
import 'services/path_service.dart';
import 'services/single_instance_service.dart';
import 'services/subprocess_guard.dart' as guard;

Future<ProviderContainer> bootstrapAppContainer({
  List overrides = const [],
  List<ProviderObserver> observers = const [],
}) async {
  final container = ProviderContainer(
    overrides: [...overrides],
    observers: observers,
  );
  await container.read(settingsProvider.future);
  return container;
}

Future<void> main(List<String> args) async {
  // NOTE: WidgetsFlutterBinding.ensureInitialized() is called INSIDE the
  // bootstrap callback so that the binding and runApp() share the same zone.
  // Calling it here (root zone) while runApp() runs in the guarded zone
  // triggers a zone-mismatch assertion in debug mode.

  await AppMonitoring.bootstrap(appRunner: () async {
    WidgetsFlutterBinding.ensureInitialized();

    // Secondary window detection: desktop_multi_window passes the window type
    // via WindowController.fromCurrentEngine().arguments.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final controller = await WindowController.fromCurrentEngine();
        final windowArgs = controller.arguments;
        if (windowArgs.isNotEmpty) {
          final parsed = jsonDecode(windowArgs) as Map<String, dynamic>;
          final type = parsed['type'] as String?;
          if (type == WindowType.floatingButton) {
            return runFloatingButtonWindow(controller);
          }
          // Legacy: floating overlay windows are no longer used. If one
          // was left from a previous session, hide it and go inert.
          if (type == WindowType.floatingOverlay) {
            try {
              await controller.hide();
            } catch (_) {}
            return;
          }
        }
      } catch (_) {
        // Not a secondary window — continue with main window setup.
      }
    }

    // ── Main window path ───────────────────────────────────────────────────
    // Single-instance guard: if another instance is running, signal it and exit.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final isPrimary = await SingleInstanceService.ensureSingleInstance();
      if (!isPrimary) {
        exit(0);
      }
    }

    // Bootstrap the provider container early so we can read persisted window
    // geometry BEFORE creating the window — this avoids resize/move flicker.
    final container = await bootstrapAppContainer(
      observers: const [CrashProviderObserver()],
    );
    final settings =
        container.read(settingsProvider).value ?? AppSettings.defaults;

    // Desktop window setup — use persisted geometry when available.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();

      final hasPosition = settings.windowX >= 0 && settings.windowY >= 0;
      final windowOptions = WindowOptions(
        size: Size(settings.windowWidth, settings.windowHeight),
        minimumSize: const Size(800, 550),
        center: !hasPosition,
        title: 'WhisPaste',
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (hasPosition) {
          await windowManager.setPosition(
              Offset(settings.windowX, settings.windowY));
        }
        if (settings.windowMaximized) {
          await windowManager.maximize();
        }
        await windowManager.show();
        await windowManager.focus();
      });

      // When a second instance launches, focus this window.
      SingleInstanceService.onSecondInstanceLaunched = () async {
        await windowManager.show();
        await windowManager.focus();
      };
    }

    // Clean up stale WAV files from previous sessions (fire-and-forget).
    unawaited(AudioServiceNotifier.cleanupStaleFiles());

    // Kill orphaned whisper-server / llama-server from crashed sessions.
    unawaited(guard.cleanupOrphans());

    // Pre-cache GPU detection and validate the whisper-server binary matches
    // the current hardware. If the GPU changed since the binary was
    // downloaded (e.g., eGPU plugged in, driver update, hardware swap),
    // the incompatible binary is auto-deleted so the next download fetches
    // the correct variant.
    unawaited(hw.validateAndCleanIncompatibleBinary(sttDir()));

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const WhisPasteApp(),
      ),
    );
  });
}
