/// Platform-independent overlay positioning math.
///
/// Anchor resolution, screen-edge clamping and the size lookup all read from
/// the single source of truth ([OverlayDesignSpec]); this module owns no
/// geometry constants of its own. It lives in Dart (not in the native shells)
/// so the positioning/clamping/anchor behaviour is identical across macOS,
/// Windows and Linux and is unit-testable (ADR 0002, issue 05 AC3).
///
/// Coordinate convention: all rects/offsets use the Flutter/logical-pixel
/// convention with the origin at the top-left and the y-axis pointing **down**.
/// A native shell that uses a y-up coordinate space (macOS `NSScreen`) converts
/// at its own boundary; the shared math stays in one convention.
library;

import 'package:flutter/widgets.dart';

import '../../core/theme/overlay_design_spec.dart';

/// Pure positioning helpers for the floating overlay window.
abstract final class OverlayPositioning {
  /// The logical pill size for the given size variant, taken from the spec.
  static Size overlaySize({required bool compact}) {
    final s = OverlayDesignSpec.size(compact: compact);
    return Size(s.width, s.height);
  }

  /// Margin kept from every screen edge — sourced from the spec.
  static double get edgeMargin =>
      OverlayDesignSpec.interaction.screenEdgeMargin;

  /// Pointer travel before a press becomes a drag — sourced from the spec.
  static double get dragThreshold =>
      OverlayDesignSpec.interaction.dragThresholdPx;

  /// Resolves the top-left window origin for [anchor] within [screen].
  ///
  /// [size] is the pill size (see [overlaySize]); [lastPosition] is consulted
  /// only for [OverlayAnchor.lastPosition] and falls back to the top-centre
  /// anchor when absent. The result is always clamped on-screen via
  /// [clampToScreen] so a stale persisted position or a smaller monitor can
  /// never push the overlay off-screen (multi-monitor / resolution change).
  static Offset resolve({
    required OverlayAnchor anchor,
    required Rect screen,
    required Size size,
    Offset? lastPosition,
  }) {
    final m = edgeMargin;
    final Offset target;
    switch (anchor) {
      case OverlayAnchor.topCenter:
        target = Offset(
          screen.left + (screen.width - size.width) / 2,
          screen.top + m,
        );
      case OverlayAnchor.bottomCenter:
        target = Offset(
          screen.left + (screen.width - size.width) / 2,
          screen.bottom - size.height - m,
        );
      case OverlayAnchor.lastPosition:
        target =
            lastPosition ??
            Offset(
              screen.left + (screen.width - size.width) / 2,
              screen.top + m,
            );
    }
    return clampToScreen(point: target, size: size, screen: screen);
  }

  /// Clamps [point] so the pill of [size] stays fully inside [screen], keeping
  /// [edgeMargin] from each edge.
  ///
  /// If the screen is smaller than the pill plus its margins (degenerate case)
  /// the origin is pinned to the top-left in-margin corner rather than
  /// producing an inverted clamp range.
  static Offset clampToScreen({
    required Offset point,
    required Size size,
    required Rect screen,
  }) {
    final m = edgeMargin;
    final minX = screen.left + m;
    final minY = screen.top + m;
    final maxX = screen.right - size.width - m;
    final maxY = screen.bottom - size.height - m;
    final x = maxX < minX ? minX : point.dx.clamp(minX, maxX).toDouble();
    final y = maxY < minY ? minY : point.dy.clamp(minY, maxY).toDouble();
    return Offset(x, y);
  }
}
