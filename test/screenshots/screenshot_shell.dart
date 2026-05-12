/// Static full-window shell for golden screenshot tests.
///
/// Wraps any page widget in the complete WhisPaste UI chrome — title bar,
/// navigation sidebar, content panel with rounded corners, and status bar —
/// without any platform services or window_manager calls.
///
/// Every store/website golden should use [WpScreenshotShell] so the generated
/// images show a realistic, populated app window rather than a bare page.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/app.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/brand_wordmark.dart';
import 'package:whispaste/widgets/frame_watermark.dart';
import 'package:whispaste/widgets/recording_indicator_bar.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/sidebar_settings_button.dart';
import 'package:whispaste/widgets/status_bar.dart';

/// Full-window visual shell — static, test-safe.
///
/// Renders the complete WhisPaste UI frame matching the live [_AppShell]
/// layout:
/// - Gradient frame background + topographic watermark
/// - Title bar (platform-aware: macOS traffic-light area / Windows controls)
/// - Left navigation sidebar with [activePageId] highlighted
/// - Right content panel with rounded top-left/bottom-left corners,
///   page title header, and [child] content
/// - Status bar at the bottom
///
/// Use [activePageId] to match one of the nav item IDs:
/// `history`, `replacements`, `analytics`, `about`, `feedback`, `settings`.
class WpScreenshotShell extends StatelessWidget {
  const WpScreenshotShell({
    super.key,
    required this.activePageId,
    required this.child,
  });

  final String activePageId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use theme.platform (overridden by ScreenshotDevice) so Windows-target
    // screenshots render with Windows window controls even on a macOS host.
    final platform = Theme.of(context).platform;
    final l10n = L10n.of(context);
    final navItems = wpNavItems(l10n);
    final pageTitle = wpPageTitle(activePageId, navItems, l10n);

    final contentDecoration = BoxDecoration(
      gradient: isDark
          ? WpColorsDark.warmSurfaceGradient
          : WpColorsLight.warmSurfaceGradient,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(WpRadius.xl),
        bottomLeft: Radius.circular(WpRadius.xl),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDark
              ? WpColorsDark.frameGradient
              : WpColorsLight.frameGradient,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: WpFrameWatermark(isDark: isDark)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScreenshotTitleBar(isDark: isDark, platform: platform),
                Expanded(
                  child: Row(
                    children: [
                      WpSidebar(
                        items: navItems,
                        activeId: activePageId,
                        onItemTap: (_) {},
                        bottomItems: [
                          WpSidebarSettingsButton(
                            isActive: activePageId == 'settings',
                            onTap: () {},
                          ),
                        ],
                      ),
                      Expanded(
                        child: Container(
                          decoration: contentDecoration,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const WpRecordingIndicatorBar(
                                phase: RecordingPhase.idle,
                              ),
                              _ScreenshotPageHeader(
                                title: pageTitle,
                                isDark: isDark,
                              ),
                              Expanded(child: child),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const WpStatusBar(
                  sttModeLabel: 'Whisper Large v3',
                  hotkeyLabel: 'Ctrl+Shift+D',
                  hotkeyEnabled: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Static title bar — no windowManager calls, safe for headless tests.
// ---------------------------------------------------------------------------

class _ScreenshotTitleBar extends StatelessWidget {
  const _ScreenshotTitleBar({required this.isDark, required this.platform});

  final bool isDark;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final isMacOS = platform == TargetPlatform.macOS;

    return SizedBox(
      height: WpLayout.appBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.lg),
        child: Row(
          children: [
            // macOS: traffic-light dot row (close/minimise/maximise).
            if (isMacOS)
              const _MacTrafficLights()
            else
              const SizedBox(width: WpSpacing.sm),
            const WpBrandWordmark(height: 34),
            const Spacer(),
            // Windows: static window control buttons.
            if (!isMacOS) ...[
              _StaticWindowButton(icon: LucideIcons.minus, isDark: isDark),
              _StaticWindowButton(icon: LucideIcons.square, isDark: isDark),
              _StaticWindowButton(icon: LucideIcons.x, isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// macOS traffic-light buttons (close / minimise / maximise).
// ---------------------------------------------------------------------------

class _MacTrafficLights extends StatelessWidget {
  const _MacTrafficLights();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 14, right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TrafficDot(color: Color(0xFFFF5F57)),
          SizedBox(width: 6),
          _TrafficDot(color: Color(0xFFFEBC2E)),
          SizedBox(width: 6),
          _TrafficDot(color: Color(0xFF28C840)),
        ],
      ),
    );
  }
}

class _TrafficDot extends StatelessWidget {
  const _TrafficDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ---------------------------------------------------------------------------
// Windows static title-bar buttons.
// ---------------------------------------------------------------------------

class _StaticWindowButton extends StatelessWidget {
  const _StaticWindowButton({required this.icon, required this.isDark});

  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final mutedColor = isDark
        ? WpColorsDark.textMuted.withValues(alpha: 0.5)
        : WpColorsLight.textMuted.withValues(alpha: 0.5);

    return SizedBox(
      width: 40,
      height: 32,
      child: Icon(icon, size: 15, color: mutedColor),
    );
  }
}

// ---------------------------------------------------------------------------
// Page header — matches _PageHeader in app.dart.
// ---------------------------------------------------------------------------

class _ScreenshotPageHeader extends StatelessWidget {
  const _ScreenshotPageHeader({required this.title, required this.isDark});

  final String title;
  final bool isDark;

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
