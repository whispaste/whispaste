/// Schematic preview widgets for the Settings overlay/button sections.
///
/// These are purely compositional widgets — no animation, no platform overlay
/// mock. They show a miniature screen rectangle with the overlay pill placed at
/// the chosen anchor position, scaled to indicate the chosen size variant.
///
/// Two public widgets are exposed:
/// - [OverlayPositionPreview] — the Floating Overlay variant (issue 04).
/// - [FloatingButtonPositionPreview] — the Floating Button variant (issue 05,
///   reuses the same [_ScreenPreviewPainter] base).
///
/// Observable keys for tests (position + size pills carry [ValueKey]s so tests
/// can assert observable layout changes without reaching into painter internals):
/// - `overlay-pill-<position.value>` (e.g. `overlay-pill-top-center`)
/// - `overlay-pill-size-<size.value>`  (e.g. `overlay-pill-size-compact`)
library;

import 'package:flutter/material.dart';

import '../core/config/settings_enums.dart';
import '../core/theme/overlay_design_spec.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Public — Floating Overlay preview (issue 04)
// ---------------------------------------------------------------------------

/// Schematic preview of the Floating Overlay.
///
/// Renders a miniature screen with the overlay pill placed according to
/// [position] and sized according to [size]. Both properties carry observable
/// [ValueKey]s so widget tests can distinguish positions/sizes without
/// inspecting painter internals.
class OverlayPositionPreview extends StatelessWidget {
  const OverlayPositionPreview({
    super.key,
    required this.position,
    required this.size,
  });

  final OverlayStartPosition position;
  final FloatingOverlaySize size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ScreenPreview(
      isDark: isDark,
      pillVariant: _PillVariant.overlay,
      position: position,
      compact: size == FloatingOverlaySize.compact,
      // Observable keys — tests find the pill by position and by size.
      positionKey: ValueKey('overlay-pill-${position.value}'),
      sizeKey: ValueKey('overlay-pill-size-${size.value}'),
    );
  }
}

// ---------------------------------------------------------------------------
// Public — Floating Button preview (issue 05, reuses same base)
// ---------------------------------------------------------------------------

/// Schematic preview of the Floating Button.
///
/// Shares [_ScreenPreview] / [_ScreenPreviewPainter] with
/// [OverlayPositionPreview]; the only variant is the pill shape (disc vs.
/// capsule) which [_PillVariant] controls.
class FloatingButtonPositionPreview extends StatelessWidget {
  const FloatingButtonPositionPreview({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return _ScreenPreview(
      isDark: isDark,
      pillVariant: _PillVariant.button,
      position: OverlayStartPosition.topCenter, // not used for button
      compact: false,
      positionKey: const ValueKey('button-pill'),
      sizeKey: const ValueKey('button-pill-size'),
    );
  }
}

// ---------------------------------------------------------------------------
// Private — shared screen-preview widget
// ---------------------------------------------------------------------------

enum _PillVariant { overlay, button }

class _ScreenPreview extends StatelessWidget {
  const _ScreenPreview({
    required this.isDark,
    required this.pillVariant,
    required this.position,
    required this.compact,
    required this.positionKey,
    required this.sizeKey,
  });

  final bool isDark;
  final _PillVariant pillVariant;
  final OverlayStartPosition position;
  final bool compact;
  final ValueKey<String> positionKey;
  final ValueKey<String> sizeKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      child: Center(
        child: SizedBox(
          width: 220,
          height: 140,
          child: _ScreenCanvas(
            isDark: isDark,
            pillVariant: pillVariant,
            position: position,
            compact: compact,
            positionKey: positionKey,
            sizeKey: sizeKey,
          ),
        ),
      ),
    );
  }
}

/// Custom-painted miniature screen with an overlay pill.
///
/// The painter draws the screen chrome; the pill is a composed Flutter widget
/// (not painted) so that [ValueKey]s are discoverable in widget tests.
class _ScreenCanvas extends StatelessWidget {
  const _ScreenCanvas({
    required this.isDark,
    required this.pillVariant,
    required this.position,
    required this.compact,
    required this.positionKey,
    required this.sizeKey,
  });

  final bool isDark;
  final _PillVariant pillVariant;
  final OverlayStartPosition position;
  final bool compact;
  final ValueKey<String> positionKey;
  final ValueKey<String> sizeKey;

  @override
  Widget build(BuildContext context) {
    // Screen background derived from design tokens.
    final screenBg = isDark ? const Color(0xFF1A2030) : const Color(0xFFE8EDF5);
    final screenBorder = isDark
        ? const Color(0x40FFFFFF)
        : const Color(0x30000000);

    return Stack(
      children: [
        // -- Screen chrome (painted background + border) ---------------------
        Positioned.fill(
          child: CustomPaint(
            painter: _ScreenChromePainter(
              background: screenBg,
              border: screenBorder,
              radius: WpRadius.md,
            ),
          ),
        ),

        // -- Overlay pill (composed widget with observable keys) -------------
        _PillOverlay(
          isDark: isDark,
          pillVariant: pillVariant,
          position: position,
          compact: compact,
          positionKey: positionKey,
          sizeKey: sizeKey,
        ),
      ],
    );
  }
}

/// Paints the miniature screen background with rounded corners and a border.
class _ScreenChromePainter extends CustomPainter {
  const _ScreenChromePainter({
    required this.background,
    required this.border,
    required this.radius,
  });

  final Color background;
  final Color border;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromLTRBR(
      0,
      0,
      size.width,
      size.height,
      Radius.circular(radius),
    );

    // Fill.
    canvas.drawRRect(rr, Paint()..color = background);

    // Hairline border.
    canvas.drawRRect(
      rr,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_ScreenChromePainter old) =>
      old.background != background ||
      old.border != border ||
      old.radius != radius;
}

/// Positions the pill widget inside the screen area based on [position].
///
/// The pill carries both [positionKey] and [sizeKey] so tests can observe
/// all relevant properties without reaching into painter state.
class _PillOverlay extends StatelessWidget {
  const _PillOverlay({
    required this.isDark,
    required this.pillVariant,
    required this.position,
    required this.compact,
    required this.positionKey,
    required this.sizeKey,
  });

  final bool isDark;
  final _PillVariant pillVariant;
  final OverlayStartPosition position;
  final bool compact;
  final ValueKey<String> positionKey;
  final ValueKey<String> sizeKey;

  /// Logical pill dimensions from the spec, scaled to fit the preview canvas.
  static const double _previewScale = 0.42;
  static const double _margin = 8.0; // screen-edge margin in preview coords

  @override
  Widget build(BuildContext context) {
    const colors =
        OverlayDesignSpec.light; // spec: single design for both themes
    final sizeSpec = compact ? OverlaySizeSpec.compact : OverlaySizeSpec.normal;

    final pillW = sizeSpec.width * _previewScale;
    final pillH = sizeSpec.height * _previewScale;

    // Alignment within the screen canvas.
    // lastPosition falls back to top-center (mirrors OverlayPositioning).
    final isBottom = position == OverlayStartPosition.bottomCenter;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        final left = (screenW - pillW) / 2;
        final top = isBottom ? screenH - pillH - _margin : _margin;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: pillW,
              height: pillH,
              child: _PillWidget(
                colors: colors,
                compact: compact,
                pillVariant: pillVariant,
                radius: (sizeSpec.capsuleRadius * _previewScale).clamp(
                  0,
                  pillH / 2,
                ),
                // Both observable keys live on this single widget so a test
                // can find either key and always land on the same element.
                positionKey: positionKey,
                sizeKey: sizeKey,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The actual pill shape — two [ValueKey]s are stacked via a [KeyedSubtree]
/// wrapper so tests can find either key in the widget tree.
class _PillWidget extends StatelessWidget {
  const _PillWidget({
    required this.colors,
    required this.compact,
    required this.pillVariant,
    required this.radius,
    required this.positionKey,
    required this.sizeKey,
  });

  final OverlayThemeColors colors;
  final bool compact;
  final _PillVariant pillVariant;
  final double radius;
  final ValueKey<String> positionKey;
  final ValueKey<String> sizeKey;

  @override
  Widget build(BuildContext context) {
    final decoration = pillVariant == _PillVariant.overlay
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.capsuleFillStart, colors.capsuleFillEnd],
            ),
            border: Border.all(color: colors.capsuleBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          )
        : BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0x1A101828)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          );

    // positionKey lives on the outer container (position determines placement).
    // sizeKey lives on the inner decorated box (size determines the pill dims).
    return KeyedSubtree(
      key: positionKey,
      child: Container(key: sizeKey, decoration: decoration),
    );
  }
}
