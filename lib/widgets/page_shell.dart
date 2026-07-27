import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

/// Reusable page shell — every content page wraps in this for consistent
/// padding, scrolling, and fluid desktop-native layout.
///
/// The shell fills all available width (no max-width constraint) so content
/// scales naturally with the window. Pages that need a responsive two-panel
/// layout should use [WpTwoPanel] inside; pages that need to cap width on
/// very wide windows constrain their own content (see e.g. FeedbackPage,
/// SettingsPage).
///
/// Two layout modes:
/// - **Scrollable** (default): content scrolls vertically when it overflows.
///   Use for settings, analytics, about, feedback — anything with long content.
/// - **Fixed**: content fills available height without scrolling. Use for
///   pages that manage their own scroll (e.g., history with a ListView).
class WpPageShell extends StatelessWidget {
  const WpPageShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      WpSpacing.xl,
      WpSpacing.sm,
      WpSpacing.xl,
      WpSpacing.xl,
    ),
    this.scrollable = true,
  });

  /// Page content.
  final Widget child;

  /// Outer padding around the content.
  final EdgeInsets padding;

  /// Whether content scrolls vertically (default) or fills fixed height.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (scrollable) {
      return SingleChildScrollView(padding: padding, child: child);
    }

    // Fixed mode — wrap in Padding, child manages its own height.
    return Padding(padding: padding, child: child);
  }
}

// ---------------------------------------------------------------------------
// Adaptive two-panel — extracted from analytics for reuse
// ---------------------------------------------------------------------------

/// Lays out [left] and [right] side-by-side on wide screens, stacked on
/// narrow screens. Commonly used for dashboard panels, detail views, etc.
class WpTwoPanel extends StatelessWidget {
  const WpTwoPanel({
    super.key,
    required this.left,
    required this.right,
    this.spacing = WpSpacing.md,
    this.breakpoint = 600,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  final Widget left;
  final Widget right;
  final double spacing;
  final double breakpoint;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              SizedBox(height: spacing),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            SizedBox(width: spacing),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }
}
