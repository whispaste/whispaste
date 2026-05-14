import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import 'core/config/settings_labels.dart';
import 'core/config/settings_provider.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_provider.dart';
import 'core/theme/theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/colors.dart';
import 'core/theme/tokens.dart';
import 'widgets/sidebar.dart';
import 'widgets/sidebar_settings_button.dart';
import 'widgets/status_bar.dart';
import 'widgets/fab.dart';
import 'widgets/frame_watermark.dart';
import 'widgets/recording_indicator_bar.dart';
import 'widgets/title_bar.dart';
import 'widgets/service_bootstrap.dart';
import 'widgets/recording_behavior.dart';
import 'features/history/history_page.dart';
import 'features/settings/settings_page.dart';
import 'features/replacements/replacements_page.dart';
import 'features/analytics/analytics_page.dart';
import 'features/about/about_page.dart';
import 'features/feedback/feedback_page.dart';
import 'features/onboarding/onboarding_overlay.dart';
import 'core/platform/macos_lifecycle_channel.dart';
import 'core/recording/recording_state.dart';
import 'core/data/database.dart';
import 'core/logging/crash_reporter.dart';
import 'services/recording_orchestrator.dart';
import 'services/stt/stt_bundle.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'services/deploy_channel_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/toast.dart';
import 'widgets/review_prompt_dialog.dart';

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
    NotifierProvider<_SettingsScrollTarget, String?>(_SettingsScrollTarget.new);

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

/// Navigation items — built from localized strings.
///
/// Public so the screenshot integration test can build an identical sidebar.
List<WpNavItem> wpNavItems(L10n l10n) => [
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

/// Resolves the page title — checks nav items first, falls back for
/// bottom-pinned pages (e.g. Settings).
String wpPageTitle(String pageId, List<WpNavItem> navItems, L10n l10n) {
  for (final item in navItems) {
    if (item.id == pageId) return item.label;
  }
  if (pageId == 'settings') return l10n.navSettings;
  return '';
}

/// Map page IDs to their widgets.
const wpPageWidgets = <String, Widget>{
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
  Timer? _windowSaveTimer;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      windowManager.isMaximized().then((v) => _isMaximized = v);
    }

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
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _windowSaveTimer?.cancel();
    super.dispose();
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

    // User opted for "close = quit": kill subprocesses then destroy.
    try {
      ref.read(localSttBundleProvider.notifier).stop();
    } catch (_) {}

    try {
      await ref
          .read(historyDatabaseProvider)
          .close()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final activePage = ref.watch(activePageProvider);
    final recordingPhase = ref.watch(recordingPhaseProvider);
    final readiness = ref.watch(recordingReadinessProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final navItems = wpNavItems(l10n);
    final sttStatus = ref.watch(localSttBundleProvider);
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

    return ReviewPromptWatcher(
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
                            activeId: activePage,
                            onItemTap: (id) {
                              ref.read(activePageProvider.notifier).setPage(id);
                            },
                            bottomItems: [
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
                                    duration: WpMotion.fast,
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
                      sttState: sttStatus.serverState,
                      sttStartingSince: sttStatus.startingSince,
                      recordingPhase: recordingPhase,
                      afterActionLabel: afterTranscriptionStatusLabel(
                        settings.afterTranscriptionAction,
                        l10n,
                      ),
                      afterAction: settings.afterTranscriptionAction,
                      hotkeyLabel: formatHotkeyShortcut(
                        settings.hotkeyModifiers,
                        settings.hotkeyKey,
                        l10n: l10n,
                        displayOverride: settings.hotkey.hotkeyKeyDisplay,
                      ),
                      hotkeyEnabled: settings.hotkeyEnabled,
                      updateVersion: updateState.phase == UpdatePhase.available
                          ? updateState.latestVersion
                          : null,
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
                              (s) =>
                                  s.copyWith(afterTranscription: action.value),
                            );
                      },
                      onUpdateTap: () {
                        if (deployChannel == DeployChannel.portable) {
                          final url = updateState.releaseNotesUrl;
                          if (url != null) launchUrl(Uri.parse(url));
                        } else {
                          ref.read(updateProvider.notifier).downloadUpdate();
                        }
                      },
                    ),
                  ],
                ),
                // Onboarding overlay — shown on first launch
                if (!settings.onboardingCompleted)
                  const Positioned.fill(child: OnboardingOverlay()),
              ],
            ),
            // Hide in-window FAB during onboarding (user can't record yet).
            floatingActionButton: !settings.onboardingCompleted
                ? null
                : Padding(
                    padding: const EdgeInsets.only(
                      bottom: WpLayout.statusBarHeight,
                      right: 0,
                    ),
                    child: WpRecordingFab(
                      phase: recordingPhase,
                      readiness: readiness,
                      onPressed: () {
                        if (readiness != RecordingReadiness.ready) {
                          // Still tappable — triggers soft preflight for info toast.
                          ref
                              .read(recordingOrchestratorProvider.notifier)
                              .toggleRecording();
                          return;
                        }
                        ref
                            .read(recordingOrchestratorProvider.notifier)
                            .toggleRecording();
                      },
                    ),
                  ),
          ), // Scaffold
        ), // RecordingBehaviorWidget
      ), // ServiceBootstrapWidget
    ); // ReviewPromptWatcher
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
