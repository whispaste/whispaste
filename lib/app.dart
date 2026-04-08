import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import 'core/config/settings_enums.dart';
import 'core/config/settings_labels.dart';
import 'core/config/settings_provider.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_provider.dart';
import 'core/theme/theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/colors.dart';
import 'core/theme/tokens.dart';
import 'widgets/sidebar.dart';
import 'widgets/status_bar.dart';
import 'widgets/fab.dart';
import 'widgets/title_bar.dart';
import 'features/history/history_page.dart';
import 'features/settings/settings_page.dart';
import 'features/replacements/replacements_page.dart';
import 'features/analytics/analytics_page.dart';
import 'features/about/about_page.dart';
import 'features/feedback/feedback_page.dart';
import 'features/onboarding/onboarding_overlay.dart';
import 'features/recording/recording_overlay.dart';
import 'core/recording/recording_state.dart';
import 'core/data/database.dart';
import 'core/logging/crash_reporter.dart';
import 'core/logging/app_logger.dart';
import 'services/multi_window_service.dart';
import 'services/recording_orchestrator.dart';
import 'services/sound_feedback_service.dart';
import 'services/stt_service.dart';
import 'services/tray_service.dart';
import 'services/hotkey_service.dart';
import 'services/autostart_service.dart';
import 'widgets/toast.dart';

/// Active navigation page state (Riverpod 3.x Notifier).
class _ActivePageNotifier extends Notifier<String> {
  @override
  String build() => 'history';

  void setPage(String id) => state = id;
}

final activePageProvider = NotifierProvider<_ActivePageNotifier, String>(
  _ActivePageNotifier.new,
);

/// Optional settings section to scroll to after navigating to Settings.
/// Set before calling setPage('settings') — SettingsPage consumes & clears it.
class _SettingsScrollTarget extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

final settingsScrollTargetProvider =
    NotifierProvider<_SettingsScrollTarget, String?>(
  _SettingsScrollTarget.new,
);

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
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const _AppShell(),
    );
  }
}

/// Maps error codes from the recording orchestrator to localized messages.
String _localizeError(L10n l10n, String errorCode) {
  switch (errorCode) {
    case 'stt_server_not_found':
      return l10n.errorSttServerNotFound;
    case 'onboarding_not_completed':
      return l10n.errorOnboardingNotCompleted;
    case 'stt_model_not_found':
      return l10n.errorSttModelNotFound;
    case 'stt_model_unknown':
      return l10n.errorSttModelUnknown;
    case 'recording_failed':
      return l10n.errorRecordingFailed;
    case 'no_audio_recorded':
      return l10n.errorNoAudioRecorded;
    case 'transcription_empty':
      return l10n.errorTranscriptionEmpty;
    case 'stt_server_failed':
      return l10n.errorSttServerFailed;
    case 'recording_guard_failed':
      return l10n.recordingGuardFailed;
    case 'recording_auto_stopped':
      return l10n.recordingAutoStopped;
    case 'pipeline_timeout':
      return l10n.errorPipelineTimeout;
    case 'wav_file_not_created':
      return l10n.errorWavFileNotCreated;
    case 'wav_file_empty':
      return l10n.errorWavFileEmpty;
    case 'stt_start_timeout':
      return l10n.errorSttStartTimeout;
    case 'transcription_timeout':
      return l10n.errorTranscriptionTimeout;
    case 'mic_permission_denied':
      return l10n.errorMicPermissionDenied;
    case 'recording_start_failed':
      return l10n.errorRecordingStartFailed;
    default:
      return l10n.errorGeneric;
  }
}

/// Navigation items — built from localized strings.
List<WpNavItem> _navItems(L10n l10n) => [
  WpNavItem(id: 'history', icon: LucideIcons.clock3, label: l10n.navHistory),
  WpNavItem(
    id: 'replacements',
    icon: LucideIcons.replace,
    label: l10n.navReplacements,
  ),
  WpNavItem(
    id: 'analytics',
    icon: LucideIcons.chartNoAxesColumn,
    label: l10n.navAnalytics,
  ),
  WpNavItem(id: 'about', icon: LucideIcons.info, label: l10n.navAbout),
  WpNavItem(
    id: 'feedback',
    icon: LucideIcons.messageSquare,
    label: l10n.navFeedback,
  ),
];

/// Resolves the page title — checks nav items first, falls back for bottom-pinned pages.
String _pageTitle(String pageId, List<WpNavItem> navItems, L10n l10n) {
  for (final item in navItems) {
    if (item.id == pageId) return item.label;
  }
  if (pageId == 'settings') return l10n.navSettings;
  return '';
}

/// Map page IDs to their widgets.
const _pageWidgets = <String, Widget>{
  'history': HistoryPage(),
  'settings': SettingsPage(),
  'replacements': ReplacementsPage(),
  'analytics': AnalyticsPage(),
  'about': AboutPage(),
  'feedback': FeedbackPage(),
};

/// Root layout: title bar + sidebar + content + status bar + FAB.
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> with WindowListener {
  static final _appLog = AppLogger('AppShell');
  Timer? _windowSaveTimer;
  Timer? _doneResetTimer;
  Timer? _watchdogTimer;
  bool _isMaximized = false;
  bool _orchestratorInitialized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      windowManager.isMaximized().then((v) => _isMaximized = v);
    }
    // Watchdog: detect and auto-recover if state stuck in "done" for >15s.
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStuckDone();
    });

    // Show one-time migration toast if Go → Flutter migration happened.
    // Force a DB query first to ensure beforeOpen/migrations have completed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
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
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _windowSaveTimer?.cancel();
    _doneResetTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  DateTime? _doneEnteredAt;

  void _checkStuckDone() {
    try {
      final state = ref.read(recordingProvider);
      if (state.isDone) {
        _doneEnteredAt ??= DateTime.now();
        final stuck = DateTime.now().difference(_doneEnteredAt!);
        if (stuck.inSeconds >= 15) {
          _appLog.warning(
            'Watchdog: state stuck in done for ${stuck.inSeconds}s — force reset',
          );
          ref.read(recordingOrchestratorProvider.notifier).reset();
          _doneEnteredAt = null;
        }
      } else {
        _doneEnteredAt = null;
      }
    } catch (_) {
      // Provider may not be ready yet during startup.
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
    // Kill native subprocesses FIRST — before windows or Riverpod are torn
    // down. This is the last reliable point to prevent orphaned processes.
    try {
      ref.read(sttServiceProvider.notifier).stop();
    } catch (_) {}

    // Shut down floating windows before exiting.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await ref.read(multiWindowProvider.notifier).shutdownAll();
      } catch (_) {}
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final activePage = ref.watch(activePageProvider);
    final recordingPhase = ref.watch(recordingPhaseProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    // Sync crash reporting consent with user's settings toggle (Finding 1 fix).
    CrashReporter.instance?.consentGranted = settings.errorReporting;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final navItems = _navItems(l10n);
    final sttStatus = ref.watch(sttServiceProvider);
    final statusBarModel = buildStatusBarModel(settings: settings, l10n: l10n);

    // ── Service eager-init via ref.watch ──
    // These are keepAlive NotifierProviders (not autoDispose). Riverpod
    // creates each exactly once; subsequent builds reuse the same instance.
    // This is intentional: services need to be alive for the entire app
    // lifetime (tray icon, hotkey listener, STT prewarm, multi-window).
    // Safe despite being in build() — no re-init on rebuild.

    // Defer recording orchestrator init (and its STT prewarm) until after
    // the first frame — so the window is interactive immediately.
    if (!_orchestratorInitialized) {
      _orchestratorInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(recordingOrchestratorProvider);
      });
    } else {
      ref.watch(recordingOrchestratorProvider);
    }

    // Eagerly initialise system tray and wire callbacks.
    ref.watch(trayServiceProvider);
    final tray = ref.read(trayServiceProvider.notifier);
    tray.onToggleRecording = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };
    tray.onNavigate = (page) {
      ref.read(activePageProvider.notifier).setPage(page);
    };

    // Eagerly initialise global hotkey (Ctrl+Shift+D → toggle recording).
    ref.watch(hotkeyServiceProvider);
    ref.read(hotkeyServiceProvider.notifier).onHotkeyPressed = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };

    // Sync autostart setting with system.
    ref.watch(autostartServiceProvider);

    // Initialise multi-window service for floating button/overlay (desktop).
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      ref.watch(multiWindowProvider);
    }

    // Show error/success feedback via toast when recording state changes.
    // Also triggers sound feedback for start / stop / complete / error.
    // Also updates the system tray menu.
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      tray.updateRecordingState(next, l10n: l10n);
      if (next.isError && next.errorMessage != null) {
        ref.read(soundFeedbackProvider.notifier).playError();
        WpToast.show(
          context,
          message: _localizeError(l10n, next.errorMessage!),
          type: WpToastType.error,
          duration: const Duration(seconds: 5),
          actionLabel: l10n.actionDismiss,
          onAction: () {
            ref.read(recordingOrchestratorProvider.notifier).reset();
          },
        );
        // Auto-reset after toast display so FAB returns to idle.
        Future.delayed(const Duration(seconds: 5), () {
          try {
            if (mounted && ref.read(recordingProvider).isError) {
              _appLog.debug('Error auto-reset timer fired');
              ref.read(recordingOrchestratorProvider.notifier).reset();
            }
          } catch (e) {
            _appLog.warning('Error auto-reset failed', e);
          }
        });
      } else if (next.isRecording && (prev == null || !prev.isRecording)) {
        ref.read(soundFeedbackProvider.notifier).playRecordStart();
      } else if (next.isTranscribing &&
          (prev == null || !prev.isTranscribing)) {
        ref.read(soundFeedbackProvider.notifier).playRecordStop();
      } else if (next.isDone && next.transcript != null) {
        _appLog.debug('State → done, scheduling sound + toast + 2s reset');
        ref.read(soundFeedbackProvider.notifier).playTranscriptionComplete();
        WpToast.show(
          context,
          message:
              '${l10n.statusTranscriptionDone} — ${next.transcript!.length > 80 ? '${next.transcript!.substring(0, 80)}…' : next.transcript!}',
          type: WpToastType.success,
        );
        // Auto-reset after a short delay so the FAB returns to idle.
        _doneResetTimer?.cancel();
        _doneResetTimer = Timer(const Duration(seconds: 2), () {
          try {
            _appLog.debug('Done reset timer fired — calling reset()');
            if (mounted) {
              ref.read(recordingOrchestratorProvider.notifier).reset();
              _appLog.debug('Done reset completed');
            }
          } catch (e, st) {
            _appLog.error('Done reset timer error', e, st);
          }
        });
      } else if (next.isIdle && prev != null && !prev.isIdle) {
        _appLog.debug('State → idle (from ${prev.phase})');
        _doneResetTimer?.cancel();
      }
    });

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

    return Scaffold(
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
          Positioned.fill(child: _FrameWatermark(isDark: isDark)),
          // Main layout
          Column(
            children: [
              const WpTitleBar(actions: [_ThemeToggle()]),
              Expanded(
                child: Row(
                  children: [
                    WpSidebar(
                      items: navItems,
                      activeId: activePage,
                      onItemTap: (id) {
                        ref.read(activePageProvider.notifier).setPage(id);
                      },
                      bottomItems: [
                        _SidebarSettingsButton(
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
                            _RecordingIndicatorBar(phase: recordingPhase),
                            // Page header with smooth title transition
                            AnimatedSwitcher(
                              duration: WpMotion.fast,
                              child: _PageHeader(
                                key: ValueKey('header-$activePage'),
                                title: _pageTitle(activePage, navItems, l10n),
                              ),
                            ),
                            // Content with page transition animation
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: WpMotion.smooth,
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0.0, 0.015),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: KeyedSubtree(
                                  key: ValueKey(activePage),
                                  child:
                                      _pageWidgets[activePage] ??
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
                postProcessingLabel: statusBarModel.postProcessingLabel,
                sttState: sttStatus.serverState,
                recordingPhase: recordingPhase,
                onSttTap: () {
                  ref
                      .read(settingsScrollTargetProvider.notifier)
                      .set('stt');
                  ref.read(activePageProvider.notifier).setPage('settings');
                },
                onPostProcessTap: () {
                  ref
                      .read(settingsScrollTargetProvider.notifier)
                      .set('postprocessing');
                  ref.read(activePageProvider.notifier).setPage('settings');
                },
              ),
            ],
          ),
          // Onboarding overlay — shown on first launch
          if (!settings.onboardingCompleted)
            const Positioned.fill(child: OnboardingOverlay()),

          // Recording overlay — shown in-window when:
          //  1. overlayMode is inWindow, OR
          //  2. overlayMode is floating but the floating window isn't visible
          //     AND overlay isn't currently being created (prevents flash
          //     during async window creation).
          //  3. overlayMode is off → never show.
          if (recordingPhase != RecordingPhase.idle &&
              settings.overlayModeType == OverlayMode.inWindow)
            const Positioned(
              bottom: WpLayout.statusBarHeight + 8,
              left: 0,
              right: 0,
              child: Center(child: RecordingOverlay()),
            ),
        ],
      ),
      // Hide in-window FAB when floating button is active outside the window,
      // or during onboarding (user can't record yet).
      floatingActionButton:
          !settings.onboardingCompleted ||
          (settings.showFloatingButton &&
              ref.watch(multiWindowProvider).buttonVisible)
          ? null
          : Padding(
              padding: const EdgeInsets.only(
                bottom: WpLayout.statusBarHeight,
                right: 0,
              ),
              child: WpRecordingFab(
                phase: recordingPhase,
                onPressed: () {
                  ref
                      .read(recordingOrchestratorProvider.notifier)
                      .toggleRecording();
                },
              ),
            ),
    );
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
class _SidebarSettingsButton extends StatefulWidget {
  const _SidebarSettingsButton({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_SidebarSettingsButton> createState() => _SidebarSettingsButtonState();
}

class _SidebarSettingsButtonState extends State<_SidebarSettingsButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final Color iconColor;
    final Color bgColor;

    if (widget.isActive) {
      iconColor = isDark ? WpColorsDark.accent : WpColorsLight.accent;
      bgColor = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      iconColor = isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
      bgColor = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      iconColor = isDark ? WpColorsDark.textSecondary : WpColorsLight.textMuted;
      bgColor = isDark
          ? WpColorsDark.hoverTransparent
          : WpColorsLight.hoverTransparent;
    }

    return Semantics(
      label: l10n.navSettings,
      button: true,
      selected: widget.isActive,
      child: Tooltip(
        message: l10n.navSettings,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              width: WpLayout.sidebarWidth,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.isActive)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          gradient: isDark
                              ? WpColorsDark.accentWarmGradient
                              : WpColorsLight.accentWarmGradient,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(WpRadius.sm),
                            bottomRight: Radius.circular(WpRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  AnimatedContainer(
                    duration: WpMotion.hoverIn,
                    curve: WpMotion.defaultCurve,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(WpRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.settings,
                      color: iconColor,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin animated bar at the top of the content panel.
///
/// Pulses red during recording, amber during transcribing, hidden otherwise.
/// 3 px tall — visible but non-intrusive, signalling active recording at a
/// glance without competing with content.
class _RecordingIndicatorBar extends StatefulWidget {
  const _RecordingIndicatorBar({required this.phase});

  final RecordingPhase phase;

  @override
  State<_RecordingIndicatorBar> createState() => _RecordingIndicatorBarState();
}

class _RecordingIndicatorBarState extends State<_RecordingIndicatorBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _syncPulse();
  }

  @override
  void didUpdateWidget(_RecordingIndicatorBar old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase) _syncPulse();
  }

  void _syncPulse() {
    if (widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing ||
        widget.phase == RecordingPhase.processing) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive =
        widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing ||
        widget.phase == RecordingPhase.processing;

    final color = widget.phase == RecordingPhase.recording
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return AnimatedContainer(
      duration: WpMotion.normal,
      height: isActive ? 3.0 : 0.0,
      child: isActive
          ? AnimatedBuilder(
              animation: _opacity,
              builder: (context, _) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: _opacity.value * 0.8),
                        color.withValues(alpha: _opacity.value),
                        color.withValues(alpha: _opacity.value * 0.8),
                      ],
                    ),
                  ),
                );
              },
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Subtle topographic contour watermark painted on the frame.
///
/// Draws faint concentric arcs offset to the bottom-right, evoking a
/// premium dashboard / gaming-launcher feel without competing with
/// content. Opacity kept at ≈ 3% so it's FELT, not SEEN.
class _FrameWatermark extends StatelessWidget {
  const _FrameWatermark({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TopoPainter(isDark: isDark),
      child: const SizedBox.expand(),
    );
  }
}

class _TopoPainter extends CustomPainter {
  const _TopoPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = isDark
          ? const Color(0x08FFFFFF) // ~3% white on dark
          : WpColorsLight.watermark; // ~4% black on light

    // Origin offset to bottom-right so arcs peek from the corner
    final cx = size.width * 0.85;
    final cy = size.height * 0.9;
    final maxR = math.max(size.width, size.height) * 0.7;

    // Draw concentric elliptical arcs
    for (var r = 40.0; r < maxR; r += 55) {
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: r * 2.2,
        height: r * 1.6,
      );
      canvas.drawArc(rect, math.pi * 0.8, math.pi * 1.1, false, paint);
    }

    // Second cluster — subtle, top-left
    final cx2 = size.width * 0.12;
    final cy2 = size.height * 0.15;
    for (var r = 30.0; r < maxR * 0.4; r += 60) {
      final rect = Rect.fromCenter(
        center: Offset(cx2, cy2),
        width: r * 1.8,
        height: r * 2.0,
      );
      canvas.drawArc(rect, -math.pi * 0.3, math.pi * 0.8, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopoPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
