import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme.dart';
import 'widgets/sidebar.dart';
import 'widgets/status_bar.dart';
import 'widgets/fab.dart';
import 'features/history/history_page.dart';
import 'features/settings/settings_page.dart';
import 'features/replacements/replacements_page.dart';
import 'features/analytics/analytics_page.dart';
import 'features/about/about_page.dart';
import 'features/feedback/feedback_page.dart';

/// Active navigation page state (by string id).
final activePageProvider = StateProvider<String>((ref) => 'history');

/// Recording state (will be backed by audio service later).
final isRecordingProvider = StateProvider<bool>((ref) => false);

/// Main WhisPaste application widget.
class WhisPasteApp extends ConsumerWidget {
  const WhisPasteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'WhisPaste',
      debugShowCheckedModeBanner: false,
      theme: wpLightTheme(),
      darkTheme: wpDarkTheme(),
      themeMode: ThemeMode.dark,
      home: const _AppShell(),
    );
  }
}

/// Navigation items for the sidebar.
const _navItems = [
  WpNavItem(id: 'history', icon: Icons.history_outlined, activeIcon: Icons.history_rounded, label: 'History'),
  WpNavItem(id: 'settings', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings'),
  WpNavItem(id: 'replacements', icon: Icons.find_replace_outlined, activeIcon: Icons.find_replace_rounded, label: 'Voice Shortcuts'),
  WpNavItem(id: 'analytics', icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart_rounded, label: 'Analytics'),
  WpNavItem(id: 'about', icon: Icons.info_outline_rounded, activeIcon: Icons.info_rounded, label: 'About'),
  WpNavItem(id: 'feedback', icon: Icons.feedback_outlined, activeIcon: Icons.feedback_rounded, label: 'Feedback'),
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

/// Root layout: sidebar + content area + status bar + FAB.
class _AppShell extends ConsumerWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePage = ref.watch(activePageProvider);
    final isRecording = ref.watch(isRecordingProvider);

    return Scaffold(
      body: Row(
        children: [
          // Left sidebar
          WpSidebar(
            items: _navItems,
            activeId: activePage,
            onItemTap: (id) {
              ref.read(activePageProvider.notifier).state = id;
            },
          ),
          // Content + status bar
          Expanded(
            child: Column(
              children: [
                // Content area
                Expanded(
                  child: _pageWidgets[activePage] ?? const SizedBox.shrink(),
                ),
                // Status bar
                const WpStatusBar(
                  modeLabel: 'Local',
                  postProcessingLabel: 'Post-Processing',
                  hotkeyLabel: 'Ctrl + Shift + R',
                  isOnline: true,
                ),
              ],
            ),
          ),
        ],
      ),
      // Floating action button
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 36, right: 8),
        child: WpRecordingFab(
          isRecording: isRecording,
          onPressed: () {
            ref.read(isRecordingProvider.notifier).state = !isRecording;
          },
        ),
      ),
    );
  }
}
