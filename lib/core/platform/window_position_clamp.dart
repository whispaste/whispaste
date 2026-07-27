/// Pure geometry for keeping a persisted window/panel position on-screen.
///
/// A position saved to settings can go stale the moment a monitor is
/// unplugged, resolution changes, or the app is opened on a different
/// machine's settings backup — with nothing to clamp it, the main window or
/// the floating button/overlay can start entirely off any currently
/// connected display. This mirrors [OverlayPositioning.clampToScreen]'s
/// single-screen math but picks the *right* display out of however many are
/// currently connected, so callers stay independent of `screen_retriever`'s
/// types (easy to unit test, no plugin channel involved).
library;

import 'package:flutter/widgets.dart';

abstract final class WindowPositionClamp {
  /// Clamps [position] (top-left origin) for a window/panel of [size] onto
  /// whichever of [displays] the position belongs to.
  ///
  /// A display "contains" the position when the window's center falls inside
  /// its bounds; if none does (stale position, unplugged monitor), the
  /// display whose center is nearest to the target position is used instead
  /// so the window reappears near where the user last saw it rather than
  /// jumping to an arbitrary display. Returns [position] unchanged when
  /// [displays] is empty (screen enumeration failed) — a plausible saved
  /// position beats discarding it outright.
  static Offset clamp({
    required Offset position,
    required Size size,
    required List<Rect> displays,
  }) {
    if (displays.isEmpty) return position;
    final center = Offset(
      position.dx + size.width / 2,
      position.dy + size.height / 2,
    );
    final target = displays.firstWhere(
      (d) => d.contains(center),
      orElse: () => _nearest(displays, center),
    );
    final minX = target.left;
    final minY = target.top;
    final maxX = target.right - size.width;
    final maxY = target.bottom - size.height;
    final x = maxX < minX ? minX : position.dx.clamp(minX, maxX);
    final y = maxY < minY ? minY : position.dy.clamp(minY, maxY);
    return Offset(x, y);
  }

  static Rect _nearest(List<Rect> displays, Offset point) {
    var best = displays.first;
    var bestDistanceSquared = double.infinity;
    for (final d in displays) {
      final dx = d.center.dx - point.dx;
      final dy = d.center.dy - point.dy;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        best = d;
      }
    }
    return best;
  }
}
