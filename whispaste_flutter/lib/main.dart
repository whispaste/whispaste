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
import 'screens/floating_overlay_screen.dart';
import 'services/audio_service.dart';
import 'services/multi_window_service.dart';
import 'services/single_instance_service.dart';

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
        if (type == WindowType.floatingOverlay) {
          return runFloatingOverlayWindow(controller);
        }
      }
    } catch (_) {
      // Not a secondary window — continue with main window setup.
    }
  }

  // ── Main window path ─────────────────────────────────────────────────────
  await AppMonitoring.bootstrap(appRunner: () async {
    // Single-instance guard: if another instance is running, signal it and exit.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final isPrimary = await SingleInstanceService.ensureSingleInstance();
      if (!isPrimary) {
        exit(0);
      }
    }

    // Desktop window setup
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1100, 750),
        minimumSize: Size(800, 550),
        center: true,
        title: 'WhisPaste',
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      // When a second instance launches, focus this window.
      SingleInstanceService.onSecondInstanceLaunched = () async {
        await windowManager.show();
        await windowManager.focus();
      };
    }

    // TODO: Initialize Go FFI bridge

    final container = await bootstrapAppContainer(
      observers: const [CrashProviderObserver()],
    );

    // Clean up stale WAV files from previous sessions (fire-and-forget).
    unawaited(AudioServiceNotifier.cleanupStaleFiles());

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const WhisPasteApp(),
      ),
    );
  });
}
