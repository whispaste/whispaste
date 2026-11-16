/// Pure geometry for keeping a persisted window/panel position on-screen.
///
/// A position saved to settings can go stale the moment a monitor is
/// unplugged, resolution changes, or the app is opened on a different
/// machine's settings backup — with nothing to clamp it, the main window or
/// the floating button/overlay can start entirely off any currently
/// connected display. This does single-screen clamp math similar to the
/// native overlay shells' own clamp functions, but picks the *right* display
/// out of however many are currently connected, so callers stay independent
/// of `screen_retriever`'s types (easy to unit test, no plugin channel
/// involved).
library;

import 'package:flutter/widgets.dart';

/// Where and how large a window opens: the size fitted into a work area and
/// the top-left position (`null` = let the platform center it).
typedef WindowPlacement = ({Size size, Offset? position});

abstract final class WindowPositionClamp {
  /// Resolves the start or restore placement of a window of [size].
  ///
  /// The size is raised to [minimum] and then capped to the work area of the
  /// display it lands on, so it never extends under a taskbar, Dock or menu
  /// bar. A stored [position] is clamped onto that display; a missing one
  /// centers the window in the [primary] work area. Without any [displays]
  /// (enumeration failed) only the minimum is applied.
  static WindowPlacement place({
    Offset? position,
    required Size size,
    required Size minimum,
    required List<Rect> displays,
    Rect? primary,
  }) {
    final raised = Size(
      size.width < minimum.width ? minimum.width : size.width,
      size.height < minimum.height ? minimum.height : size.height,
    );
    if (displays.isEmpty) {
      return (size: raised, position: position);
    }
    if (position != null) {
      final target = _displayFor(position, raised, displays);
      final fitted = _fit(raised, minimum, target);
      return (
        size: fitted,
        position: clamp(position: position, size: fitted, displays: displays),
      );
    }
    final target = primary ?? displays.first;
    final fitted = _fit(raised, minimum, target);
    return (
      size: fitted,
      position: Offset(
        target.left + (target.width - fitted.width) / 2,
        target.top + (target.height - fitted.height) / 2,
      ),
    );
  }

  /// Minimum size the OS may enforce, capped to [workArea]. A minimum taller
  /// than the work area would force the window under the taskbar or Dock, so
  /// the window manager gets the smaller of the two per axis.
  static Size capMinimum(Size minimum, Rect workArea) => Size(
    _lower(minimum.width, workArea.width),
    _lower(minimum.height, workArea.height),
  );

  /// Work area wins over the minimum: a window never extends past it.
  static Size _fit(Size size, Size minimum, Rect workArea) => Size(
    _lower(_higher(size.width, minimum.width), workArea.width),
    _lower(_higher(size.height, minimum.height), workArea.height),
  );

  static double _higher(double value, double floor) =>
      value < floor ? floor : value;

  static double _lower(double value, double limit) =>
      value > limit ? limit : value;

  static Rect _displayFor(Offset position, Size size, List<Rect> displays) {
    final center = Offset(
      position.dx + size.width / 2,
      position.dy + size.height / 2,
    );
    return displays.firstWhere(
      (d) => d.contains(center),
      orElse: () => _nearest(displays, center),
    );
  }

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
    final target = _displayFor(position, size, displays);
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
