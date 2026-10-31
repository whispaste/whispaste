/// WpFocusRing — keyboard-focus-visible outline painted OUTSIDE the wrapped
/// widget bounds.
///
/// Layout-neutral: the outline is drawn by a [CustomPainter] in the foreground
/// layer, extending a few dp beyond the widget's own size, so adjacent
/// siblings are never displaced.
///
/// ## Why a crisp outline
///
/// The ring is a solid 2 dp line set 3 dp off the control, never blurred or
/// softened (UIA-VIS-12). A focus mark has to read as a
/// shape with a clear edge, so the keyboard user sees exactly which control
/// has focus. Both the line width and the gap come from the app tokens
/// (`focus-ring-width`, `focus-ring-gap`).
///
/// Two usage modes:
///
/// **Standalone** (`focusNode` = null, default):
///   Creates its own [FocusNode] via [FocusableActionDetector].
///   [FocusableActionDetector] correctly respects [FocusHighlightMode] so the
///   ring only appears on keyboard navigation, never on pointer tap.
///
/// **External-node** (`focusNode` provided):
///   The caller creates one [FocusNode] and passes it to BOTH [WpFocusRing]
///   AND the inner [InkWell] (or other Focus-bearing widget).  [WpFocusRing]
///   does NOT insert a second [Focus] widget; it only attaches a listener to
///   the shared node and to [FocusManager.highlightMode].  Enter/Space
///   keyboard activation continues to work because the [InkWell] still owns
///   the only [Focus] widget in the tree.
///
/// ## Ring colour
///
/// The ring is the accent colour by default, which is what every caller wants:
/// they wrap controls whose own surface is *not* accent-filled (rows, chips,
/// search fields, outlined triggers), so an accent ring 2 dp outside them
/// reads as one clear, on-brand focus mark.
///
/// A control that is itself filled edge-to-edge in a saturated colour breaks
/// that assumption: a ring of the same colour sitting 2 dp off the fill reads
/// as a second border of the control rather than as focus — two concentric
/// outlines, a target instead of an indicator. Such a caller passes
/// [ringColor] with a colour that contrasts against *both* its own fill and
/// the page behind it (see `WpButton`). It stays an explicit opt-in: changing
/// the default would repaint the ten-odd correct callers to fix one.
library;

import 'package:flutter/material.dart';

import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';

/// Focus-visible ring that wraps any widget without affecting layout.
class WpFocusRing extends StatefulWidget {
  const WpFocusRing({
    super.key,
    required this.child,
    this.focusNode,
    this.radius,
    this.ringColor,
    this.insets = EdgeInsets.zero,
  });

  final Widget child;

  /// External [FocusNode] to observe (external-node mode).
  ///
  /// When non-null, no [Focus] widget is inserted — a listener is attached
  /// only.  Pass the **same** node to the inner [InkWell.focusNode] so
  /// keyboard activation (Enter/Space) remains intact.
  final FocusNode? focusNode;

  /// Corner radius for the ring.  Defaults to [WpRadius.sm] (8 dp).
  final double? radius;

  /// Ring colour.  Defaults to `ColorScheme.primary` — the accent.
  ///
  /// Only set this on a control that is itself filled in a strong colour; see
  /// the library docs.
  final Color? ringColor;

  /// Difference between the child's *reported* layout size and its *visible*
  /// box, per edge.
  ///
  /// Normally zero: what a widget reports is what it paints, and the ring is
  /// measured off the full size. Material's [MaterialTapTargetSize.padded]
  /// breaks that — `_InputPadding` inflates the reported size to
  /// `kMinInteractiveDimension` (48) in any dimension that falls short, so a
  /// 40 dp button reports 48 dp and carries 4 dp of invisible padding above and
  /// below its visible edge. A ring measured off the reported box then sits
  /// 4 dp further away vertically than horizontally.
  ///
  /// Callers that know about such padding declare it here; the ring is then
  /// measured off `size` shrunk by these insets, i.e. off the visible contour.
  final EdgeInsets insets;

  @override
  State<WpFocusRing> createState() => _WpFocusRingState();
}

class _WpFocusRingState extends State<WpFocusRing> {
  FocusNode? _ownedNode; // non-null in standalone mode only
  bool _showRing = false;

  bool get _standalone => widget.focusNode == null;

  @override
  void initState() {
    super.initState();
    if (_standalone) {
      _ownedNode = FocusNode();
    } else {
      _attachExternal(widget.focusNode!);
    }
  }

  @override
  void didUpdateWidget(WpFocusRing old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      if (old.focusNode != null) {
        _detachExternal(old.focusNode!);
      } else {
        _ownedNode?.dispose();
        _ownedNode = null;
      }
      if (_standalone) {
        _ownedNode = FocusNode();
      } else {
        _attachExternal(widget.focusNode!);
      }
      setState(() => _showRing = false);
    }
  }

  @override
  void dispose() {
    _ownedNode?.dispose();
    if (!_standalone) _detachExternal(widget.focusNode!);
    super.dispose();
  }

  // ── External-node helpers ──────────────────────────────────────────────────

  void _attachExternal(FocusNode node) {
    node.addListener(_onExternalFocus);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  void _detachExternal(FocusNode node) {
    node.removeListener(_onExternalFocus);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
  }

  void _onExternalFocus() => _syncExternal();
  void _onHighlightMode(FocusHighlightMode _) => _syncExternal();

  void _syncExternal() {
    if (!mounted) return;
    final node = widget.focusNode;
    if (node == null) return;
    final should =
        node.hasFocus &&
        FocusManager.instance.highlightMode != FocusHighlightMode.touch;
    if (_showRing != should) setState(() => _showRing = should);
  }

  // ── Standalone mode callback (called by FocusableActionDetector) ──────────

  void _onFadHighlight(bool show) {
    if (_showRing != show) setState(() => _showRing = show);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ringColor = widget.ringColor ?? Theme.of(context).colorScheme.primary;
    final radius = widget.radius ?? WpRadius.sm;

    final painted = CustomPaint(
      foregroundPainter: _showRing
          ? WpFocusRingPainter(
              color: ringColor,
              radius: radius,
              insets: widget.insets,
            )
          : null,
      child: widget.child,
    );

    if (_standalone) {
      return FocusableActionDetector(
        focusNode: _ownedNode,
        onShowFocusHighlight: _onFadHighlight,
        child: painted,
      );
    }

    // External-node mode — no additional Focus widget.
    return painted;
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

/// Paints a solid rounded outline in [color] just outside the widget bounds.
///
/// Exposed as a public class (non-private) so widget tests can inspect
/// [color] and [radius] to verify token usage without golden snapshots.
class WpFocusRingPainter extends CustomPainter {
  const WpFocusRingPainter({
    required this.color,
    required this.radius,
    this.insets = EdgeInsets.zero,
  });

  final Color color;
  final double radius;

  /// Invisible padding between the reported size and the visible box — see
  /// [WpFocusRing.insets].
  final EdgeInsets insets;

  /// Distance from the widget edge to the inner edge of the outline.
  static const double _gap = WpShellTokens.focusRingGap;

  /// Width of the solid outline. Value from the app token (`focus-ring-width`),
  /// the single source for this ring.
  static const double _stroke = WpShellTokens.focusRingWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..isAntiAlias = true;

    // A stroke is centred on its path, so the path sits half a stroke width
    // further out than the gap to keep the inner edge exactly [_gap] away.
    const outset = _gap + _stroke / 2;
    final rrect = RRect.fromLTRBR(
      insets.left - outset,
      insets.top - outset,
      size.width - insets.right + outset,
      size.height - insets.bottom + outset,
      Radius.circular(radius + outset),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(WpFocusRingPainter old) =>
      old.color != color || old.radius != radius || old.insets != insets;
}
