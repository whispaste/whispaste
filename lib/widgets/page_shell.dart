import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/colors.dart';
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
        ? _KeyboardScrollView(padding: inset, child: child)
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

/// The scroll view of a scrollable page, operable by keyboard (#1845).
///
/// Page Up/Down and Ctrl+Home/End scroll the page while focus is anywhere in
/// it, except in a text field, which keeps those keys. A page without any
/// focusable control (Statistik) becomes one Tab stop itself, like a scroll
/// region in a browser, so the keyboard can reach it at all; focused, it also
/// takes the arrow keys, Space, Home and End. Its focus mark is the scroll
/// bar itself, shown in the accent colour while the region has keyboard
/// focus: a ring around the whole content area read as a frame around the
/// page, not as focus (hp840 retest).
class _KeyboardScrollView extends StatefulWidget {
  const _KeyboardScrollView({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  State<_KeyboardScrollView> createState() => _KeyboardScrollViewState();
}

class _KeyboardScrollViewState extends State<_KeyboardScrollView> {
  final _controller = ScrollController();
  final _region = FocusNode(debugLabel: 'page-scroll-region');

  /// Arrow-key step, the usual line step of desktop scroll views.
  static const double _lineStep = 40;

  @override
  void initState() {
    super.initState();
    _region.skipTraversal = true;
    _region.addListener(_onFocusChange);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTabStop());
  }

  @override
  void didUpdateWidget(_KeyboardScrollView old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTabStop());
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _region.removeListener(_onFocusChange);
    _controller.dispose();
    _region.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() {});

  void _onHighlightMode(FocusHighlightMode _) => setState(() {});

  /// Keyboard focus on the region itself; a click never shows the mark.
  bool get _showsFocus =>
      _region.hasPrimaryFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// The region is a Tab stop only while the page offers no control of its
  /// own and has something to scroll; otherwise Tab reaches the page through
  /// its controls as before, and a short page is no stop at all.
  void _syncTabStop() {
    if (!mounted) return;
    final hasControls = _region.descendants.any(
      (n) => n.canRequestFocus && !n.skipTraversal,
    );
    final scrolls =
        _controller.hasClients && _controller.position.maxScrollExtent > 0;
    final skip = hasControls || !scrolls;
    if (_region.skipTraversal != skip) {
      setState(() => _region.skipTraversal = skip);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_controller.hasClients) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final onRegion = focus == _region;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final position = _controller.position;
    final page = position.viewportDimension * 0.85;
    final key = event.logicalKey;
    double? target;
    if (key == LogicalKeyboardKey.pageDown) {
      target = position.pixels + page;
    } else if (key == LogicalKeyboardKey.pageUp) {
      target = position.pixels - page;
    } else if (key == LogicalKeyboardKey.home && (ctrl || onRegion)) {
      target = position.minScrollExtent;
    } else if (key == LogicalKeyboardKey.end && (ctrl || onRegion)) {
      target = position.maxScrollExtent;
    } else if (onRegion && key == LogicalKeyboardKey.arrowDown) {
      target = position.pixels + _lineStep;
    } else if (onRegion && key == LogicalKeyboardKey.arrowUp) {
      target = position.pixels - _lineStep;
    } else if (onRegion && key == LogicalKeyboardKey.space) {
      target = HardwareKeyboard.instance.isShiftPressed
          ? position.pixels - page
          : position.pixels + page;
    }
    if (target == null) return KeyEventResult.ignored;
    _controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final focused = _showsFocus;
    return Focus(
      focusNode: _region,
      onKeyEvent: _onKey,
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context).copyWith(
          thumbColor: focused ? WidgetStatePropertyAll(WpColors.accent) : null,
        ),
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: focused ? true : null,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _syncTabStop(),
                );
                return false;
              },
              child: SingleChildScrollView(
                controller: _controller,
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
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
