import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_info.dart';
import 'core/config/settings_labels.dart';
import 'core/config/settings_provider.dart';
import 'core/navigation/page_state.dart';
import 'core/onboarding/onboarding_revision.dart';
import 'core/onboarding/onboarding_surface.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_provider.dart';
import 'core/theme/theme.dart';
import 'core/theme/colors.dart';
import 'core/theme/tokens.dart';
import 'widgets/sidebar.dart';
import 'widgets/status_bar.dart';
import 'widgets/recording_indicator_bar.dart';
import 'widgets/title_bar.dart';
import 'core/platform/desktop_window_geometry.dart';
import 'core/platform/display_bounds.dart';
import 'core/platform/window_position_clamp.dart';
import 'widgets/service_bootstrap.dart';
import 'widgets/recording_behavior.dart';
import 'features/history/history_page.dart';
import 'features/history/data/providers.dart' show groupedHistoryProvider;
import 'features/notes/notes_page.dart';
import 'features/settings/settings_page.dart';
import 'features/replacements/replacements_page.dart';
import 'features/snippets/snippets_page.dart';
import 'features/analytics/analytics_page.dart';
import 'features/about/about_page.dart';
import 'features/feedback/feedback_page.dart';
import 'features/onboarding/onboarding_overlay.dart';
import 'core/platform/macos_lifecycle_channel.dart';
import 'core/recording/recording_state.dart';
import 'core/data/database.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/crash_reporter.dart';
import 'core/config/settings_enums.dart' show OnDeviceEngine;
import 'core/config/build_config.dart' show kAutoPasteSupported;
import 'features/onboarding/mic_probe.dart'
    show MicProbeOutcome, OnboardingMicProbe;
import 'services/paste/paste_capability_notifier.dart';
import 'services/paste/paste_policy.dart';
import 'services/paste/paster.dart' show PasteCapabilityStatus;
import 'services/paste/tcc_reset_notice.dart';
import 'services/permissions/mic_permission_notifier.dart';
import 'services/permissions/startup_permission_gate.dart';
import 'services/audio_service.dart' show audioInputDevicesProvider;
import 'services/microphone_selection_service.dart';
import 'services/settings_autosave_service.dart';
import 'services/settings_portability_service.dart'
    show buildSettingsExportBundle;
import 'services/single_instance_service.dart';
import 'services/graceful_shutdown.dart';
import 'services/stt/backend_utilization_notifier.dart';
import 'services/stt/stt_bundle.dart';
import 'services/stt_parakeet/parakeet_engine_notifier.dart'
    show ParakeetEngineState, parakeetEngineProvider;
import 'services/telemetry_service.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'services/update_actions.dart';
import 'services/deploy_channel_service.dart';
import 'widgets/dialog.dart';
import 'widgets/toast.dart';
import 'widgets/feature_spotlight_notice.dart';
import 'features/onboarding/smart_mode_usage_hint.dart';
import 'widgets/review_prompt_dialog.dart';
import 'widgets/store_thank_you_dialog.dart';
import 'widgets/support_prompt_dialog.dart';

// activePageProvider and settingsScrollTargetProvider are defined in
// lib/core/navigation/page_state.dart (imported above).
// Re-exported below so existing import sites (e.g. tests) that use
// `show activePageProvider` on this file continue to resolve without changes.
export 'core/navigation/page_state.dart'
    show activePageProvider, settingsScrollTargetProvider;

/// Main WhisPaste application widget.
class WhisPasteApp extends ConsumerWidget {
  const WhisPasteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'WhisPaste',
      debugShowCheckedModeBanner: false,
      // One theme, passed as `theme:` alone — no `darkTheme:`/`themeMode:`
      // pair (2026-08-11). Handing the same ThemeData to both slots would
      // have kept the shape of a choice the app no longer offers, and
      // `themeMode:` would then be a setting whose every value looks the
      // same.
      theme: wpDarkTheme(),
      locale: locale,
      localizationsDelegates: const [
        ...L10n.localizationsDelegates,
        LocaleNamesLocalizationsDelegate(),
      ],
      supportedLocales: L10n.supportedLocales,
      // Tracks dialog/route pushes (toasts, review prompt, file pickers) as
      // Sentry breadcrumbs and transactions. Page-level navigation is handled
      // in-shell via activePageProvider and isn't visible to this observer.
      navigatorObservers: [SentryNavigatorObserver()],
      home: const _AppShell(),
    );
  }
}

/// Navigation items — built from localized strings.
///
/// Public so the screenshot integration test can build an identical sidebar.
///
/// Ordered in two deliberate groups (separated in the sidebar via
/// [wpNavDividerAfterIds]):
///
/// 1. **Recording-cycle tools** — History (the record of past recording
///    cycles), Notizen (freeform notes, independent of any recording), then
///    the trigger-phrase family: Replacements (transform text), Snippets
///    (insert stored text).
/// 2. **Product/meta** — Analytics, Feedback, About (canonical last entry).
List<WpNavItem> wpNavItems(L10n l10n) => [
  WpNavItem(id: 'history', icon: LucideIcons.clock3, label: l10n.navHistory),
  WpNavItem(id: 'notes', icon: LucideIcons.stickyNote, label: l10n.navNotes),
  WpNavItem(
    id: 'replacements',
    icon: LucideIcons.replace,
    label: l10n.navReplacements,
  ),
  WpNavItem(
    id: 'snippets',
    icon: LucideIcons.notebookText,
    label: l10n.navSnippets,
  ),
  WpNavItem(
    id: 'analytics',
    icon: LucideIcons.chartNoAxesColumn,
    label: l10n.navAnalytics,
  ),
  WpNavItem(
    id: 'feedback',
    icon: LucideIcons.messageSquare,
    label: l10n.navFeedback,
  ),
  WpNavItem(id: 'about', icon: LucideIcons.info, label: l10n.navAbout),
];

/// Group break between the recording-cycle tools and the product/meta nav items —
/// single source of truth for every [WpSidebar] call site (app shell,
/// screenshot shells), so grouping stays consistent everywhere.
const Set<String> wpNavDividerAfterIds = {'snippets'};

/// The Settings entry pinned to the bottom of the rail.
///
/// Same [WpNavItem] type and same renderer as [wpNavItems] — it used to be a
/// hand-copied widget, which is how it acquired an RTL-blind indicator bar and
/// a vertical rhythm 16 px tighter than the items above it. Public so the
/// screenshot shells build the identical rail.
///
/// [badgeHint] carries the attention dot's *reason*, not a flag: pass the
/// sentence a screen reader should read, or null for no dot.
WpNavItem wpSettingsNavItem(L10n l10n, {String? badgeHint}) => WpNavItem(
  id: 'settings',
  icon: LucideIcons.settings,
  label: l10n.navSettings,
  badgeHint: badgeHint,
);

/// Resolves the page title — checks nav items first, falls back for
/// bottom-pinned pages (e.g. Settings).
String wpPageTitle(String pageId, List<WpNavItem> navItems, L10n l10n) {
  for (final item in navItems) {
    if (item.id == pageId) return item.label;
  }
  if (pageId == 'settings') return l10n.navSettings;
  return '';
}

/// Maps Parakeet's engine-lifecycle state onto the status bar's generic
/// [SttServerState] — both enums share the same four states by name, so this
/// is a presentation-only translation (the status bar doesn't know Parakeet
/// exists).
SttServerState _sttServerStateFor(ParakeetEngineState state) => switch (state) {
  ParakeetEngineState.stopped => SttServerState.stopped,
  ParakeetEngineState.starting => SttServerState.starting,
  ParakeetEngineState.ready => SttServerState.ready,
  ParakeetEngineState.error => SttServerState.error,
};

/// Coarse device kind for the status bar's far-right backend chip —
/// deliberately `'CPU'`/`'GPU'`, never the specific architecture
/// (Metal/CUDA/Vulkan): the user asked for "just CPU or GPU" after finding
/// the specific name (e.g. "Metal") more detail than they wanted there.
/// `null` before any local model has ever loaded (nothing to report yet).
String? _sttBackendKind(WhisperBackend? backend) => switch (backend) {
  null => null,
  WhisperBackend.cpu => 'CPU',
  WhisperBackend.metal || WhisperBackend.cuda || WhisperBackend.vulkan => 'GPU',
};

/// Map page IDs to their widgets.
const wpPageWidgets = <String, Widget>{
  'history': HistoryPage(),
  'notes': NotesPage(),
  'settings': SettingsPage(),
  'replacements': ReplacementsPage(),
  'snippets': SnippetsPage(),
  'analytics': AnalyticsPage(),
  'about': AboutPage(),
  'feedback': FeedbackPage(),
};

/// Pure decision for whether the startup permission gate should run,
/// extracted from [_AppShellState._runStartupPermissionGate] so it is
/// unit-testable without the surrounding widget tree.
///
/// The onboarding flow owns both permissions with its own richer UI — the
/// gate only takes over once that surface is not on top, i.e. from the second
/// start on for a first run, and again the moment a review reopened from
/// Settings ends. `settings == null` (not loaded yet) is treated like "not
/// completed", matching the `?? false` fallback this replaces at the call
/// site.
bool shouldRunStartupPermissionGate(
  AppSettings? settings, {
  bool onboardingManuallyOpen = false,
  bool onboardingRevisionRunning = false,
}) => !onboardingSurfaceActive(
  onboardingCompleted: settings?.onboarding.onboardingCompleted ?? false,
  manuallyOpen: onboardingManuallyOpen,
  revisionRunning: onboardingRevisionRunning,
);

/// Pure decision for whether closing the window should hide to tray (`true`)
/// or quit the app (`false`), extracted from
/// [_AppShellState.onWindowClose] so it is unit-testable without the
/// surrounding widget tree / window_manager channel.
///
/// During first-run onboarding, closing the window must always quit — never
/// hide to tray, regardless of the `closeToTray` setting. A half-onboarded
/// background process has no configured hotkey and no discoverable UI; the
/// user's mental model of the X button on the onboarding surface is "abort",
/// not "minimize". `settings == null` (not loaded yet) is treated like
/// "onboarding not completed", so an early close before settings resolve
/// quits rather than risks a stranded background process.
///
/// An onboarding revision run (`.scratch/onboarding-revisions/issues/03`)
/// gets the identical treatment even though `onboardingCompleted` is already
/// true for that user: the parent PRD is explicit that closing the window
/// during a run "beendet weiterhin die App und ist kein Ausgang — es
/// stempelt nichts" (still quits the app, is not an exit, stamps nothing) —
/// the visible exit is a separate, dedicated action, not the window chrome.
bool shouldHideToTrayOnClose(
  AppSettings? settings, {
  bool onboardingRevisionRunning = false,
}) =>
    (settings?.closeToTray ?? true) &&
    (settings?.onboarding.onboardingCompleted ?? false) &&
    !onboardingRevisionRunning;

/// Root layout: title bar + sidebar + content + status bar.
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell>
    with WindowListener, WidgetsBindingObserver {
  static final _log = AppLogger('AppShell');
  Timer? _windowSaveTimer;
  Timer? _telemetryFlushTimer;
  bool _isMaximized = false;

  /// Watches the shared capability state so the native "must restart" modal
  /// fires the instant [PasteCapabilityNotifier.needsRestart] becomes true —
  /// even with the window hidden (tray-only), because the widget tree stays
  /// mounted in the background. Closed in [dispose].
  ProviderSubscription<PasteCapabilityState>? _restartWatchSub;

  /// Keeps the history provider chain (`filteredHistoryProvider` →
  /// `groupedHistoryProvider`) recomputing while the Notes page is showing
  /// and History has no listener of its own — otherwise entries saved during
  /// that time (e.g. several quick-note dictations) pile up as unflushed
  /// invalidations, and HistoryPage's first `ref.watch` on remount has to
  /// catch them all up synchronously mid-build, which Riverpod schedules via
  /// a `setState()` on `UncontrolledProviderScope` that Flutter rejects
  /// because that widget isn't part of the in-progress build — crashing (and,
  /// with a debugger attached, freezing) the Notizen→Verlauf switch. Closed
  /// in [dispose].
  ProviderSubscription<Object?>? _historyWarmupSub;

  /// Autosicherung (Ticket 26). Lives here rather than in the settings
  /// section that switches it on, because two of its three triggers — a
  /// replacement, a snippet — happen on pages of their own, and because a
  /// backup must still run with the settings page closed and the window
  /// hidden in the tray. Closed in [dispose].
  SettingsAutosaveScheduler? _autosaveScheduler;
  final List<ProviderSubscription<Object?>> _autosaveSubs = [];

  /// Last exported-content fingerprint (see [autosaveTriggerSignature]).
  /// Compared instead of the raw settings object so the settings that change
  /// constantly on their own — window geometry, and the autosave feature's
  /// own timestamps — cannot schedule a backup.
  String? _autosaveSignature;

  /// One-shot latch per restart episode: keeps a re-derived `needsRestart`
  /// (probes re-run on focus / poll) from re-invoking the modal while one is
  /// already up. Reset when the state leaves the restart-needed condition.
  bool _restartModalActive = false;

  /// Best-effort flush of session-aggregated telemetry. Drains the hot-path
  /// counters into the sender and awaits pending HTTP requests. No-op without
  /// consent/config, and never throws — telemetry must not break the app.
  Future<void> _drainAndFlushTelemetry({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final telemetry = ref.read(telemetryProvider);
      await ref
          .read(telemetrySessionAggregatorProvider)
          .drainAndFlush(telemetry)
          .timeout(timeout, onTimeout: () {});
    } catch (e) {
      _log.debug('telemetry flush failed (non-fatal): $e');
    }
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      windowManager.isMaximized().then((v) => _isMaximized = v);
      // The fixed onboarding window size never touched the persisted regular
      // geometry (see `_debounceSaveWindowState`) — the moment onboarding
      // completes, that persisted geometry is exactly the pre-onboarding
      // state, and this puts the actual OS window back on it.
      ref.listenManual(settingsProvider, (prev, next) {
        final wasCompleted =
            prev?.value?.onboarding.onboardingCompleted ?? false;
        final settings = next.value;
        if (wasCompleted || settings == null) return;
        if (!settings.onboarding.onboardingCompleted) return;
        unawaited(_restoreRegularWindowGeometry(settings));
      });
    }
    _historyWarmupSub = ref.listenManual(groupedHistoryProvider, (_, _) {});

    // Observe app lifecycle (background/suspend) so session-aggregated
    // telemetry is flushed even when the window-close path is skipped
    // (closeToTray is the default) — this is the flush point that actually
    // fires for most sessions, since hide-to-tray triggers `hidden`/`paused`.
    // The periodic timer below is ONLY a crash safety-net for the process
    // being killed without any lifecycle callback at all (OS force-quit,
    // power loss) — it must stay coarse. A short interval defeats the whole
    // point of session-level aggregation: live Matomo data showed an active
    // session producing a request every one-to-few minutes instead of one
    // batch, because every 60 s bucket got flushed as its own mini-batch.
    WidgetsBinding.instance.addObserver(this);
    _telemetryFlushTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(
        _drainAndFlushTelemetry(timeout: const Duration(seconds: 3)),
      ),
    );

    // Show one-time migration toast if Go → Flutter migration happened.
    // Force a DB query first to ensure beforeOpen/migrations have completed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Reactively sync crash reporting consent whenever settings change.
      // This replaces the old build()-side-effect approach.
      ref.listenManual(settingsProvider, (_, next) {
        final s = next.value;
        if (s != null) {
          CrashReporter.instance?.consentGranted = s.errorReporting;
        }
      }, fireImmediately: true);

      final db = ref.read(historyDatabaseProvider);
      // Ensures Drift's beforeOpen (and _reconcileGoSchema) has run.
      await db.customSelect('SELECT 1').get();
      if (!mounted) return;
      final count = db.consumeGoMigrationCount();
      if (count != null && count > 0) {
        final l10n = L10n.of(context);
        WpToast.show(
          context,
          message: l10n.migrationComplete(count),
          type: WpToastType.success,
          duration: const Duration(seconds: 8),
        );
      }

      // Show one-time toast when a user's Groq STT provider was reset
      // to On-Device after the Groq removal in v1.2.13.
      if (db.consumeGroqMigrationFlag()) {
        final l10n = L10n.of(context);
        WpToast.show(
          context,
          message: l10n.groqRemovedToast,
          type: WpToastType.info,
          duration: const Duration(seconds: 8),
        );
      }

      unawaited(_runStartupPermissionFlows());
    });

    _setupSettingsAutosave();
  }

  /// Arms the Autosicherung triggers (Ticket 26, decisions E11a–E11d).
  ///
  /// Purely event-driven: three listeners, one debounce, no periodic timer
  /// and nothing that runs at startup. The settings listener compares
  /// [autosaveTriggerSignature] rather than the settings object, so only a
  /// change that would alter the backup file counts — which is also what
  /// stops the scheduler's own success timestamp from triggering the next
  /// run.
  void _setupSettingsAutosave() {
    final scheduler = SettingsAutosaveScheduler(
      runner: SettingsAutosaveRunner(
        gather: () async => buildSettingsExportBundle(
          settings: ref.read(settingsProvider).value ?? AppSettings.defaults,
          replacements: ref.read(replacementsProvider).value ?? const [],
          snippets: ref.read(snippetsProvider).value ?? const [],
        ),
      ),
      readConfig: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults).autosave,
      writeConfig: (update) => ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(autosave: update(s.autosave)),
          ),
      reportFailure: _reportAutosaveFailure,
    );
    _autosaveScheduler = scheduler;
    _autosaveSignature = switch (ref.read(settingsProvider).value) {
      final settings? => autosaveTriggerSignature(settings),
      null => null,
    };

    final settingsSub = ref.listenManual(settingsProvider, (previous, next) {
      final after = next.value;
      if (after == null) return;
      if (autosaveNeedsImmediateRun(
        previous?.value?.autosave,
        after.autosave,
      )) {
        _autosaveSignature = autosaveTriggerSignature(after);
        scheduler.runNow();
        return;
      }
      final signature = autosaveTriggerSignature(after);
      final baseline = _autosaveSignature;
      _autosaveSignature = signature;
      // The first settled value only establishes the baseline. It is the
      // provider hydrating, not something the user did, and must not produce
      // a backup on launch.
      if (previous?.value == null || baseline == null) return;
      if (signature == baseline) return;
      scheduler.scheduleRun();
    });

    // Replacements and snippets carry no comparable fingerprint — their
    // notifiers emit when the list actually changed — so any settled value
    // after a settled value counts. The `AsyncLoading → AsyncData` hydration
    // is filtered out by requiring both sides to hold data.
    final replacementsSub = ref.listenManual(replacementsProvider, (
      previous,
      next,
    ) {
      if (previous?.value == null || next.value == null) return;
      scheduler.scheduleRun();
    });
    final snippetsSub = ref.listenManual(snippetsProvider, (previous, next) {
      if (previous?.value == null || next.value == null) return;
      scheduler.scheduleRun();
    });

    _autosaveSubs.addAll([settingsSub, replacementsSub, snippetsSub]);
  }

  /// Decision E11d: every failed run toasts, not just a repeated one. A
  /// successful run says nothing at all — the passive status line in the
  /// settings section is where success lives.
  void _reportAutosaveFailure(SettingsAutosaveFailure failure, String? detail) {
    if (!mounted) return;
    final l10n = L10n.of(context);
    WpToast.show(
      context,
      message: switch (failure) {
        SettingsAutosaveFailure.locationUnavailable =>
          l10n.settingsAutosaveErrorLocation,
        SettingsAutosaveFailure.writeFailed => l10n.settingsAutosaveErrorWrite(
          detail ?? '',
        ),
      },
      type: WpToastType.error,
    );
  }

  /// Strictly ordered startup sequence for everything permission-shaped:
  /// an onboarding revision run starts first — before any of the checks
  /// below read `onboardingRevisionRunning`, so none of them can race a
  /// native dialog onto the onboarding surface — then the TCC-reset notice
  /// hydrates the restart marker and runs the first capability probe, the
  /// restart watch must be armed before any grant flow can trigger a
  /// restart, and the proactive gate runs last so it reads a settled
  /// capability state.
  Future<void> _runStartupPermissionFlows() async {
    await _maybeStartOnboardingRevisionRun();
    await _maybeShowTccResetNotice();
    _setupAutoPasteRestartWatch();
    await _runStartupPermissionGate();
  }

  /// Starts an onboarding revision run (`.scratch/onboarding-revisions/
  /// issues/03`) the moment settings confirm one is due for this user and
  /// platform. `onboardingRevisionDue` is the same pure trigger function the
  /// grandfathering migration checks at settings-load time
  /// (`onboarding_revision.dart`); this is the other half — turning "due"
  /// into an actual run, once per process, right before anything else that
  /// must stay out of the onboarding surface's way gets a chance to check.
  Future<void> _maybeStartOnboardingRevisionRun() async {
    final onboarding = ref.read(settingsProvider).value?.onboarding;
    if (onboarding == null) return;
    final registry = ref.read(onboardingRevisionRegistryProvider);
    final target = targetOnboardingContentVersion(
      registry,
      currentOnboardingPlatform(),
    );
    if (!onboardingRevisionDue(
      onboardingCompleted: onboarding.onboardingCompleted,
      seenContentVersion: onboarding.onboardingContentVersion,
      targetContentVersion: target,
    )) {
      return;
    }
    await ref.read(onboardingRevisionRunProvider.notifier).start();
  }

  /// Subscribes to the capability notifier and drives the native forced-restart
  /// modal off [PasteCapabilityNotifier.needsRestart]. Deliberately app-level
  /// (not inside a settings widget) so it works when WhisPaste is backgrounded
  /// with no window open — the whole point of the modal. Suppressed until
  /// onboarding is complete: the onboarding Auto-Paste step surfaces its own
  /// inline restart banner, and a competing OS modal there would be redundant.
  void _setupAutoPasteRestartWatch() {
    if (!Platform.isMacOS || !kAutoPasteSupported) return;
    _restartWatchSub = ref.listenManual(pasteCapabilityNotifierProvider, (
      _,
      _,
    ) {
      final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
      final needsRestart = notifier.needsRestart;
      if (!needsRestart) {
        _restartModalActive = false;
        return;
      }
      if (_restartModalActive) return;
      final onboarding = ref.read(settingsProvider).value?.onboarding;
      // Single shared guard set (see shouldShowAutoPasteRestartSurface):
      // clipboard-only users must never see any Auto-Paste modal — the
      // permission is meaningless for them, no matter what stale state
      // (restart marker, capability probes) is lying around.
      if (!shouldShowAutoPasteRestartSurface(
        needsRestart: needsRestart,
        onboardingCompleted: onboarding?.onboardingCompleted ?? false,
        onboardingManuallyOpen: ref.read(onboardingManuallyOpenProvider),
        onboardingRevisionRunning: ref.read(onboardingRevisionRunProvider),
        userPastes: _userPastesAfterTranscription(),
      )) {
        return;
      }
      _restartModalActive = true;
      // Second-attempt awareness: if a grant-driven restart ALREADY happened
      // (the cross-process marker is set) and we're back in "restart needed",
      // a plain restart demonstrably isn't taking — auto-restarting again just
      // loops the backgrounded user forever. Break out with an actionable
      // manual alert (opens System Settings) instead of the forced restart.
      final alreadyRestarted = ref
          .read(pasteCapabilityNotifierProvider)
          .restartAttempted;
      if (alreadyRestarted) {
        unawaited(_showManualGrantAlert());
      } else {
        unawaited(_showForcedRestartModal(notifier));
      }
    });
  }

  Future<void> _showForcedRestartModal(PasteCapabilityNotifier notifier) async {
    if (!mounted) return;
    final l10n = L10n.of(context);
    // Persist the marker BEFORE handing off to the native modal: the alert is
    // single-action (no cancel — the user cannot opt out) and always ends in a
    // relaunch, so recording the attempt here lets the fresh process detect an
    // ineffective restart even if it is killed mid-relaunch.
    await notifier.markRestartAttempted();
    await MacOSLifecycleChannel.showRestartRequiredAlert(
      title: l10n.pasteRestartAlertTitle,
      body: l10n.pasteRestartAlertBody,
      confirmLabel: l10n.pasteRestartAlertConfirm,
    );
  }

  /// The loop exit: a plain restart already ran and the permission is STILL
  /// missing, so instead of forcing yet another relaunch this native alert
  /// tells the user plainly and — on confirm — opens System Settings →
  /// Accessibility so they can verify/re-toggle WhisPaste themselves. Surfaces
  /// even when backgrounded, so the honest dead-end is never buried on a
  /// settings page the user doesn't have open.
  Future<void> _showManualGrantAlert() async {
    if (!mounted) return;
    final l10n = L10n.of(context);
    await MacOSLifecycleChannel.showManualGrantAlert(
      title: l10n.pasteManualGrantAlertTitle,
      body: l10n.pasteManualGrantAlertBody,
      confirmLabel: l10n.pasteManualGrantAlertConfirm,
    );
  }

  /// Proactive, one-time-per-version nudge when macOS reset the Auto-Paste
  /// (Accessibility) permission as a side effect of an app update — see
  /// tcc_reset_notice.dart. Previously the only way to discover a reset
  /// permission was to stumble into Settings → After Transcription; this
  /// surfaces it right after the update that caused it, with a one-tap fix.
  Future<void> _maybeShowTccResetNotice() async {
    if (!Platform.isMacOS) return;
    final capNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    // Hydrate the cross-process restart marker BEFORE the first probe so the
    // cold-start `capability.probed` breadcrumb carries it — that single trace
    // is what tells "the grant never persisted" apart from "the restart never
    // produced a fresh process" on the next live test.
    await capNotifier.hydrateRestartMarker();
    await capNotifier.check();
    if (!mounted) return;
    // The probe above stays (it settles the capability state the startup
    // gate reads), but the notice itself is an Auto-Paste surface — never
    // show it to users whose after-transcription action doesn't paste.
    if (!_userPastesAfterTranscription()) return;
    final capability = ref.read(pasteCapabilityNotifierProvider).capability;
    final onboarding = ref.read(settingsProvider).value?.onboarding;
    final shouldShow = await maybeMarkTccResetNoticeVersion(
      currentVersion: appVersion,
      onboardingCompleted: onboarding?.onboardingCompleted ?? false,
      onboardingManuallyOpen: ref.read(onboardingManuallyOpenProvider),
      onboardingRevisionRunning: ref.read(onboardingRevisionRunProvider),
      isMacOS: true,
      capabilityStatus: capability?.status,
    );
    if (!shouldShow || !mounted) return;
    final l10n = L10n.of(context);
    WpToast.show(
      context,
      message: l10n.tccResetAfterUpdateToast,
      type: WpToastType.warning,
      duration: const Duration(seconds: 12),
      // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; the WpButton in _ToastCard.build derives its accessible label from `label`
      action: WpToastAction(
        label: l10n.pasteCapabilityGrantButton,
        onPressed: () => unawaited(_grantAccessibilityFromNotice(capNotifier)),
      ),
    );
  }

  Future<void> _grantAccessibilityFromNotice(
    PasteCapabilityNotifier capNotifier,
  ) async {
    // This notice only fires when a signature change was just detected (see
    // shouldShowTccResetNotice) — the entry is bound to the old code-signing
    // hash, so unlike the general requestGrant() flow (which assumes a
    // possibly-still-good grant and tries a non-destructive restart before
    // ever wiping anything), repair() here is the correct first step, not an
    // escalation: a plain re-request would just re-hit the same stale entry.
    await capNotifier.repair();
    await capNotifier.requestGrant();
  }

  /// Proactive permission gate: on EVERY start (after onboarding has been
  /// completed once) both load-bearing permissions — microphone and
  /// Auto-Paste — are probed, and a missing one immediately triggers a
  /// native, always-on-top guided recovery instead of failing silently at
  /// the first recording/paste. See `startup_permission_gate.dart` for the
  /// full decision tree and the platform truths it encodes.
  Future<void> _runStartupPermissionGate() async {
    if (!shouldRunStartupPermissionGate(
      ref.read(settingsProvider).value,
      onboardingManuallyOpen: ref.read(onboardingManuallyOpenProvider),
      onboardingRevisionRunning: ref.read(onboardingRevisionRunProvider),
    )) {
      return;
    }

    // The gate always constructs in a fresh process (only after onboarding —
    // which owns the first in-process permission ask — has already completed
    // in an earlier process), so `request()` below is always this process's
    // first ask: it never opens Settings/polls on its own, leaving that
    // orchestration entirely to `_runMicGate()`'s own hooks below.
    final micNotifier = ref.read(micPermissionNotifierProvider.notifier);
    final gate = StartupPermissionGate(
      mic: MicGateHooks(
        checkPermission: ({required bool request}) =>
            request ? micNotifier.request() : micNotifier.check(),
        verifyCapture: _verifyMicCapture,
        showGrantAlert: _showMicGateGrantAlert,
        openSettings: _openMicPrivacySettings,
        showRestartAlert: _showMicGateRestartAlert,
      ),
      autoPaste: Platform.isMacOS && kAutoPasteSupported
          ? AutoPasteGateHooks(
              readStatus: _readAutoPasteGateStatus,
              showGrantAlert: _showAutoPasteGateGrantAlert,
              startGrantFlow: _startAutoPasteGateGrantFlow,
              showManualGrantAlert: _showManualGrantAlert,
            )
          : null,
    );
    await gate.run();
  }

  /// Post-recovery proof that capture actually works in THIS process: opens
  /// a short real PCM stream. `silence` counts as success — the stream
  /// opened, there just was no speech, which is expected for an unattended
  /// probe. Only `permissionDenied`/`error` mean the running process still
  /// can't record despite the on-disk grant.
  Future<bool> _verifyMicCapture() async {
    final probe = OnboardingMicProbe(
      timeout: const Duration(milliseconds: 1500),
    );
    try {
      final outcome = await probe.start();
      return outcome == MicProbeOutcome.speechDetected ||
          outcome == MicProbeOutcome.silence;
    } finally {
      await probe.dispose();
    }
  }

  /// Returns whether the user confirmed the guided fix. A decline (or a
  /// failed native dispatch) aborts the recovery — Settings opening "out of
  /// nowhere" without a confirmed dialog is exactly the kind of surprise
  /// this flow must not produce.
  Future<bool> _showMicGateGrantAlert() async {
    if (!mounted) return false;
    final l10n = L10n.of(context);
    if (Platform.isMacOS) {
      final choice = Completer<bool>();
      final dispatched = await MacOSLifecycleChannel.showPermissionGrantAlert(
        id: 'mic_gate',
        title: l10n.micGateAlertTitle,
        body: l10n.micGateAlertBody,
        confirmLabel: l10n.micGateAlertConfirm,
        cancelLabel: l10n.permissionAlertLaterButton,
        onDismiss: choice.complete,
      );
      if (!dispatched) return false;
      return choice.future;
    }
    // Windows/Linux: no native always-on-top channel — surface the window
    // and use an in-app dialog instead.
    await windowManager.show();
    await windowManager.focus();
    if (!mounted) return false;
    return showWpConfirmDialog(
      context: context,
      title: l10n.micGateAlertTitle,
      message: l10n.micGateAlertBodyGeneric,
      confirmLabel: l10n.micGateAlertConfirm,
      cancelLabel: l10n.permissionAlertLaterButton,
    );
  }

  Future<void> _openMicPrivacySettings() =>
      ref.read(micPermissionNotifierProvider.notifier).openSystemSettings();

  /// The mic pendant to [_showForcedRestartModal]: the grant is on disk but
  /// this process demonstrably still can't capture, so relaunch. Releases
  /// the single-instance lock FIRST — the fresh process must be able to
  /// claim it, exactly like the Auto-Paste restart path (see
  /// [PasteCapabilityNotifier.markRestartAttempted]).
  Future<void> _showMicGateRestartAlert() async {
    if (!Platform.isMacOS || !mounted) return;
    final l10n = L10n.of(context);
    await SingleInstanceService.release();
    await MacOSLifecycleChannel.showRestartRequiredAlert(
      title: l10n.micGateRestartAlertTitle,
      body: l10n.micGateRestartAlertBody,
      confirmLabel: l10n.micGateRestartAlertConfirm,
    );
  }

  /// Whether the current user's resolved after-transcription action
  /// actually injects keystrokes. The one predicate all three proactive
  /// Auto-Paste surfaces (startup gate, restart watch, TCC-reset notice)
  /// share — see [afterTranscriptionActionPastes]. Unloaded settings count
  /// as "doesn't paste": the factory default is clipboard-only, and a
  /// permission dialog must never fire on a guess.
  bool _userPastesAfterTranscription() {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return false;
    return afterTranscriptionActionPastes(settings.afterTranscriptionAction);
  }

  /// Collapses settings + capability state into the gate's Auto-Paste view.
  /// Users whose after-transcription action never pastes (clipboard-only /
  /// nothing) are deliberately not nagged about a permission they don't use.
  Future<AutoPasteGateStatus> _readAutoPasteGateStatus() async {
    if (!_userPastesAfterTranscription()) return AutoPasteGateStatus.notNeeded;

    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    var capability = ref.read(pasteCapabilityNotifierProvider).capability;
    if (capability == null) {
      // Normally _maybeShowTccResetNotice has already probed; this is the
      // fallback for an early-failed probe.
      await notifier.hydrateRestartMarker();
      await notifier.check();
      capability = ref.read(pasteCapabilityNotifierProvider).capability;
    }
    if (capability?.status != PasteCapabilityStatus.permissionMissing) {
      return AutoPasteGateStatus.notNeeded;
    }
    if (notifier.restartWasIneffective) {
      return AutoPasteGateStatus.missingAfterIneffectiveRestart;
    }
    // `grantRequiresEntryReset` is the live-probe (Developer-ID / ad-hoc)
    // build — the one where the grant handoff calls
    // `AXIsProcessTrustedWithOptions(prompt:)` and macOS therefore raises its
    // own Accessibility alert. Our pre-alert would be that same question
    // twice. The cached-probe (MAS) build keeps its own alert: only
    // `CGRequestPostEventAccess()` runs there, and that its dialog appears is
    // not verified on this machine.
    return notifier.grantRequiresEntryReset
        ? AutoPasteGateStatus.missingWithOsPrompt
        : AutoPasteGateStatus.missing;
  }

  /// Returns whether the user confirmed; decline or dispatch failure abort
  /// the grant flow (no Settings pane, no polling, no restart chain).
  Future<bool> _showAutoPasteGateGrantAlert() async {
    if (!mounted) return false;
    final l10n = L10n.of(context);
    final choice = Completer<bool>();
    final dispatched = await MacOSLifecycleChannel.showPermissionGrantAlert(
      id: 'autopaste_gate',
      title: l10n.autoPasteGateAlertTitle,
      body: l10n.autoPasteGateAlertBody,
      confirmLabel: l10n.autoPasteGateAlertConfirm,
      cancelLabel: l10n.permissionAlertLaterButton,
      onDismiss: choice.complete,
    );
    if (!dispatched) return false;
    return choice.future;
  }

  /// The gate's grant handoff. Splits on the same predicate as
  /// [_readAutoPasteGateStatus] so the "who shows the dialog" decision and the
  /// "how do we hand off" decision can never drift apart:
  ///
  /// * live-probe build (Developer-ID / ad-hoc) → [repairAndRequestGrant], the
  ///   repair-aware pendant of [_grantAccessibilityFromNotice]. A bare
  ///   `requestGrant()` would send the user to a Settings row that is already
  ///   switched on (live-reported dead end, verified: `repairTccEntries` never
  ///   appeared in the native log).
  /// * cached-probe build (MAS) → [requestGrant], deliberately unchanged. It
  ///   writes `sentToOsGrantFlow` + `awaitingGrant` in one atomic step and arms
  ///   the poll; `openAccessibilitySettings()` sets only the handoff bit, which
  ///   the already-armed restart watch would read as "restart required" before
  ///   the user has even reached System Settings.
  Future<void> _startAutoPasteGateGrantFlow() {
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    return notifier.grantRequiresEntryReset
        ? notifier.repairAndRequestGrant()
        : notifier.requestGrant();
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _telemetryFlushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _windowSaveTimer?.cancel();
    _restartWatchSub?.close();
    _historyWarmupSub?.close();
    _autosaveScheduler?.dispose();
    for (final subscription in _autosaveSubs) {
      subscription.close();
    }
    _autosaveSubs.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Flush on background/suspend so telemetry is not lost when the OS
    // reclaims the app without reaching the window-close handler (logout,
    // lid-close, switch-user). On desktop `detached`/`hidden` fire late but
    // are still worth a best-effort drain.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_drainAndFlushTelemetry());
    }
  }

  /// Debounced save to avoid excessive DB writes during drag/resize.
  void _debounceSaveWindowState() {
    _windowSaveTimer?.cancel();
    _windowSaveTimer = Timer(const Duration(milliseconds: 400), () async {
      final current = ref.read(settingsProvider).value;
      if (current == null || !shouldPersistWindowGeometry(current)) {
        // Unfinished onboarding: this resize/move belongs to the fixed
        // onboarding window, not the user's regular geometry — see
        // `desktop_window_geometry.dart`.
        return;
      }
      if (_isMaximized) {
        // Only persist the maximized flag; keep pre-maximize geometry.
        ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(windowMaximized: true));
        return;
      }
      final bounds = await windowManager.getBounds();
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              windowX: bounds.left,
              windowY: bounds.top,
              windowWidth: bounds.width,
              windowHeight: bounds.height,
              windowMaximized: false,
            ),
          );
    });
  }

  /// Puts the OS window back on the user's regular geometry the moment
  /// onboarding completes — the persisted values themselves never moved
  /// during onboarding (see `_debounceSaveWindowState`'s guard), so this is
  /// just re-applying them to a window that has been sitting at the fixed
  /// onboarding size.
  Future<void> _restoreRegularWindowGeometry(AppSettings settings) async {
    final geometry = resolveDesktopWindowGeometry(settings);
    await windowManager.setSize(geometry.size);
    final position = geometry.position;
    if (position != null) {
      final displays = await currentDisplayBounds();
      final clamped = WindowPositionClamp.clamp(
        position: position,
        size: geometry.size,
        displays: displays,
      );
      await windowManager.setPosition(clamped);
    } else {
      // No regular position was ever persisted (fresh install) — the window
      // has been sitting wherever the onboarding session left it, so it
      // needs an explicit re-center instead of `main.dart`'s `center: true`
      // WindowOptions, which only applies at window creation.
      await windowManager.center();
    }
    if (geometry.maximized) {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowMoved() => _debounceSaveWindowState();

  @override
  void onWindowResized() => _debounceSaveWindowState();

  @override
  void onWindowMaximize() {
    _isMaximized = true;
    _debounceSaveWindowState();
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    _debounceSaveWindowState();
  }

  @override
  void onWindowClose() async {
    if (shouldHideToTrayOnClose(
      ref.read(settingsProvider).value,
      onboardingRevisionRunning: ref.read(onboardingRevisionRunProvider),
    )) {
      // Just hide — the engine keeps running so floating windows, hotkeys,
      // and recording all continue to work.
      await windowManager.hide();

      // On macOS, hide from Dock only when the tray icon is available.
      // Without a working tray icon the user would be stranded.
      final trayReady = ref.read(trayServiceProvider.notifier).isInitialized;
      if (Platform.isMacOS && trayReady) {
        unawaited(MacOSLifecycleChannel.setAccessory());
      }
      return;
    }

    // User opted for "close = quit": run the same graceful engine teardown
    // as the native applicationShouldTerminate path (Cmd+Q / Dock Quit —
    // see graceful_shutdown.dart) before destroying the window.
    await runGracefulEngineShutdown(ProviderScope.containerOf(context));

    await windowManager.destroy();
  }

  @override
  void onWindowFocus() {
    // The user has just returned to WhisPaste — the common case being "came
    // back from System Settings after (maybe) flipping the Accessibility
    // switch". Re-probe the Auto-Paste capability so the grant resolves the
    // moment they return, rather than only on the next recording or a poll
    // timeout. Proactively surfacing the correct grant-vs-restart action here
    // is what keeps every entry point in lock-step. macOS-only: it's the sole
    // platform with a TCC gate on keystroke injection.
    if (Platform.isMacOS && kAutoPasteSupported) {
      unawaited(
        ref
            .read(pasteCapabilityNotifierProvider.notifier)
            .recheckOnForeground(),
      );
    }

    // Same "back from System Settings" moment for the microphone permission,
    // but only while onboarding is still running: page 1 shows the mic
    // permission chip, and a side-effect-free check() promotes it to "ready"
    // the instant the user returns after granting outside the app — no poll
    // tick, no restart. All platforms (the check never prompts). Outside
    // onboarding no chip consumes the status, so skip the probe entirely.
    final settings = ref.read(settingsProvider).value;
    if (settings != null && !settings.onboarding.onboardingCompleted) {
      unawaited(ref.read(micPermissionNotifierProvider.notifier).check());
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePage = ref.watch(activePageProvider);
    final recordingPhase = ref.watch(recordingPhaseProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final onboardingRevisionRunning = ref.watch(onboardingRevisionRunProvider);
    final resolvedAfterAction = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
    );

    final l10n = L10n.of(context);
    final navItems = wpNavItems(l10n);
    final sttStatus = ref.watch(localSttBundleProvider);
    final isParakeetEngine = settings.onDeviceEngine == OnDeviceEngine.parakeet;
    final parakeetStatus = isParakeetEngine
        ? ref.watch(parakeetEngineProvider)
        : null;
    final statusBarSttState = parakeetStatus != null
        ? _sttServerStateFor(parakeetStatus.state)
        : sttStatus.serverState;
    // Parakeet has no GPU backend at all (CPU-only, see its `aboutParakeetDesc`
    // copy) — the indicator only earns its keep for the local Whisper engine,
    // where "GPU or CPU?" is an actual question with two possible answers.
    //
    // A live GPU→CPU fallback (`cpuFallbackActive`) always earns this chip
    // regardless of `showBackendUtilization` — that setting is about
    // interface chrome for interested users, but a degraded-mode signal
    // ("your transcription may sound different right now") is exactly the
    // kind of thing users hit by the transcription-quality-under-load
    // feedback should be able to see without first discovering and
    // enabling a settings toggle. The one-time toast
    // (`recording_behavior.dart`) still fires the moment the fallback
    // starts; this chip covers everything after that moment for the rest
    // of the process's lifetime.
    final sttBackendKind = parakeetStatus == null
        ? (settings.interface_.showBackendUtilization ||
                  sttStatus.cpuFallbackActive
              ? _sttBackendKind(sttStatus.backend)
              : null)
        : null;
    final statusBarModel = buildStatusBarModel(settings: settings, l10n: l10n);
    final updateState = ref.watch(updateProvider);
    final deployChannel = ref.watch(deployChannelProvider);

    // Microphone quick-switch chip — mirror the tray submenu: hidden when
    // only the default pseudo-device was enumerated (nothing to switch to).
    final micDevices =
        ref.watch(audioInputDevicesProvider).value ?? const [micDefaultLabel];
    final currentMic = settings.audioInput.microphone;
    final micOptions = micDevices.length > 1
        ? buildMicrophoneOptions(
            deviceLabels: micDevices,
            selectedLabel: currentMic,
          )
        : null;

    const contentRadius = BorderRadius.only(
      topLeft: Radius.circular(WpRadius.xl),
      bottomLeft: Radius.circular(WpRadius.xl),
    );

    // Content panel uses a warm gradient for depth (both themes)
    const contentDecoration = BoxDecoration(
      gradient: WpColors.warmSurfaceGradient,
      borderRadius: contentRadius,
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+, / Cmd+,: jump to Settings — the platform-standard
        // "Preferences" shortcut, so it's always reachable regardless of
        // which page currently has focus.
        SingleActivator(
          LogicalKeyboardKey.comma,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () =>
            ref.read(activePageProvider.notifier).setPage('settings'),
      },
      child: WpReviewPromptWatcher(
        child: WpSupportPromptWatcher(
          child: WpStoreThankYouWatcher(
            child: WpFeatureSpotlightWatcher(
              child: SmartModeUsageHintWatcher(
                child: WpServiceBootstrap(
                  child: WpRecordingBehavior(
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Stack(
                        children: [
                          // The frame — one diagonal ambient for title bar, nav
                          // rail and status bar together, painted here and
                          // nowhere else. None of the three bars carries a ground
                          // of its own (gated in frame_single_paint_test.dart):
                          // a flat fill on one strip would cut a seam across a
                          // gradient that has to read as a single light source.
                          // Any future depth belongs *inside* this DecoratedBox,
                          // never as a second layer above it — see *The
                          // One-Atmosphere Rule*.
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: WpColors.frameGradient,
                            ),
                            child: SizedBox.expand(),
                          ),
                          // Main layout
                          Column(
                            children: [
                              const WpTitleBar(),
                              Expanded(
                                child: Row(
                                  children: [
                                    WpSidebar(
                                      items: navItems,
                                      dividerAfterIds: wpNavDividerAfterIds,
                                      activeId: activePage,
                                      onItemTap: (id) {
                                        ref
                                            .read(activePageProvider.notifier)
                                            .setPage(id);
                                      },
                                      bottomItems: [
                                        // Attention dot on the gear whenever a
                                        // newer version is waiting — reuses the
                                        // existing `updateProvider` phase rather
                                        // than tracking a second "seen" state,
                                        // and reuses the sentence the status bar
                                        // already shows so the dot is never a
                                        // bare, unexplained mark.
                                        wpSettingsNavItem(
                                          l10n,
                                          badgeHint:
                                              updateState.phase ==
                                                  UpdatePhase.available
                                              ? l10n.updateAvailable(
                                                  updateState.latestVersion ??
                                                      '',
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                    // Content area — rounded panel with warm gradient
                                    Expanded(
                                      child: Container(
                                        decoration: contentDecoration,
                                        clipBehavior: Clip.antiAlias,
                                        child: Column(
                                          children: [
                                            // Recording indicator — thin pulsing bar
                                            WpRecordingIndicatorBar(
                                              phase: recordingPhase,
                                            ),
                                            // Page header with smooth title transition
                                            AnimatedSwitcher(
                                              duration: WpMotion.durationFor(
                                                context,
                                                WpMotion.fast,
                                              ),
                                              child: _PageHeader(
                                                key: ValueKey(
                                                  'header-$activePage',
                                                ),
                                                title: wpPageTitle(
                                                  activePage,
                                                  navItems,
                                                  l10n,
                                                ),
                                              ),
                                            ),
                                            // Content with page transition animation
                                            Expanded(
                                              child: AnimatedSwitcher(
                                                duration: WpMotion.durationFor(
                                                  context,
                                                  WpMotion.normal,
                                                ),
                                                switchInCurve:
                                                    WpMotion.defaultCurve,
                                                switchOutCurve:
                                                    WpMotion.defaultCurve,
                                                transitionBuilder:
                                                    (child, animation) {
                                                      return FadeTransition(
                                                        opacity: animation,
                                                        child: SlideTransition(
                                                          position:
                                                              Tween<Offset>(
                                                                begin:
                                                                    const Offset(
                                                                      0.0,
                                                                      0.015,
                                                                    ),
                                                                end:
                                                                    Offset.zero,
                                                              ).animate(
                                                                animation,
                                                              ),
                                                          child: child,
                                                        ),
                                                      );
                                                    },
                                                child: KeyedSubtree(
                                                  key: ValueKey(activePage),
                                                  child:
                                                      wpPageWidgets[activePage] ??
                                                      const SizedBox.shrink(),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Status bar — sits on the frame, full width.
                              //
                              // `backendUtilizationPercent` alone is wrapped in a
                              // `Consumer`: `backendUtilizationProvider` ticks
                              // every ~3 s (see backend_utilization_notifier.dart),
                              // and watching it directly in this method's `build`
                              // would rebuild the entire app shell — nav rail,
                              // active page, animations — on every tick for a
                              // value only this one status-bar chip renders. The
                              // `.select` narrows it further to just the field
                              // this chip actually reads, so only this `Consumer`
                              // rebuilds each tick.
                              Consumer(
                                builder: (context, ref, child) {
                                  final backendUtilizationPercent = ref.watch(
                                    backendUtilizationProvider.select(
                                      (s) => s.cpuPercent,
                                    ),
                                  );
                                  return WpStatusBar(
                                    sttModeLabel: statusBarModel.sttModeLabel,
                                    sttState: statusBarSttState,
                                    backendKind: sttBackendKind,
                                    backendUtilizationPercent:
                                        backendUtilizationPercent,
                                    // Parakeet has no starting-since timestamp (no
                                    // "warming up" phase to time) — the status bar
                                    // simply shows no elapsed-time hint for it.
                                    sttStartingSince: parakeetStatus != null
                                        ? null
                                        : sttStatus.startingSince,
                                    recordingPhase: recordingPhase,
                                    afterActionLabel:
                                        afterTranscriptionStatusLabel(
                                          resolvedAfterAction,
                                          l10n,
                                        ),
                                    afterAction: resolvedAfterAction,
                                    microphoneLabel: currentMic,
                                    microphoneOptions: micOptions,
                                    onMicrophoneChanged: (label) {
                                      unawaited(
                                        ref
                                            .read(
                                              microphoneSelectionServiceProvider,
                                            )
                                            .select(label),
                                      );
                                    },
                                    onMicrophoneMenuOpened: () => ref
                                        .invalidate(audioInputDevicesProvider),
                                    hotkeyLabel: formatHotkeyShortcut(
                                      settings.hotkeyModifiers,
                                      settings.hotkeyKey,
                                      l10n: l10n,
                                      displayOverride:
                                          settings.hotkey.hotkeyKeyDisplay,
                                    ),
                                    hotkeyEnabled: settings.hotkeyEnabled,
                                    updateVersion:
                                        updateState.phase ==
                                            UpdatePhase.available
                                        ? updateState.latestVersion
                                        : null,
                                    updateReadyToInstall:
                                        updateState.phase ==
                                        UpdatePhase.readyToInstall,
                                    showAutoPasteOffHint:
                                        shouldShowAutoPasteOffHint(
                                          afterAction: resolvedAfterAction,
                                          onboardingCompleted: settings
                                              .onboarding
                                              .onboardingCompleted,
                                          autoPasteOffHintDismissed: settings
                                              .onboarding
                                              .autoPasteOffHintDismissed,
                                        ),
                                    onAutoPasteOffHintTap: () {
                                      ref
                                          .read(
                                            settingsScrollTargetProvider
                                                .notifier,
                                          )
                                          .set('afterTranscription');
                                      ref
                                          .read(activePageProvider.notifier)
                                          .setPage('settings');
                                    },
                                    onAutoPasteOffHintDismiss: () {
                                      ref
                                          .read(settingsProvider.notifier)
                                          .updateSettings(
                                            (s) => s.copyWithSections(
                                              onboarding: s.onboarding.copyWith(
                                                autoPasteOffHintDismissed: true,
                                              ),
                                            ),
                                          );
                                    },
                                    onHotkeyTap: () {
                                      ref
                                          .read(
                                            settingsScrollTargetProvider
                                                .notifier,
                                          )
                                          .set('hotkey');
                                      ref
                                          .read(activePageProvider.notifier)
                                          .setPage('settings');
                                    },
                                    onSttTap: () {
                                      ref
                                          .read(
                                            settingsScrollTargetProvider
                                                .notifier,
                                          )
                                          .set('stt');
                                      ref
                                          .read(activePageProvider.notifier)
                                          .setPage('settings');
                                    },
                                    onAfterActionChanged: (action) {
                                      ref
                                          .read(settingsProvider.notifier)
                                          .updateSettings(
                                            (s) => s.copyWith(
                                              afterTranscription: action.value,
                                            ),
                                          );
                                    },
                                    onUpdateTap: () => triggerUpdateAction(
                                      ref: ref,
                                      updateState: updateState,
                                      channel: deployChannel,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          // Onboarding overlay — the first launch, a review the
                          // user reopened from Settings, or an onboarding
                          // revision run (`.scratch/onboarding-revisions/
                          // issues/03`). `onboardingCompleted` alone no longer
                          // decides which of the latter two it is — both start
                          // with setup already done — so the ephemeral revision
                          // flag breaks the tie; the two are mutually exclusive
                          // by construction (see `OnboardingOverlay.revisionRun`).
                          if (ref.watch(onboardingSurfaceActiveProvider))
                            Positioned.fill(
                              child: OnboardingOverlay(
                                manualReview:
                                    settings.onboarding.onboardingCompleted &&
                                    !onboardingRevisionRunning,
                                revisionRun: onboardingRevisionRunning,
                              ),
                            ),
                        ],
                      ),
                    ), // Scaffold
                  ), // WpRecordingBehavior
                ), // WpServiceBootstrap
              ), // SmartModeUsageHintWatcher
            ), // WpFeatureSpotlightWatcher
          ), // WpStoreThankYouWatcher
        ), // WpSupportPromptWatcher
      ), // WpReviewPromptWatcher
    ); // CallbackShortcuts
  }
}

/// Page header — displays the active page title with clean styling.
class _PageHeader extends StatelessWidget {
  const _PageHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.lg,
        WpSpacing.xl,
        WpSpacing.xs,
      ),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
        ],
      ),
    );
  }
}

/// Thin animated bar at the top of the content panel.
///
/// Re-exported from [WpRecordingIndicatorBar] (lib/widgets/recording_indicator_bar.dart).
/// Kept as a comment anchor for git-blame readability.
