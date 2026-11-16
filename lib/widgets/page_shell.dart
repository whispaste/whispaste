import 'package:flutter/material.dart';

import '../core/theme/generated/wp_tokens.g.dart' show WpShellTokens;
import '../core/theme/tokens.dart';

/// The one page frame every page shares (Maintainer 2026-10-30): the inset of
/// the title row, the gap from the page title to the first content, the side
/// insets and the bottom inset. The app shell paints the title with
/// [titleTop] and [inset] (its bottom edge sits [titleToContent] above the
/// content); [WpPageShell] applies the rest. Change a value here, never per page.
abstract final class WpPageFrame {
  /// Space above the page title (app shell).
  static const double titleTop = WpSpacing.lg;

  /// Gap from the bottom of the page title to the first content element.
  static const double titleToContent = WpSpacing.sm;

  /// Left and right inset of title row and content.
  static const double inset = WpSpacing.xl;

  /// Bottom inset of scrollable content.
  static const double bottom = WpSpacing.xl;
}

/// Reusable page shell — every content page wraps in this for consistent
/// padding, scrolling, and fluid desktop-native layout.
///
/// The shell fills all available width (no max-width constraint) so content
/// scales naturally with the window. Pages that need a responsive two-panel
/// layout should use [WpTwoPanel] inside; content whose lines would grow
/// unreadably long on very wide windows (forms with free text, transcripts)
/// wraps in [WpReadingWidth], never in a width of its own.
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
///
/// **No ground of its own, on purpose.** Ticket 08 put the card material on
/// the shared primitives and deliberately stopped short of this one: the shell
/// is padding and scroll behaviour, and the app has exactly one light source,
/// painted once in `app.dart`. A fill here would be a second ground under
/// every page — the One-Atmosphere Rule's failure case, and the reason
/// `settings_page.dart` already carries the same note. Cards go *inside* the
/// shell, never around it.
class WpPageShell extends StatelessWidget {
  const WpPageShell({
    super.key,
    required this.child,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(
      WpPageFrame.inset,
      WpPageFrame.titleToContent,
      WpPageFrame.inset,
      WpPageFrame.bottom,
    ),
    this.scrollable = true,
    this.bodyPadding,
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

  /// Padding around [child] when it differs from [padding]: a fixed body whose
  /// own lists carry the page inset (so their scrollbars sit at the edge)
  /// passes [EdgeInsets.zero] here and keeps the header aligned with every
  /// other page.
  final EdgeInsets? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final inset = bodyPadding ?? padding;
    final body = scrollable
        ? SingleChildScrollView(padding: inset, child: child)
        // Fixed mode — wrap in Padding, child manages its own height.
        : Padding(padding: inset, child: child);

    if (header == null) return body;

    return Column(
      children: [
        Padding(padding: padding.copyWith(bottom: 0), child: header),
        Expanded(child: body),
      ],
    );
  }
}

/// The one reading measure (#197): caps prose and free-text forms at
/// `shell.reading-measure` from `design-tokens/app.tokens.json` so lines stay
/// legible on wide windows. Narrower parents are filled as usual. Pages never
/// pick a width of their own; change the token instead.
class WpReadingWidth extends StatelessWidget {
  const WpReadingWidth({
    super.key,
    required this.child,
    this.alignment = AlignmentDirectional.topStart,
  });

  /// The capped content.
  final Widget child;

  /// Where the capped column sits when the parent is wider: at the start
  /// like every page's content, or centred for a lone confirmation.
  final AlignmentGeometry alignment;

  /// The measure in logical pixels.
  static const double measure = WpShellTokens.readingMeasure;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: measure),
      child: child,
    ),
  );
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
