import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:record/record.dart' show AudioRecorder;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_info.dart';
import 'core/config/settings_labels.dart';
import 'core/config/settings_provider.dart';
import 'core/navigation/page_state.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_provider.dart';
import 'core/theme/theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/colors.dart';
import 'core/theme/tokens.dart';
import 'widgets/sidebar.dart';
import 'widgets/sidebar_settings_button.dart';
import 'widgets/status_bar.dart';
import 'widgets/frame_watermark.dart';
import 'widgets/recording_indicator_bar.dart';
import 'widgets/title_bar.dart';
import 'widgets/service_bootstrap.dart';
import 'widgets/recording_behavior.dart';
import 'features/history/history_page.dart';
import 'features/settings/settings_page.dart';
import 'features/replacements/replacements_page.dart';
import 'features/automations/automations_page.dart';
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
import 'services/permissions/startup_permission_gate.dart';
import 'services/single_instance_service.dart';
import 'services/graceful_shutdown.dart';
import 'services/stt/stt_bundle.dart';
import 'services/stt_parakeet/parakeet_engine_notifier.dart'
    show ParakeetEngineState, parakeetEngineProvider;
import 'services/telemetry_service.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'services/update_actions.dart';
import 'services/deploy_channel_service.dart';
import 'widgets/toast.dart';
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
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'WhisPaste',
      debugShowCheckedModeBanner: false,
      theme: wpLightTheme(),
      darkTheme: wpDarkTheme(),
      themeMode: themeMode,
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
/// 1. **Dictation tools** — History (the record of what you dictated), then
///    the trigger-phrase family in ascending power: Replacements (transform
///    text), Snippets (insert stored text), Automations (run an action).
/// 2. **Product/meta** — Analytics, Feedback, About (canonical last entry).
List<WpNavItem> wpNavItems(L10n l10n) => [
  WpNavItem(id: 'history', icon: LucideIcons.clock3, label: l10n.navHistory),
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
    id: 'automations',
    icon: LucideIcons.zap,
    label: l10n.navAutomations,
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

/// Group break between the dictation tools and the product/meta nav items —
/// single source of truth for every [WpSidebar] call site (app shell,
/// screenshot shells), so grouping stays consistent everywhere.
const Set<String> wpNavDividerAfterIds = {'automations'};

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

/// Map page IDs to their widgets.
const wpPageWidgets = <String, Widget>{
  'history': HistoryPage(),
  'settings': SettingsPage(),
  'replacements': ReplacementsPage(),
  'automations': AutomationsPage(),
  'snippets': SnippetsPage(),
  'analytics': AnalyticsPage(),
  'about': AboutPage(),
  'feedback': FeedbackPage(),
};

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
    }

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
  }

  /// Strictly ordered startup sequence for everything permission-shaped:
  /// the TCC-reset notice hydrates the restart marker and runs the first
  /// capability probe, the restart watch must be armed before any grant
  /// flow can trigger a restart, and the proactive gate runs last so it
  /// reads a settled capability state.
  Future<void> _runStartupPermissionFlows() async {
    await _maybeShowTccResetNotice();
    _setupAutoPasteRestartWatch();
    await _runStartupPermissionGate();
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
      final onboardingCompleted =
          ref.read(settingsProvider).value?.onboardingCompleted ?? false;
      // Single shared guard set (see shouldShowAutoPasteRestartSurface):
      // clipboard-only users must never see any Auto-Paste modal — the
      // permission is meaningless for them, no matter what stale state
      // (restart marker, capability probes) is lying around.
      if (!shouldShowAutoPasteRestartSurface(
        needsRestart: needsRestart,
        onboardingCompleted: onboardingCompleted,
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
    final onboardingCompleted =
        ref.read(settingsProvider).value?.onboardingCompleted ?? false;
    final shouldShow = await maybeMarkTccResetNoticeVersion(
      currentVersion: appVersion,
      onboardingCompleted: onboardingCompleted,
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
      // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; the TextButton in _ToastCard.build uses its child Text as the accessible label
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
    final onboardingCompleted =
        ref.read(settingsProvider).value?.onboardingCompleted ?? false;
    // First-run onboarding owns both permissions with its own richer UI —
    // the gate only takes over from the second start on.
    if (!onboardingCompleted) return;

    final recorder = AudioRecorder();
    try {
      final gate = StartupPermissionGate(
        mic: MicGateHooks(
          checkPermission: ({required bool request}) =>
              recorder.hasPermission(request: request),
          verifyCapture: _verifyMicCapture,
          showGrantAlert: _showMicGateGrantAlert,
          openSettings: _openMicPrivacySettings,
          showRestartAlert: _showMicGateRestartAlert,
        ),
        autoPaste: Platform.isMacOS && kAutoPasteSupported
            ? AutoPasteGateHooks(
                readStatus: _readAutoPasteGateStatus,
                showGrantAlert: _showAutoPasteGateGrantAlert,
                startGrantFlow: () => ref
                    .read(pasteCapabilityNotifierProvider.notifier)
                    .requestGrant(),
                showManualGrantAlert: _showManualGrantAlert,
              )
            : null,
      );
      await gate.run();
    } finally {
      unawaited(recorder.dispose());
    }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.micGateAlertTitle),
        content: Text(l10n.micGateAlertBodyGeneric),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.permissionAlertLaterButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.micGateAlertConfirm),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _openMicPrivacySettings() async {
    final uri = Platform.isMacOS
        ? 'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'
        : Platform.isWindows
        ? 'ms-settings:privacy-microphone'
        : null;
    if (uri == null) return;
    try {
      await launchUrl(Uri.parse(uri));
    } on Exception catch (e) {
      _log.warning('Could not open microphone privacy settings: $e');
    }
  }

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
    return notifier.restartWasIneffective
        ? AutoPasteGateStatus.missingAfterIneffectiveRestart
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

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _telemetryFlushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _windowSaveTimer?.cancel();
    _restartWatchSub?.close();
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
    final closeToTray = ref.read(settingsProvider).value?.closeToTray ?? true;

    if (closeToTray) {
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
  }

  @override
  Widget build(BuildContext context) {
    final activePage = ref.watch(activePageProvider);
    final recordingPhase = ref.watch(recordingPhaseProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final resolvedAfterAction = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
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
    final statusBarModel = buildStatusBarModel(settings: settings, l10n: l10n);
    final updateState = ref.watch(updateProvider);
    final deployChannel = ref.watch(deployChannelProvider);

    const contentRadius = BorderRadius.only(
      topLeft: Radius.circular(WpRadius.xl),
      bottomLeft: Radius.circular(WpRadius.xl),
    );

    // Content panel uses a warm gradient for depth (both themes)
    final contentDecoration = BoxDecoration(
      gradient: isDark
          ? WpColorsDark.warmSurfaceGradient
          : WpColorsLight.warmSurfaceGradient,
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
      child: ReviewPromptWatcher(
        child: SupportPromptWatcher(
          child: StoreThankYouWatcher(
            child: ServiceBootstrapWidget(
              child: RecordingBehaviorWidget(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Stack(
                    children: [
                      // Frame background — gradient for premium unified feel
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: isDark
                              ? WpColorsDark.frameGradient
                              : WpColorsLight.frameGradient,
                        ),
                        child: const SizedBox.expand(),
                      ),
                      // Subtle topographic watermark pattern (both themes)
                      Positioned.fill(child: WpFrameWatermark(isDark: isDark)),
                      // Main layout
                      Column(
                        children: [
                          const WpTitleBar(actions: [_ThemeToggle()]),
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
                                    // loam-ignore: a11y-interactive-semantics – semantics provided in WpSidebarSettingsButton.build
                                    WpSidebarSettingsButton(
                                      isActive: activePage == 'settings',
                                      onTap: () => ref
                                          .read(activePageProvider.notifier)
                                          .setPage('settings'),
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
                                            key: ValueKey('header-$activePage'),
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
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                          0.0,
                                                          0.015,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(animation),
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
                          // Status bar — sits on the frame, full width
                          WpStatusBar(
                            sttModeLabel: statusBarModel.sttModeLabel,
                            sttState: statusBarSttState,
                            // Parakeet has no starting-since timestamp (no
                            // "warming up" phase to time) — the status bar
                            // simply shows no elapsed-time hint for it.
                            sttStartingSince: parakeetStatus != null
                                ? null
                                : sttStatus.startingSince,
                            recordingPhase: recordingPhase,
                            afterActionLabel: afterTranscriptionStatusLabel(
                              resolvedAfterAction,
                              l10n,
                            ),
                            afterAction: resolvedAfterAction,
                            hotkeyLabel: formatHotkeyShortcut(
                              settings.hotkeyModifiers,
                              settings.hotkeyKey,
                              l10n: l10n,
                              displayOverride: settings.hotkey.hotkeyKeyDisplay,
                            ),
                            hotkeyEnabled: settings.hotkeyEnabled,
                            updateVersion:
                                updateState.phase == UpdatePhase.available
                                ? updateState.latestVersion
                                : null,
                            updateReadyToInstall:
                                updateState.phase == UpdatePhase.readyToInstall,
                            showAutoPasteOffHint: shouldShowAutoPasteOffHint(
                              afterAction: resolvedAfterAction,
                              onboardingCompleted:
                                  settings.onboarding.onboardingCompleted,
                              autoPasteOffHintDismissed:
                                  settings.onboarding.autoPasteOffHintDismissed,
                            ),
                            onAutoPasteOffHintTap: () {
                              ref
                                  .read(settingsScrollTargetProvider.notifier)
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
                                  .read(settingsScrollTargetProvider.notifier)
                                  .set('hotkey');
                              ref
                                  .read(activePageProvider.notifier)
                                  .setPage('settings');
                            },
                            onSttTap: () {
                              ref
                                  .read(settingsScrollTargetProvider.notifier)
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
                          ),
                        ],
                      ),
                      // Onboarding overlay — shown on first launch
                      if (!settings.onboardingCompleted)
                        const Positioned.fill(child: OnboardingOverlay()),
                    ],
                  ),
                ), // Scaffold
              ), // RecordingBehaviorWidget
            ), // ServiceBootstrapWidget
          ), // StoreThankYouWatcher
        ), // SupportPromptWatcher
      ), // ReviewPromptWatcher
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

/// Theme toggle — cycles dark ↔ light. Placed in title bar.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final mutedColor = isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;
    return IconButton(
      icon: Icon(
        isDark ? LucideIcons.moon : LucideIcons.sun,
        color: mutedColor,
        size: 16,
      ),
      tooltip: isDark ? l10n.tooltipSwitchToLight : l10n.tooltipSwitchToDark,
      onPressed: () => ref.read(settingsProvider.notifier).toggleDarkLight(),
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}

/// Settings shortcut pinned to sidebar bottom — mirrors nav item style.
///
/// Re-exported from [WpSidebarSettingsButton] (lib/widgets/sidebar_settings_button.dart).
/// Kept as a comment anchor for git-blame readability.

/// Thin animated bar at the top of the content panel.
///
/// Re-exported from [WpRecordingIndicatorBar] (lib/widgets/recording_indicator_bar.dart).
/// Kept as a comment anchor for git-blame readability.

/// Subtle topographic contour watermark painted on the frame.
///
/// Re-exported from [WpFrameWatermark] (lib/widgets/frame_watermark.dart).
/// Kept as a comment anchor for git-blame readability.
