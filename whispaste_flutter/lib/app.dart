import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

/// Navigation items — built from localized strings.
List<WpNavItem> _navItems(L10n l10n) => [
  WpNavItem(id: 'history', icon: LucideIcons.clock3, label: l10n.navHistory),
  WpNavItem(id: 'settings', icon: LucideIcons.settings, label: l10n.navSettings),
  WpNavItem(id: 'replacements', icon: LucideIcons.replace, label: l10n.navReplacements),
  WpNavItem(id: 'analytics', icon: LucideIcons.chartNoAxesColumn, label: l10n.navAnalytics),
  WpNavItem(id: 'about', icon: LucideIcons.info, label: l10n.navAbout),
  WpNavItem(id: 'feedback', icon: LucideIcons.messageSquare, label: l10n.navFeedback),
];

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
    final isRecording = ref.watch(isRecordingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final navItems = _navItems(l10n);

    const contentRadius = BorderRadius.only(
      topLeft: Radius.circular(WpRadius.xl),
      bottomLeft: Radius.circular(WpRadius.xl),
    );

    // Content panel uses a warm gradient for depth
    final contentDecoration = BoxDecoration(
      gradient: isDark ? WpColorsDark.warmSurfaceGradient : null,
      color: isDark ? null : WpColorsLight.surface,
      borderRadius: contentRadius,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Frame background
          DecoratedBox(
            decoration: BoxDecoration(
              color:
                  isDark ? WpColorsDark.background : WpColorsLight.background,
            ),
            child: const SizedBox.expand(),
          ),
          // Subtle topographic watermark pattern
          if (isDark) const Positioned.fill(child: _FrameWatermark()),
          // Main layout
          Column(
            children: [
              const WpTitleBar(),
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
                      _ThemeToggle(),
                    ],
                  ),
                  // Content area — rounded panel with warm gradient
                  Expanded(
                    child: Container(
                      decoration: contentDecoration,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          // Page header with smooth title transition
                          AnimatedSwitcher(
                            duration: WpMotion.fast,
                            child: _PageHeader(
                              key: ValueKey('header-$activePage'),
                              title: navItems
                                  .firstWhere((n) => n.id == activePage)
                                  .label,
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
            const WpStatusBar(
              modeLabel: 'On device',
              postProcessingLabel: 'Text enhancement',
              hotkeyLabel: 'Ctrl+Shift+R',
              isOnline: true,
            ),
          ],
        ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: WpLayout.statusBarHeight + 8, right: 8),
        child: WpRecordingFab(
          isRecording: isRecording,
          onPressed: () {
            final notifier = ref.read(recordingProvider.notifier);
            if (isRecording) {
              notifier.stopRecording();
            } else {
              notifier.reset();
              notifier.startRecording();
            }
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

/// Sidebar theme toggle — cycles dark ↔ light with a single tap.
class _ThemeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(isDarkModeProvider);
    return IconButton(
      icon: Icon(
        isDark ? LucideIcons.moon : LucideIcons.sun,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        size: 20,
      ),
      tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      onPressed: () => ref.read(themeModeProvider.notifier).toggleDarkLight(),
    );
  }
}

/// Subtle topographic contour watermark painted on the dark frame.
///
/// Draws faint concentric arcs offset to the bottom-right, evoking a
/// premium dashboard / gaming-launcher feel without competing with
/// content. Opacity kept at ≈ 3% so it's FELT, not SEEN.
class _FrameWatermark extends StatelessWidget {
  const _FrameWatermark();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TopoPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _TopoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x08FFFFFF); // ~3% white

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
