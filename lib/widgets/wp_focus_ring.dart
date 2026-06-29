/// WpFocusRing — keyboard-focus-visible ring painted OUTSIDE the wrapped
/// widget bounds.
///
/// Layout-neutral: the ring is drawn by a [CustomPainter] in the foreground
/// layer, extending 2 dp beyond the widget's own size, so adjacent siblings
/// are never displaced.
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
library;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// Focus-visible ring that wraps any widget without affecting layout.
class WpFocusRing extends StatefulWidget {
  const WpFocusRing({
    super.key,
    required this.child,
    this.focusNode,
    this.radius,
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
    final accentColor = Theme.of(context).colorScheme.primary;
    final radius = widget.radius ?? WpRadius.sm;

    final painted = CustomPaint(
      foregroundPainter: _showRing
          ? WpFocusRingPainter(color: accentColor, radius: radius)
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

/// Paints a 2 dp accent-coloured rounded ring 2 dp outside the widget bounds.
///
/// Exposed as a public class (non-private) so widget tests can inspect
/// [color] and [radius] to verify token usage without golden snapshots.
class WpFocusRingPainter extends CustomPainter {
  const WpFocusRingPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _gap = 2.0;
  static const double _stroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..isAntiAlias = true;

    final rrect = RRect.fromLTRBR(
      -_gap,
      -_gap,
      size.width + _gap,
      size.height + _gap,
      Radius.circular(radius + _gap),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(WpFocusRingPainter old) =>
      old.color != color || old.radius != radius;
}
