import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hotkey_manager/hotkey_manager.dart' show hotKeyManager;
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/app_info.dart';
import 'core/config/ram_gate_config.dart';
import 'core/config/settings_provider.dart';
import 'core/data/history_vacuum.dart';
import 'core/navigation/last_page.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/app_monitoring.dart';
import 'core/logging/crash_reporter.dart';
import 'core/logging/perf_instrumentation.dart';
import 'core/platform/desktop_window_geometry.dart';
import 'core/platform/display_bounds.dart';
import 'core/platform/macos_lifecycle_channel.dart';
import 'core/platform/window_position_clamp.dart';
import 'core/recording/recording_state.dart'
    show isDictationBusy, recordingPhaseProvider, recordingProvider;
import 'core/theme/tokens.dart';
import 'core/tls/mozilla_roots_loader.dart';
import 'floating_button_render_entrypoint.dart';
import 'floating_overlay_render_entrypoint.dart';
import 'side_panel_render_entrypoint.dart';
import 'snippet_picker_render_entrypoint.dart';
import 'services/audio/retention/retention_schedule.dart';
import 'services/audio_service.dart';
import 'services/speech_recommendation.dart' show ramMBProvider;
import 'services/audio/recovery/recording_journal_provider.dart';
import 'services/audio/recovery/recording_recovery.dart';
import 'services/audio/user_audio_dirs.dart';
import 'services/pending_audio/pending_audio_providers.dart';
import 'services/auto_updater_service.dart';
import 'services/automation_api/automation_api_controller.dart';
import 'services/automation_api/automation_api_router.dart'
    show AutomationDictationBusyException, DictationTriggerResult;
import 'services/bundle_id_migration_adapters.dart';
import 'services/bundle_id_migration_service.dart';
import 'services/deploy_channel_service.dart';
import 'services/graceful_shutdown.dart';
import 'services/quit_deadline.dart';
import 'services/hardware_info_service.dart' as hw;
import 'services/headless/headless_cli.dart';
import 'services/headless/headless_transcription.dart'
    show HeadlessTranscriptionOptions;
import 'services/headless/package_diagnose.dart'
    show PackageDiagnoseOptions, runPackageDiagnoseCli;
import 'services/legacy_residue_cleanup.dart';
import 'services/path_service.dart';
import 'services/recording_orchestrator.dart';
import 'services/single_instance_service.dart';
import 'services/smart_mode/smart_mode_presets.dart'
    show smartModePresetFromSettingsValue;
import 'services/sound_feedback_service.dart';
import 'services/stt/whisper/gpu_load_crash_guard.dart';
import 'services/stt/whisper/gpu_probe.dart'
    show kGpuProbeChildEnv, kGpuProbeStartedLine;
import 'services/stt_parakeet/parakeet_language_support.dart';
import 'services/stt_parakeet/parakeet_model_registry.dart';
import 'services/model_hardware_telemetry.dart';
import 'services/telemetry_service.dart';
import 'services/tmp_reaper.dart';
import 'services/update_channel_service.dart';
import 'services/update_service.dart';

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

/// Secondary Dart entrypoint booted by name from the native Snippet-Picker
/// shell (dictation-automations ticket 06). macOS `SnippetPickerHost` runs a
/// dedicated Flutter engine with `runWithEntrypoint: "snippetPickerMain"`,
/// which resolves the name only against this root library — so the
/// entrypoint MUST live here. It delegates straight into
/// [runSnippetPickerEngine]; it is never called from Dart, and the pragma
/// keeps it out of the tree-shaker.
@pragma('vm:entry-point')
void snippetPickerMain() => runSnippetPickerEngine();

/// Secondary Dart entrypoint booted by name from the native side-panel
/// shell (clipboard quick-paste side panel). macOS/Windows run a dedicated
/// Flutter engine with `runWithEntrypoint: "sidePanelMain"`, which resolves
/// the name only against this root library -- so the entrypoint MUST live
/// here. It delegates straight into [runSidePanelEngine]; it is never
/// called from Dart, and the pragma keeps it out of the tree-shaker.
@pragma('vm:entry-point')
void sidePanelMain() {
  unawaited(runSidePanelEngine());
}

Future<ProviderContainer> bootstrapAppContainer({
  List overrides = const [],
  List<ProviderObserver> observers = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      // Local automation API (ticket 03) dictation trigger, wired to the
      // same use case the main hotkey calls. Deliberately supplied here
      // (main.dart is never imported by anything else) rather than as a
      // default inside automation_api_controller.dart, which would
      // otherwise have to import recording_orchestrator.dart directly and
      // close an import cycle back through graceful_shutdown.dart -> that
      // file -> macos_lifecycle_channel.dart. Listed first so a caller's
      // own override (e.g. in tests, though none currently reuse this
      // function) can still take precedence by appearing later.
      automationApiControllerProvider.overrideWith(
        () => AutomationApiController(
          triggerDictation:
              (
                ref, {
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async {
                // toggleRecording() is a start/stop toggle — read the phase
                // *before* calling it to know which branch it took, since the
                // call itself doesn't report that back.
                final wasRecording = ref.read(recordingProvider).isRecording;
                // Toggling while a transcription runs is a no-op, so answer
                // busy rather than claim a recording started.
                if (!wasRecording &&
                    isDictationBusy(ref.read(recordingPhaseProvider))) {
                  throw const AutomationDictationBusyException();
                }
                await ref
                    .read(recordingOrchestratorProvider.notifier)
                    .toggleRecording(
                      languageOverride: language,
                      forcedSmartModePreset: smartModePreset == null
                          ? null
                          : smartModePresetFromSettingsValue(smartModePreset),
                      silenceTimeoutOverride: silenceTimeout,
                    );
                if (wasRecording) {
                  // Stopped a recording — toggleRecording() already awaited the
                  // full transcription pipeline, so the finished transcript (if
                  // any) is sitting in recordingProvider now.
                  return DictationTriggerResult(
                    recording: false,
                    transcript: ref.read(recordingProvider).transcript,
                  );
                }
                return DictationTriggerResult(
                  recording: true,
                  unsupportedLanguage: parakeetUnsupportedLanguage(
                    ref.read(settingsProvider).value ?? AppSettings.defaults,
                    languageOverride: language,
                  ),
                );
              },
        ),
      ),
      ...overrides,
    ],
    observers: observers,
  );
  await container.read(settingsProvider.future);
  container.read(historyVacuumSchedulerProvider);
  return container;
}

Future<void> main(List<String> args) async {
  // kDebugMode-gated: compiled out of profile/release entirely (kDebugMode is
  // a compile-time constant, always false there), so this never reaches the
  // Mac App Store or Microsoft Store build. Must run before ANY binding gets
  // created — enableFlutterDriverExtension() creates the WidgetsBinding
  // singleton itself (as a _DriverBinding that also overrides debugCheckZone
  // to accept whatever zone runApp() ends up in). sentry_flutter's
  // WidgetsFlutterBindingIntegration creates its own SentryWidgetsFlutterBinding
  // the moment SentryFlutter.init() runs inside AppMonitoring.bootstrap below
  // — calling this any later collides with that (binding-already-initialized
  // assert). Whichever binding claims the singleton first wins; Sentry's own
  // ensureInitialized() finds the existing one and reuses it rather than
  // erroring, so ordering it first here is what makes both coexist. Trade-off:
  // Sentry's frame-timing tracking (SentryWidgetsBindingMixin) is then not
  // mixed in, so slow-frame reporting is inactive while this is on — debug
  // builds only, so that's not a production monitoring gap. Lets the
  // Dart/Flutter MCP server's flutter_driver_command tool
  // (screenshot/tap/diagnostics tree) drive the real running app — see
  // docs/agents/ui-investigation.md.
  // enableTextEntryEmulation defaults to true, which intercepts the
  // TextInput platform channel app-wide and swallows all real keyboard
  // input (focus/caret stay visually active but no character ever lands,
  // AppKit falls through to its own beep) — every debug build was
  // unusable for actual typing until this was set to false. The MCP
  // tool's enter_text command can still be enabled ad hoc per-session via
  // the set_text_entry_emulation driver command when a test actually
  // needs synthetic text entry.
  if (kDebugMode) {
    enableFlutterDriverExtension(enableTextEntryEmulation: false);
  }

  // Linux-only fast-path: the GTK embedder has no named-entrypoint API
  // (unlike macOS FlutterEngine.run(withEntrypoint:) / Windows
  // FlutterDesktopEngineCreate). Instead the native FloatingOverlayWindow
  // passes "--floating-overlay" as a Dart entrypoint argument via
  // fl_dart_project_set_dart_entrypoint_arguments. We branch here so the
  // second engine never runs the full app bootstrap.
  //
  // macOS never passes args to main() — the named-entrypoint pragma
  // functions (floatingOverlayMain / floatingButtonMain) above are what
  // that platform boots for the secondary engines instead. Windows DOES
  // forward the real process argv to main() (see
  // windows/runner/main.cpp:22-25, GetCommandLineArguments() feeding
  // set_dart_entrypoint_arguments()) — it just never passes these two
  // floating-overlay/-button flags, so these branches are effectively
  // Linux-only in practice.
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
  if (args.contains('--snippet-picker')) {
    // Same Linux args-branch fast-path as above, for the Snippet-Picker's
    // second engine (visual-refresh-2026 ticket 30) — macOS/Windows instead
    // boot it by name via the snippetPickerMain() pragma function above.
    runSnippetPickerEngine();
    return;
  }
  if (args.contains('--side-panel')) {
    // Same Linux args-branch fast-path as above, for the side panel's
    // second engine — macOS/Windows instead boot it by name via the
    // sidePanelMain() pragma function above.
    await runSidePanelEngine();
    return;
  }

  // Tells the GPU probe parent (gpu_probe.dart) that the child reached the
  // app: a child without this line never got to the GPU code.
  if (Platform.environment[kGpuProbeChildEnv] == '1') {
    stdout.writeln(kGpuProbeStartedLine);
  }
  // `whispaste --transcribe-file <wav> …`: headless transcription/latency
  // benchmark (lib/services/headless/). Runs before crash reporting, the
  // single-instance guard and any window/UI setup, then exits.
  if (HeadlessTranscriptionOptions.isRequested(args)) {
    exit(await runHeadlessCli(args));
  }
  // `whispaste --download-cuda-pack --accept-nvidia-eula`: CUDA pack download
  // without the window; refuses unless the NVIDIA EULA flag is given.
  if (isCudaPackDownloadRequested(args)) {
    exit(await runCudaPackDownloadCli(args));
  }
  // `whispaste --diagnose`: start probe for the release package smoke tests
  // (scripts/smoke/) — same early exit, no UI, settings or permissions.
  if (PackageDiagnoseOptions.isRequested(args)) {
    exit(await runPackageDiagnoseCli(args));
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
  // Temp WAVs modified before this instant are leftovers of an earlier run.
  final launchedAt = DateTime.now();
  // Cold-start t₀: stamp before ensureInitialized so we capture the full
  // Flutter bootstrap time. Log is emitted in the first-frame callback below.
  // HUMAN GATE (issue 16): read '[PERF] cold-start → first-frame: Xms' log
  // in the console during dogfooding. Budget: PerfBudgets.coldStartFirstFrameMs
  // (currently TBD — PRD §8 open mini-point).
  PerfMarkers.instance.markColdStartBegin();

  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();

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
  // The signal carries `--toggle`/`--cancel`, so `whispaste --toggle` from a
  // shortcut or script drives the running instance's recording.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final command = InstanceCommand.fromArgs(args);
    final isPrimary = await SingleInstanceService.ensureSingleInstance(
      command: command,
    );
    if (!isPrimary) {
      exit(0);
    }
    // No running instance means no dictation to cancel — a cancel shortcut
    // must not launch the app as a side effect. (`--toggle` instead starts
    // the app and then a dictation, queued inside ensureSingleInstance.)
    if (command == InstanceCommand.cancel) {
      exit(0);
    }
  }

  // Windows: trust the bundled Mozilla roots for every download (lib/core/tls/).
  await installBundledMozillaRoots();

  // Bootstrap the provider container early so we can read persisted window
  // geometry BEFORE creating the window — this avoids resize/move flicker.
  final container = await bootstrapAppContainer(
    observers: const [CrashProviderObserver()],
  );
  await restoreLastPage(container);
  final settings =
      container.read(settingsProvider).value ?? AppSettings.defaults;

  // Native Cmd+Q / Dock "Quit" bypasses the Dart-level window-close handler
  // entirely — wire up the graceful-shutdown bridge so it doesn't also
  // bypass the STT-engine-stop-before-exit fix (see graceful_shutdown.dart).
  if (Platform.isMacOS) {
    MacOSLifecycleChannel.registerTerminationHandler(container);
  }

  // Sync crash reporting consent BEFORE any other work that could throw.
  // A launch that already knew about an opt-out never started Sentry (see
  // AppMonitoring.startMonitoring); this sync covers the first launch after
  // an opt-out stored only in the settings, and closes Sentry right here.
  CrashReporter.instance?.consentGranted = settings.errorReporting;

  // Crash-loop breaker: if the previous session died mid GPU model-load (a
  // native crash with no catchable Dart exception, see
  // gpu_load_crash_guard.dart), permanently force CPU-only STT before
  // whisperEngineProvider's first build — otherwise the same crash repeats
  // on every relaunch and the user never gets far enough into the UI to
  // disable GPU acceleration themselves. Must complete before runApp() for
  // the same settingsProvider-cache-race reason the GPU probe below is
  // awaited before runApp().
  await recoverFromGpuLoadCrash(container);

  // Wire up the GPU-detection-failure → Sentry telemetry callback.
  // Must run after CrashReporter.init() (done inside AppMonitoring.bootstrap).
  hw.initHardwareInfoTelemetry();

  // Desktop window setup — use persisted geometry when available.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await _initDesktopWindow(settings, args);
  }

  // Clean up stale WAV files from previous sessions (fire-and-forget), now
  // and once more after the age guard has passed.
  AudioServiceNotifier.scheduleStaleFileCleanup(
    launchedAt: launchedAt,
    journal: container.read(recordingJournalProvider),
  );

  // Tighten the folders that hold user audio to 0700 (fire-and-forget; a
  // folder that cannot be made private is used as it is, with a warning).
  unawaited(userAudioDirs.hardenExisting());

  // Save dictations whose history write failed in an earlier session. Fire
  // and forget: startup does not wait for it.
  unawaited(
    recoverPendingAudio(
      container,
      retainAudio: settings.privacy.retainRecentAudio,
      parkWindow: settings.privacy.failedAudioKeepDuration,
    ),
  );

  // Transcribe the audio of recordings that a crash or quit interrupted, once.
  unawaited(recoverInterruptedRecordings(container));

  // RAM check. Low RAM never blocks the app (decision 22, 2026-10-20): the
  // speech recommendation reads the same figure and picks the compact tier.
  // Fail-open: if detection returns null, nothing is advised.
  // Only runs on desktop (mobile/web have different resource models).
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final ramMB = await hw.detectRamMB();
    container.read(ramMBProvider.notifier).set(ramMB);
    if (ramStartupAdvice(ramMB) == RamStartupAdvice.compactSpeechModel) {
      _log.info('RAM below the threshold: compact speech model recommended');
    }
  }

  // Reap orphaned .tmp fragments from aborted model/server downloads
  // (fire-and-forget). At app-start no download is active, so the
  // active-downloads set is empty — any aged .tmp is safe to delete.
  unawaited(sweepOrphanedTmpFiles(directory: sttDir()));
  // `sweepOrphanedTmpFiles` lists `directory` non-recursively, so the sweep
  // above never reaches the Parakeet bundle's own subdirectory
  // (`sttDir()/parakeet-tdt-0.6b-v3/` — see parakeet_model_registry.dart).
  // An abandoned Parakeet download (app crash, force-quit, or a cancel the
  // user never resumes) leaves a `.tmp` fragment there — up to ~650 MB for
  // the encoder alone — that nothing else ever cleans up. Sweep it
  // explicitly so orphaned Parakeet fragments don't accumulate forever.
  unawaited(sweepOrphanedTmpFiles(directory: parakeetModelDir()));

  // Remove pre-FFI whisper-server residue left behind by an upgrade across
  // the whisper-ffi-engine migration (fire-and-forget, runs at most once per
  // app version — see legacy_residue_cleanup.dart). appVersion is already
  // resolved by initAppInfo() above.
  unawaited(
    sweepLegacyResidueIfNeeded(directory: sttDir(), currentVersion: appVersion),
  );

  // Validate the whisper-server binary matches the current hardware. If the
  // GPU changed since the binary was downloaded (e.g., eGPU plugged in,
  // driver update, hardware swap), the incompatible binary is auto-deleted
  // so the next download fetches the correct variant. Fire-and-forget: this
  // is unrelated to backend selection below, just legacy-binary cleanup.
  unawaited(hw.validateAndCleanIncompatibleBinary(sttDir()));

  // Await GPU detection BEFORE runApp(). whisperEngineProvider (the
  // in-process whisper.cpp engine) reads gpuInfoProvider's cached *.value*
  // synchronously at construction time — RecordingOrchestrator's startup
  // pre-warm realizes that provider via a Future.microtask almost
  // immediately after runApp(), which reliably wins the race against
  // gpuInfoProvider's own (genuinely async, up to kWindowsGpuProbeTimeout on
  // Windows) hardware probe. Without this await, the STT engine silently
  // and permanently locks in WhisperBackend.cpu for the whole session,
  // regardless of available/forced GPU acceleration (never re-evaluated
  // afterwards). detectGpu() never throws — worst case this adds a few
  // seconds to cold start on a slow probe, never hangs.
  await container.read(hw.gpuInfoProvider.future);

  _scheduleStartupSideEffects(container, settings);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WhisPasteApp(),
    ),
  );

  // Cold-start t₁: fires after the first frame is rendered.
  // Logs '[PERF] cold-start → first-frame: Xms' for dogfooding (issue 16).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PerfMarkers.instance.markFirstFrame();
  });
}

/// Pure decision for whether the desktop window should stay hidden at
/// startup, extracted from [_initDesktopWindow] so it is unit-testable
/// without touching `window_manager` or any other native API.
///
/// The window is hidden only when the launch was triggered by autostart —
/// either the `--autostart` CLI argument (Windows/Linux today), or a
/// definite macOS Login-Item start reported via [macosLoginItemSignal] — AND
/// both the "launch at startup" and "start minimized" settings are enabled.
///
/// [macosLoginItemSignal] is the native macOS Login-Item detection
/// ([MacOSLifecycleChannel.wasLaunchedAsLoginItem]); `null` off macOS or when
/// the signal is unavailable, which never makes the window hide on its own.
bool shouldMinimize({
  required List<String> args,
  required AppSettings settings,
  bool? macosLoginItemSignal,
}) {
  final isAutostart =
      args.contains('--autostart') || macosLoginItemSignal == true;
  return isAutostart && settings.startMinimized && settings.launchAtStartup;
}

/// Initialises the desktop window manager and applies persisted geometry.
///
/// Runs only on Windows, Linux, and macOS — the caller is responsible for the
/// platform guard.
Future<void> _initDesktopWindow(AppSettings settings, List<String> args) async {
  await windowManager.ensureInitialized();
  // A hot restart keeps the native hotkey registrations of the previous
  // isolate, which then swallow the shortcuts the new isolate registers
  // (the plugin reports success either way). Clear them before the hotkey
  // service registers again; a fresh process has nothing to clear.
  if (kDebugMode) await hotKeyManager.unregisterAll();
  final macosLoginItemSignal = Platform.isMacOS
      ? await MacOSLifecycleChannel.wasLaunchedAsLoginItem()
      : null;

  final geometry = resolveDesktopWindowGeometry(settings);
  // The start size is not bounded by `minimumSize` (that only limits
  // resizing), so it is raised to the minimum and capped to the work area
  // here: a window taller than the work area hides its dock behind the
  // taskbar, and a window shorter than the minimum clips the dock itself.
  final primary = await currentPrimaryWorkArea();
  const minimum = Size(WpLayout.minWindowWidth, WpLayout.minWindowHeight);
  final placement = WindowPositionClamp.place(
    position: geometry.position,
    size: geometry.size,
    minimum: minimum,
    displays: await currentDisplayBounds(),
    primary: primary,
  );
  final windowOptions = WindowOptions(
    size: placement.size,
    // Derived, not guessed: the height is the nav rail's own budget plus
    // title bar, status bar and what the platform window frame eats before
    // the engine sees it (see [WpLayout.minWindowHeight]). At the old 550 the
    // rail was 59 dp short of its rows at a size the app itself enforced;
    // anything below the new value is handled by the rail's scroll fallback,
    // for the window managers that ignore this request.
    // Capped to the work area: a minimum taller than the screen would push
    // the bottom edge under the taskbar or Dock.
    minimumSize: primary == null
        ? minimum
        : WindowPositionClamp.capMinimum(minimum, primary),
    center: placement.position == null,
    title: 'WhisPaste',
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // A position saved before a monitor was unplugged (or from a settings
    // backup restored on different hardware) is already clamped onto a
    // connected display by [WindowPositionClamp.place].
    final position = placement.position;
    if (position != null) {
      await windowManager.setPosition(position);
    }
    if (geometry.maximized) {
      await windowManager.maximize();
    }

    // Start minimized only when launched via autostart (system boot),
    // not when the user explicitly opens the app from Dock/Taskbar.
    final hide = shouldMinimize(
      args: args,
      settings: settings,
      macosLoginItemSignal: macosLoginItemSignal,
    );

    if (!hide) {
      await windowManager.show();
      await windowManager.focus();
    } else {
      // The runners hold back their own first-frame show on an autostart
      // launch (Windows/Linux); macOS opens the nib window regardless, so
      // hide explicitly on every platform.
      await windowManager.hide();
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

/// The "Check for Updates" toggle as of now (off while settings are unknown).
bool _automaticUpdateChecksEnabled(ProviderContainer container) =>
    container.read(settingsProvider).value?.updates.checkUpdates ?? false;

/// Schedules fire-and-forget startup side effects that do not block the UI.
void _scheduleStartupSideEffects(
  ProviderContainer container,
  AppSettings settings,
) {
  // Retention: trash purge and expired-audio sweep, now and then daily.
  startRetentionSchedule(container);

  // Boot the audio engine off the hotkey path. Delayed so the native init
  // lands after the first frames rather than competing with them — see
  // SoundFeedbackService.prewarm for the measured cost of not doing this.
  Future<void>.delayed(const Duration(seconds: 2), () {
    unawaited(container.read(soundFeedbackProvider.notifier).prewarm());
  });

  // Not externally managed — store and package-manager (Homebrew Cask,
  // Scoop) builds have no self-updater at all, see isExternallyManaged.
  final channel = container.read(deployChannelProvider);
  if (!isExternallyManaged(channel)) {
    if (Platform.isLinux) {
      // Linux — no Sparkle/WinSparkle; keep the GitHub API check, at start
      // and every 24 h, each gated by the toggle at that moment.
      Future<void>.delayed(const Duration(seconds: 3), () {
        unawaited(
          startAutomaticUpdateChecks(
            check: container.read(updateProvider.notifier).checkForUpdate,
            enabled: () => _automaticUpdateChecksEnabled(container),
          ),
        );
      });
    } else {
      // macOS / Windows non-store. Register the listener UNCONDITIONALLY
      // (not gated by `settings.checkUpdates`) so the native "update
      // available"/"up to date"/error events are mirrored into
      // `updateProvider` — otherwise the status bar chip, About page, and
      // Settings never learn what a native check found (PRD Bug 1). This
      // must cover manual checks too: `presentSparkleUpdate` (triggered from
      // About/Settings/status bar) sets its own feed URL and runs
      // regardless of this toggle, so a user who disabled the automatic
      // startup check must still see the result of a manual one.
      final updateNotifier = container.read(updateProvider.notifier);
      registerSparkleListener(
        onChecking: updateNotifier.markCheckingNative,
        onAvailable: (version, releaseNotesUrl) =>
            updateNotifier.markAvailableNative(
              version: version,
              releaseNotesUrl: releaseNotesUrl,
            ),
        onUpToDate: updateNotifier.markUpToDateNative,
        onReadyToInstall: updateNotifier.markReadyToInstallNative,
        onError: updateNotifier.markErrorNative,
      );
      // The automatic (startup-silent + 24 h) checks stay gated by the
      // toggle, re-read on every tick so it applies without a restart.
      // Load the persisted update channel first so the correct feed
      // (stable/beta appcast) is requested from the very first check.
      unawaited(
        container
            .read(updateChannelProvider.future)
            .then(
              (updateChannel) => initAutoUpdater(
                channel,
                updateChannel,
                isEnabled: () => _automaticUpdateChecksEnabled(container),
              ),
            ),
      );
    }
  }

  // Anonymous usage telemetry (opt-out). No-op without consent, config, or
  // The app_version dimension on this event
  // doubles as version-adoption signal.
  final telemetry = container.read(telemetryProvider);
  telemetry.trackEvent(category: 'lifecycle', action: 'start');
  // Counts failed model downloads for the session; read once so the listener
  // lives as long as the app.
  container.read(modelDownloadFailureTelemetryProvider);
  // T5 (Matomo product analysis 2026-09-04): coarse, once-per-day
  // active-install signal, deliberately separate from the granular event
  // above — see `TelemetryService.sendDailyAlivePingIfDue` for the
  // consent/opt-out caveat.
  unawaited(
    SharedPreferences.getInstance().then(telemetry.sendDailyAlivePingIfDue),
  );

  // Best-effort graceful teardown on logout/kill. macOS/Linux emit SIGTERM on
  // session end; SIGINT covers Ctrl+C everywhere. Windows has no real
  // SIGTERM, so only sigint is wired there.
  _installShutdownSignalHandlers(container);
}

/// Installs best-effort signal handlers that run the same native-resource
/// teardown as every other quit path (window close, tray quit, macOS
/// Cmd+Q/Dock-quit — see `graceful_shutdown.dart`) before the process exits
/// on logout/kill. Without this, a SIGINT/SIGTERM arriving while the
/// on-device STT engine holds native GPU/Metal resources exits the process
/// out from under it — the same crash class as FLUTTER_WHISPASTE-BC, just
/// reached via a quit path that bypasses window-close entirely.
void _installShutdownSignalHandlers(ProviderContainer container) {
  Future<void> shutdownAndExit() async {
    // Hard limit: a hung shutdown step must not keep the process alive
    // (SIGTERM is otherwise ignored). See quit_deadline.dart.
    await shutdownWithHardDeadline(
      orderlyShutdown: () => runGracefulEngineShutdown(container),
      hardExit: endProcessWithoutDestructors,
    );
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdownAndExit());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdownAndExit());
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
    // Old-identity reads go through BundleIdMigrationHost.swift (macOS-only
    // native bridge): NSUserDefaults(suiteName: kOldBundleId) for prefs, and
    // a raw SecItemCopyMatching query for Keychain items, matching the exact
    // service/account scheme flutter_secure_storage_darwin writes with. Both
    // are best-effort — a failed native read surfaces as `null`, which
    // runBundleIdMigration already treats as "no old data" (no-op).
    const secureStorage = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    const newSecure = SecureStorageAdapter(secureStorage);
    final newPrefsAdapter = SharedPreferencesAdapter(prefs);

    const oldSecure = OldKeychainAdapter();
    const oldPrefsAdapter = OldPreferencesAdapter();

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
