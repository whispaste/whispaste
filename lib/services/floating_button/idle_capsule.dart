/// Idle form of the floating button: a slim capsule that opens to the pill on
/// hover (setting `overlay_button_idle_capsule`, default off keeps the disc).
///
/// Pure Dart: the render engine reports the pointer, this library decides the
/// size and whether hover may expand the capsule. The native shell only
/// resizes its window to the size the render engine asks for; it anchors the
/// window at its origin, so the capsule keeps its on-screen corner.
library;

import 'dart:async';
import 'dart:ui' show Rect, Size;

class IdleCapsule {
  const IdleCapsule._();

  /// Resting size, in logical pixels.
  static const double idleWidth = 56;
  static const double idleHeight = 20;

  /// Size while hovered, the pill that the capsule opens to.
  static const double hoverWidth = 112;
  static const double hoverHeight = 28;

  /// Hover needs global pointer tracking. Linux under Wayland provides none
  /// for a plain toplevel, so the capsule stays at rest there and a click
  /// still starts recording.
  static bool hoverSupported({
    required bool isLinux,
    required bool isWayland,
  }) => !(isLinux && isWayland);

  /// Whether a Linux session runs under Wayland, from the environment
  /// variables a Wayland session sets. Takes the map so it stays testable.
  static bool isWaylandSession(Map<String, String> environment) =>
      environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland' ||
      (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;

  /// Whether the capsule is expanded for the given pointer state.
  static bool expands({required bool hovered, required bool hoverSupported}) =>
      hovered && hoverSupported;

  /// Pause before the pill closes again after the pointer has left, so a
  /// pointer that only grazes the edge does not make it flicker.
  static const Duration collapseDelay = Duration(milliseconds: 300);
}

/// Tracks the pointer over the capsule window and reports when the pill opens
/// and closes.
///
/// Opening is immediate. Closing waits [IdleCapsule.collapseDelay] after the
/// pointer has left, and a pointer that comes back within that time keeps the
/// pill open. Where hover is not supported the pill never opens.
class IdleCapsuleHover {
  IdleCapsuleHover({
    required this.hoverSupported,
    required this.onExpandedChanged,
    this.collapseDelay = IdleCapsule.collapseDelay,
  });

  /// False where no global hover is tracked (Linux under Wayland).
  final bool hoverSupported;

  /// Called with the new value whenever the pill opens or closes.
  final void Function(bool expanded) onExpandedChanged;

  /// Delay before a pill that the pointer has left closes again.
  final Duration collapseDelay;

  bool _hovered = false;
  bool _expanded = false;
  Timer? _collapseTimer;

  /// Whether the pill is shown (including during the collapse delay).
  bool get expanded => _expanded;

  /// The pointer entered the capsule window.
  void pointerEnter() {
    _hovered = true;
    _collapseTimer?.cancel();
    _collapseTimer = null;
    _setExpanded(
      IdleCapsule.expands(hovered: _hovered, hoverSupported: hoverSupported),
    );
  }

  /// The pointer left the capsule window.
  void pointerExit() {
    _hovered = false;
    if (!_expanded) return;
    _collapseTimer?.cancel();
    _collapseTimer = Timer(collapseDelay, () {
      _collapseTimer = null;
      if (!_hovered) _setExpanded(false);
    });
  }

  /// Closes the pill at once and forgets the pointer. Used when the capsule no
  /// longer applies (recording, or the setting is off).
  void reset() {
    _collapseTimer?.cancel();
    _collapseTimer = null;
    _hovered = false;
    _setExpanded(false);
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    onExpandedChanged(value);
  }

  /// Cancels a pending collapse. Call when the owning widget goes away.
  void dispose() {
    _collapseTimer?.cancel();
    _collapseTimer = null;
  }
}

/// Which edges of the capsule stay put while the pill opens, so the pill grows
/// toward the interior of the screen.
///
/// The native shells apply the same rule to their window (macOS: y grows up
/// from the bottom edge by default; Windows and Linux: y grows down from the
/// top edge by default). Keep the two in step.
class CapsulePins {
  const CapsulePins({required this.pinnedRight, required this.pinnedBottom});

  /// The right edge stays put, so the window grows to the left.
  final bool pinnedRight;

  /// The bottom edge stays put, so the window grows upward.
  final bool pinnedBottom;

  /// Resolves the pins for a window [home] (the capsule at rest, top-left
  /// coordinates, y down) that opens to [pill] on [screen]. The default pins
  /// the left edge, and the bottom edge when [defaultPinsBottom] (macOS), else
  /// the top edge. An edge flips only where the default would leave the screen
  /// and the other side fits. A [pill] of the rest size returns the defaults,
  /// so shrinking back lands exactly on [home].
  static CapsulePins resolve({
    required Rect home,
    required Size pill,
    required Rect screen,
    required bool defaultPinsBottom,
  }) {
    final rightFits = home.right - pill.width >= screen.left;
    final leftFits = home.left + pill.width <= screen.right;
    final pinnedRight = !leftFits && rightFits;

    final upFits = home.bottom - pill.height >= screen.top;
    final downFits = home.top + pill.height <= screen.bottom;
    final pinnedBottom = defaultPinsBottom
        ? !(!upFits && downFits)
        : (!downFits && upFits);

    return CapsulePins(pinnedRight: pinnedRight, pinnedBottom: pinnedBottom);
  }
}
