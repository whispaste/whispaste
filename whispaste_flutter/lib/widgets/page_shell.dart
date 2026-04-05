import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

/// Reusable page shell — every content page wraps in this for consistent
/// padding, scrolling, and fluid desktop-native layout.
///
/// The shell fills all available width (no max-width constraint) so content
/// scales naturally with the window. Pages that need responsive multi-column
/// layouts should use [WpAdaptiveGrid] inside.
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
      WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.xl,
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
      return SingleChildScrollView(
        padding: padding,
        child: child,
      );
    }

    // Fixed mode — wrap in Padding, child manages its own height.
    return Padding(
      padding: padding,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Adaptive grid — responsive multi-column layout for desktop
// ---------------------------------------------------------------------------

/// Lays out [children] in a responsive grid that adapts column count to the
/// available width. Desktop-native: content fills the width, no centering.
///
/// Breakpoints (configurable):
/// - Below [narrowBreak]: 1 column (stacked)
/// - [narrowBreak] – [wideBreak]: 2 columns
/// - Above [wideBreak]: [maxColumns] columns (default 3)
class WpAdaptiveGrid extends StatelessWidget {
  const WpAdaptiveGrid({
    super.key,
    required this.children,
    this.spacing = WpSpacing.md,
    this.runSpacing = WpSpacing.md,
    this.narrowBreak = 500,
    this.wideBreak = 900,
    this.maxColumns = 3,
    this.minChildWidth,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double narrowBreak;
  final double wideBreak;
  final int maxColumns;

  /// If set, overrides breakpoint logic: calculates column count from
  /// available width ÷ minChildWidth. Useful for uniform card grids.
  final double? minChildWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final int columns;
        if (minChildWidth != null) {
          columns = (width / minChildWidth!).floor().clamp(1, maxColumns);
        } else if (width < narrowBreak) {
          columns = 1;
        } else if (width < wideBreak) {
          columns = 2;
        } else {
          columns = maxColumns;
        }

        if (columns == 1) {
          // Single column — simple stacked layout.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: runSpacing),
              ],
            ],
          );
        }

        // Multi-column — build rows.
        final rows = <Widget>[];
        for (int i = 0; i < children.length; i += columns) {
          final rowChildren = <Widget>[];
          for (int j = 0; j < columns; j++) {
            final idx = i + j;
            if (idx < children.length) {
              rowChildren.add(Expanded(child: children[idx]));
            } else {
              rowChildren.add(const Expanded(child: SizedBox.shrink()));
            }
            if (j < columns - 1) {
              rowChildren.add(SizedBox(width: spacing));
            }
          }
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowChildren,
          ));
          if (i + columns < children.length) {
            rows.add(SizedBox(height: runSpacing));
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
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
