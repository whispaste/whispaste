import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/settings_provider.dart';
import 'core/data/database.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_provider.dart';
import 'core/logging/app_monitoring.dart';
import 'core/logging/crash_reporter.dart';
import 'core/platform/macos_lifecycle_channel.dart';
import 'core/theme/theme.dart';
import 'services/audio_service.dart';
import 'services/deploy_channel_service.dart';
import 'services/hardware_info_service.dart' as hw;
import 'services/path_service.dart';
import 'services/single_instance_service.dart';
import 'services/subprocess_guard.dart' as guard;
import 'services/update_service.dart';
import 'widgets/insufficient_ram_screen.dart';

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

    // Sync crash reporting consent BEFORE any other work that could throw.
    // Closes the GDPR window where bootstrap errors could reach Sentry
    // without user consent (default is true until this runs).
    CrashReporter.instance?.consentGranted = settings.errorReporting;

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

        // Start minimized only when launched via autostart (system boot),
        // not when the user explicitly opens the app from Dock/Taskbar.
        final isAutostart = args.contains('--autostart');
        final shouldMinimize =
            isAutostart && settings.startMinimized && settings.launchAtStartup;

        if (!shouldMinimize) {
          await windowManager.show();
          await windowManager.focus();
        } else {
          // Hide to tray — only if tray is expected to work.
          if (Platform.isMacOS) {
            await MacOSLifecycleChannel.setAccessory();
          }
        }
      });

      // When a second instance launches, focus this window.
      SingleInstanceService.onSecondInstanceLaunched = () async {
        await MacOSLifecycleChannel.setRegular();
        await windowManager.show();
        await windowManager.focus();
      };
    }

    // Clean up stale WAV files from previous sessions (fire-and-forget).
    unawaited(AudioServiceNotifier.cleanupStaleFiles());

    // RAM preflight — fail fast if system is below the 8 GB minimum.
    // Only runs on desktop (mobile/web have different resource models).
    // Fail-open: if detection returns null, proceed normally.
    // kRamCheckThresholdMB (7500) accounts for OS memory reservations on
    // Windows/Linux; kMinRamMB (8192) is the user-facing requirement shown
    // in the error UI.
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final ramMB = await hw.detectRamMB();
      if (ramMB != null && ramMB < hw.kRamCheckThresholdMB) {
        final detectedGb = ramMB / 1024.0;
        runApp(
          UncontrolledProviderScope(
            container: container,
            child: _InsufficientRamApp(detectedGb: detectedGb),
          ),
        );
        return;
      }
    }

    // Kill orphaned whisper-server / llama-server from crashed sessions.
    unawaited(guard.cleanupOrphans());

    // Pre-cache GPU detection and validate the whisper-server binary matches
    // the current hardware. If the GPU changed since the binary was
    // downloaded (e.g., eGPU plugged in, driver update, hardware swap),
    // the incompatible binary is auto-deleted so the next download fetches
    // the correct variant.
    unawaited(hw.validateAndCleanIncompatibleBinary(sttDir()));

    // Purge old trash entries on startup (fire-and-forget).
    if (settings.historyAutoTrashDays > 0) {
      final db = container.read(historyDatabaseProvider);
      unawaited(db.purgeTrash(days: settings.historyAutoTrashDays));
    }

    // Check for updates on startup if enabled and not running from Store.
    final channel = container.read(deployChannelProvider);
    if (settings.checkUpdates && channel != DeployChannel.store) {
      // Short delay so the UI renders first.
      Future<void>.delayed(const Duration(seconds: 3), () {
        container.read(updateProvider.notifier).checkForUpdate();
      });
    }

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const WhisPasteApp(),
      ),
    );
  });
}

/// Minimal app shown when RAM is below the 8 GB minimum.
///
/// Always uses the dark theme — the screen uses [WpColorsDark] tokens.
/// Locale is respected so EN/DE strings load correctly.
class _InsufficientRamApp extends ConsumerWidget {
  const _InsufficientRamApp({required this.detectedGb});

  final double detectedGb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'WhisPaste',
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: InsufficientRamScreen(detectedGb: detectedGb),
    );
  }
}
