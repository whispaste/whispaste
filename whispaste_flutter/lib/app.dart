import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

    return MaterialApp(
      title: 'WhisPaste',
      debugShowCheckedModeBanner: false,
      theme: wpLightTheme(),
      darkTheme: wpDarkTheme(),
      themeMode: themeMode,
      home: const _AppShell(),
    );
  }
}

/// Navigation items — Lucide icons, clean & thin.
const _navItems = [
  WpNavItem(id: 'history', icon: LucideIcons.clock3, label: 'History'),
  WpNavItem(id: 'settings', icon: LucideIcons.settings, label: 'Settings'),
  WpNavItem(id: 'replacements', icon: LucideIcons.replace, label: 'Voice Shortcuts'),
  WpNavItem(id: 'analytics', icon: LucideIcons.chartNoAxesColumn, label: 'Analytics'),
  WpNavItem(id: 'about', icon: LucideIcons.info, label: 'About'),
  WpNavItem(id: 'feedback', icon: LucideIcons.messageSquare, label: 'Feedback'),
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDark ? WpColorsDark.frameGradient : null,
          color: isDark ? null : WpColorsLight.background,
        ),
        child: Column(
          children: [
            const WpTitleBar(),
            Expanded(
              child: Row(
                children: [
                  WpSidebar(
                    items: _navItems,
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
                          // Page header
                          _PageHeader(
                            title: _navItems
                                .firstWhere((n) => n.id == activePage)
                                .label,
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
              modeLabel: 'Local',
              postProcessingLabel: 'Post-Processing',
              hotkeyLabel: 'Ctrl+Shift+R',
              isOnline: true,
            ),
          ],
        ),
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
  const _PageHeader({required this.title});

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
