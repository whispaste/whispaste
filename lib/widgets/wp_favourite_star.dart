// ---------------------------------------------------------------------------
// WpFavouriteStar — the favourite toggle of a list row or detail (ticket §4).
//
// Off: a 1.6 px outline in `textMuted`. On: filled `highlight` (amber) with a
// `highlightText` stroke, so the edge keeps 3:1 against a white card. Drawn
// from a path rather than an icon font, because the icon set has no filled
// star and both states must share one geometry.
//
// Hit area is 44 px, matching the icon button beside it. The toggle carries a
// `selected` semantics flag, and the caller supplies the label.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

class WpFavouriteStar extends StatefulWidget {
  const WpFavouriteStar({
    super.key,
    required this.isFavourite,
    required this.semanticsLabel,
    required this.onToggle,
  });

  final bool isFavourite;

  /// Accessible name, for example "Favourite".
  final String semanticsLabel;

  /// `null` disables the control.
  final VoidCallback? onToggle;

  /// Visible square, equal to [WpIconButton.extent]. The tap area is
  /// [WpLayout.minTouchTarget] square, see [WpTouchTarget].
  static const double hitExtent = WpShellTokens.fieldHeight;

  /// Visible star size.
  static const double starSize = 20;

  @override
  State<WpFavouriteStar> createState() => _WpFavouriteStarState();
}

class _WpFavouriteStarState extends State<WpFavouriteStar> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpFavouriteStar');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onToggle != null;
    final radius = BorderRadius.circular(WpRadiusTokens.sm);
    final on = widget.isFavourite;

    final star = CustomPaint(
      size: const Size.square(WpFavouriteStar.starSize),
      painter: _StarPainter(
        filled: on,
        fill: WpColors.highlight,
        stroke: on ? WpColors.highlightText : WpColors.textMuted,
      ),
    );

    final button = SizedBox.square(
      dimension: WpFavouriteStar.hitExtent,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          focusNode: _focusNode,
          borderRadius: radius,
          onTap: widget.onToggle,
          child: Center(
            child: Opacity(opacity: enabled ? 1 : 0.5, child: star),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      toggled: on,
      enabled: enabled,
      label: widget.semanticsLabel,
      child: WpTouchTarget(
        onTap: widget.onToggle,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadiusTokens.sm,
          child: button,
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter({
    required this.filled,
    required this.fill,
    required this.stroke,
  });

  final bool filled;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _starPath(size);
    if (filled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Five-point star inscribed in [size], outer radius at the box half.
  static Path _starPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = math.min(size.width, size.height) / 2 - 0.8;
    final inner = outer * 0.48;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.filled != filled || old.fill != fill || old.stroke != stroke;
}
