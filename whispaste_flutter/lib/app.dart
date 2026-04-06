import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import 'features/recording/recording_state.dart';
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

final activePageProvider =
    NotifierProvider<_ActivePageNotifier, String>(_ActivePageNotifier.new);

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
    default:
      return errorCode; // Pass through unknown errors as-is
  }
}

/// Navigation items — built from localized strings.
List<WpNavItem> _navItems(L10n l10n) => [
  WpNavItem(id: 'history', icon: LucideIcons.clock3, label: l10n.navHistory),
  WpNavItem(id: 'replacements', icon: LucideIcons.replace, label: l10n.navReplacements),
  WpNavItem(id: 'analytics', icon: LucideIcons.chartNoAxesColumn, label: l10n.navAnalytics),
  WpNavItem(id: 'about', icon: LucideIcons.info, label: l10n.navAbout),
  WpNavItem(id: 'feedback', icon: LucideIcons.messageSquare, label: l10n.navFeedback),
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
class _AppShell extends ConsumerWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePage = ref.watch(activePageProvider);
    final recordingPhase = ref.watch(recordingPhaseProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final navItems = _navItems(l10n);
    final sttStatus = ref.watch(sttServiceProvider);

    // Eagerly initialise the recording orchestrator so that the STT server
    // prewarm fires at app startup — not when the user first taps record.
    ref.watch(recordingOrchestratorProvider);

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

    // Show error/success feedback via toast when recording state changes.
    // Also triggers sound feedback for start / stop / complete / error.
    // Also updates the system tray menu.
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      tray.updateRecordingState(next);
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
          if (ref.read(recordingProvider).isError) {
            ref.read(recordingOrchestratorProvider.notifier).reset();
          }
        });
      } else if (next.isRecording && (prev == null || !prev.isRecording)) {
        ref.read(soundFeedbackProvider.notifier).playRecordStart();
      } else if (next.isTranscribing && (prev == null || !prev.isTranscribing)) {
        ref.read(soundFeedbackProvider.notifier).playRecordStop();
      } else if (next.isDone && next.transcript != null) {
        ref.read(soundFeedbackProvider.notifier).playTranscriptionComplete();
        WpToast.show(
          context,
          message:
              '${l10n.statusTranscriptionDone} — ${next.transcript!.length > 80 ? '${next.transcript!.substring(0, 80)}…' : next.transcript!}',
          type: WpToastType.success,
        );
        // Auto-reset after a short delay so the FAB returns to idle.
        Future.delayed(const Duration(seconds: 2), () {
          ref.read(recordingOrchestratorProvider.notifier).reset();
        });
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
                        onTap: () => ref.read(activePageProvider.notifier).setPage('settings'),
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
                                child: _pageWidgets[activePage] ??
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
              modeLabel: settings.sttProvider == 'On Device (Private)'
                  ? l10n.statusBarOnDevice
                  : settings.sttProvider,
              postProcessingLabel: settings.postProcessEnabled
                  ? l10n.statusBarPostProcessing
                  : l10n.settingsOff,
              hotkeyLabel: 'Ctrl+Shift+R',
              isOnline: true,
              sttState: sttStatus.serverState,
            ),
          ],
        ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: WpLayout.statusBarHeight + 8, right: 8),
        child: WpRecordingFab(
          phase: recordingPhase,
          onPressed: () {
            ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
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
    final mutedColor = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
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
  const _SidebarSettingsButton({
    required this.isActive,
    required this.onTap,
  });

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
                    child: Icon(LucideIcons.settings, color: iconColor, size: 21),
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
    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(_RecordingIndicatorBar old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase) _syncPulse();
  }

  void _syncPulse() {
    if (widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing) {
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
    final isActive = widget.phase == RecordingPhase.recording ||
        widget.phase == RecordingPhase.transcribing;

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
