import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

/// Reusable page shell — every content page wraps in this for consistent
/// padding, scrolling, and fluid desktop-native layout.
///
/// The shell fills all available width (no max-width constraint) so content
/// scales naturally with the window. Pages that need a responsive two-panel
/// layout should use [WpTwoPanel] inside; pages that need to cap width on
/// very wide windows constrain their own content (see e.g. FeedbackPage).
///
/// Two layout modes:
/// - **Scrollable** (default): content scrolls vertically when it overflows.
///   Use for settings, analytics, about, feedback — anything with long content.
/// - **Fixed**: content fills available height without scrolling. Use for
///   pages that manage their own scroll (e.g., history with a ListView).
///
/// An optional [header] pins a strip above the content (see SettingsPage's
/// search field), which is what makes the shell usable for pages that would
/// otherwise hand-roll their own sticky row plus scroll view.
class WpPageShell extends StatelessWidget {
  const WpPageShell({
    super.key,
    required this.child,
    this.header,
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

  /// Optional sticky strip above [child] — stays put while the content
  /// scrolls. It sits outside the scroll view, so [Scrollable.ensureVisible]
  /// on content still resolves to the shell's own scrollable.
  ///
  /// Shares the shell's horizontal padding and top inset; its bottom inset is
  /// zero because the content below carries its own top padding. Using it
  /// makes the shell fill the available height, so the parent must provide a
  /// bounded one.
  final Widget? header;

  /// Outer padding around the content.
  final EdgeInsets padding;

  /// Whether content scrolls vertically (default) or fills fixed height.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = scrollable
        ? SingleChildScrollView(padding: padding, child: child)
        // Fixed mode — wrap in Padding, child manages its own height.
        : Padding(padding: padding, child: child);

    if (header == null) return body;

    return Column(
      children: [
        Padding(padding: padding.copyWith(bottom: 0), child: header),
        Expanded(child: body),
      ],
    );
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
