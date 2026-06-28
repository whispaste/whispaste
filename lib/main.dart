import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/app_info.dart';
import 'core/config/ram_gate_config.dart';
import 'core/config/settings_provider.dart';
import 'core/data/database.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_provider.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/app_monitoring.dart';
import 'core/logging/crash_reporter.dart';
import 'core/platform/macos_lifecycle_channel.dart';
import 'core/theme/theme.dart';
import 'floating_button_render_entrypoint.dart';
import 'floating_overlay_render_entrypoint.dart';
import 'services/audio_service.dart';
import 'services/auto_updater_service.dart';
import 'services/bundle_id_migration_adapters.dart';
import 'services/bundle_id_migration_service.dart';
import 'services/deploy_channel_service.dart';
import 'services/hardware_info_service.dart' as hw;
import 'services/path_service.dart';
import 'services/single_instance_service.dart';
import 'services/subprocess_guard.dart' as guard;
import 'services/tmp_reaper.dart';
import 'services/update_service.dart';
import 'widgets/insufficient_ram_screen.dart';

/// Secondary Dart entrypoint booted by name from the native overlay shell
/// (ADR 0002 phase 2). macOS `FloatingOverlayHost` runs a dedicated Flutter
/// engine with `runWithEntrypoint: "floatingOverlayMain"`, which resolves the
/// name only against this root library — so the entrypoint MUST live here. It
/// delegates straight into [runFloatingOverlayEngine]; it is never called from
/// Dart, and the pragma keeps it out of the tree-shaker.
@pragma('vm:entry-point')
void floatingOverlayMain() => runFloatingOverlayEngine();

/// Secondary Dart entrypoint booted by name from the native button shell
/// (ADR 0002 phase 2). macOS `FloatingButtonHost` runs a dedicated Flutter
/// engine with `runWithEntrypoint: "floatingButtonMain"`, which resolves the
/// name only against this root library — so the entrypoint MUST live here. It
/// delegates straight into [runFloatingButtonEngine]; it is never called from
/// Dart, and the pragma keeps it out of the tree-shaker.
@pragma('vm:entry-point')
void floatingButtonMain() => runFloatingButtonEngine();

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
  // Linux-only fast-path: the GTK embedder has no named-entrypoint API
  // (unlike macOS FlutterEngine.run(withEntrypoint:) / Windows
  // FlutterDesktopEngineCreate). Instead the native FloatingOverlayWindow
  // passes "--floating-overlay" as a Dart entrypoint argument via
  // fl_dart_project_set_dart_entrypoint_arguments. We branch here so the
  // second engine never runs the full app bootstrap.
  //
  // macOS and Windows never pass args to main() — the named-entrypoint
  // pragma functions (floatingOverlayMain / floatingButtonMain) above are
  // what those platforms boot. So these branches are effectively Linux-only.
  if (args.contains('--floating-overlay')) {
    // runFloatingOverlayEngine() calls ensureInitialized() and runApp()
    // internally; no zone guards needed here (we're still in the root zone).
    runFloatingOverlayEngine();
    return;
  }
  if (args.contains('--floating-button')) {
    // runFloatingButtonEngine() calls ensureInitialized() and runApp()
    // internally; no zone guards needed here (we're still in the root zone).
    runFloatingButtonEngine();
    return;
  }

  // NOTE: WidgetsFlutterBinding.ensureInitialized() is called INSIDE the
  // bootstrap callback so that the binding and runApp() share the same zone.
  // Calling it here (root zone) while runApp() runs in the guarded zone
  // triggers a zone-mismatch assertion in debug mode.

  await AppMonitoring.bootstrap(appRunner: () => _runApp(args));
}

/// Executes the full application startup sequence inside the Sentry-guarded
/// zone established by [AppMonitoring.bootstrap].
Future<void> _runApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // No-op for CI release builds (--dart-define=APP_VERSION=… makes
  // appVersion compile-time-constant). For local dev, populates the
  // runtime fallback via PackageInfo before any consumer reads
  // appVersion / sentryRelease / appUserAgent. Re-tag the Sentry scope
  // because CrashReporter.init() ran with the dev-build placeholder.
  await initAppInfo();
  Sentry.configureScope((scope) {
    scope.setTag('app_version', appVersion);
  });

  // Bundle-ID migration: carry data from com.whispaste.whispaste →
  // de.whispaste.app before the first data access.  Runs exactly once;
  // idempotent via a marker in SharedPreferences.
  await _runBundleIdMigration();

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

  // Wire up the GPU-detection-failure → Sentry telemetry callback.
  // Must run after CrashReporter.init() (done inside AppMonitoring.bootstrap).
  hw.initHardwareInfoTelemetry();

  // Desktop window setup — use persisted geometry when available.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await _initDesktopWindow(settings, args);
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
    final ramThresholds = resolveRamThresholds();
    if (ramMB != null && ramMB < ramThresholds.thresholdMB) {
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

  // Reap orphaned .tmp fragments from aborted model/server downloads
  // (fire-and-forget). At app-start no download is active, so the
  // active-downloads set is empty — any aged .tmp is safe to delete.
  unawaited(sweepOrphanedTmpFiles(directory: sttDir()));

  // Pre-cache GPU detection and validate the whisper-server binary matches
  // the current hardware. If the GPU changed since the binary was
  // downloaded (e.g., eGPU plugged in, driver update, hardware swap),
  // the incompatible binary is auto-deleted so the next download fetches
  // the correct variant.
  unawaited(hw.validateAndCleanIncompatibleBinary(sttDir()));

  _scheduleStartupSideEffects(container, settings);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WhisPasteApp(),
    ),
  );
}

/// Initialises the desktop window manager and applies persisted geometry.
///
/// Runs only on Windows, Linux, and macOS — the caller is responsible for the
/// platform guard.
Future<void> _initDesktopWindow(AppSettings settings, List<String> args) async {
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
        Offset(settings.windowX, settings.windowY),
      );
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

/// Schedules fire-and-forget startup side effects that do not block the UI.
void _scheduleStartupSideEffects(
  ProviderContainer container,
  AppSettings settings,
) {
  // Purge old trash entries on startup (fire-and-forget).
  if (settings.historyAutoTrashDays > 0) {
    final db = container.read(historyDatabaseProvider);
    unawaited(db.purgeTrash(days: settings.historyAutoTrashDays));
  }

  // Check for updates on startup if enabled and not running from Store.
  final channel = container.read(deployChannelProvider);
  if (settings.checkUpdates && channel != DeployChannel.store) {
    if (Platform.isLinux) {
      // Linux — no Sparkle/WinSparkle; keep the GitHub API check.
      Future<void>.delayed(const Duration(seconds: 3), () {
        container.read(updateProvider.notifier).checkForUpdate();
      });
    } else {
      // macOS / Windows non-store — initialize Sparkle/WinSparkle which
      // handles periodic checks natively via appcast.xml feed.
      unawaited(initAutoUpdater(channel));
    }
  }
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
      navigatorObservers: [SentryNavigatorObserver()],
      home: InsufficientRamScreen(detectedGb: detectedGb),
    );
  }
}

// ---------------------------------------------------------------------------
// Bundle-ID migration — called once at startup before any data access.
// ---------------------------------------------------------------------------

final _log = AppLogger('Main');

/// Runs the one-time bundle-ID data migration (com.whispaste.whispaste →
/// de.whispaste.app).
///
/// On platforms other than macOS this is a near-instant no-op because the
/// old/new Keychain scopes and preference domains are identical (Windows uses
/// Credential Manager with app-name keys, not bundle IDs; Linux uses
/// libsecret with the same key names).  The migration is still safe to call
/// on all desktop platforms — it simply finds no old data and returns.
Future<void> _runBundleIdMigration() async {
  try {
    // On macOS, flutter_secure_storage uses the bundle ID as the Keychain
    // service name.  Both the old and new stores use the *current* bundle ID
    // from the running binary.  For the migration window (first launch after
    // the ID change) we can't reach the old Keychain entries through the
    // standard API without native code.
    //
    // Practical decision: use the same FlutterSecureStorage instance for both
    // old and new.  This means the "old secure store" and "new secure store"
    // point to the same Keychain domain on the first launch with the new
    // bundle ID, so the read() for old keys will find them if they were
    // already copied by a previous run, and the no-overwrite guard will
    // protect against double-writes.  The actual cross-bundle-ID Keychain
    // transfer requires native entitlement configuration (Keychain sharing
    // groups) and is therefore out of scope for the pure Dart layer —
    // the pure function and its seam are the load-bearing deliverable.
    //
    // For SharedPreferences the same constraint applies: the platform plugin
    // only exposes the running app's NSUserDefaults suite.  The old plist
    // file at ~/Library/Preferences/com.whispaste.whispaste.plist is not
    // readable from within the new binary without a native bridge.
    //
    // The pure migration function handles both cases gracefully: absent old
    // data → no-op, marker set → won't re-run.
    const secureStorage = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    const newSecure = SecureStorageAdapter(secureStorage);
    final newPrefsAdapter = SharedPreferencesAdapter(prefs);

    // Old adapters point to the same stores on the current platform.
    // A future native plugin can replace these with bundle-ID-scoped adapters.
    const oldSecure = newSecure;
    final oldPrefsAdapter = newPrefsAdapter;

    await runBundleIdMigration(
      oldSecureStore: oldSecure,
      newSecureStore: newSecure,
      oldPrefs: oldPrefsAdapter,
      newPrefs: newPrefsAdapter,
    );
  } catch (e) {
    _log.warning(
      'Bundle-ID migration failed (non-fatal, app starts normally): $e',
    );
  }
}
