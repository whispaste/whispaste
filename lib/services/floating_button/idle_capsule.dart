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

  /// Hover arrives through the window's own pointer events. The runner forces
  /// the X11 GDK backend (XWayland on a Wayland session), and a compositor
  /// delivers enter/leave to an XWayland window like to any other, so the
  /// session type does not matter. Only a GTK forced onto native Wayland
  /// (`GDK_BACKEND=wayland`) gives a plain toplevel no pointer tracking.
  static bool hoverSupported({
    required bool isLinux,
    required bool nativeWayland,
  }) => !(isLinux && nativeWayland);

  /// Whether GTK runs on the native Wayland backend, from `GDK_BACKEND` (the
  /// runner sets `x11` when it is unset). Takes the map so it stays testable.
  static bool isNativeWaylandBackend(Map<String, String> environment) =>
      (environment['GDK_BACKEND'] ?? '')
          .split(',')
          .first
          .trim()
          .toLowerCase() ==
      'wayland';

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
/// pill open. The pointer is remembered while the capsule does not apply
/// ([active] false: recording, transcribing, result), so a pointer that rests
/// on the button when it falls back to the capsule opens the pill again
/// without a fresh enter. Where hover is not supported the pill never opens.
class IdleCapsuleHover {
  IdleCapsuleHover({
    required this.hoverSupported,
    required this.onExpandedChanged,
    this.collapseDelay = IdleCapsule.collapseDelay,
    this.unconfirmedHold = const Duration(seconds: 3),
  });

  /// False where no global hover is tracked (Linux under Wayland).
  final bool hoverSupported;

  /// Called with the new value whenever the pill opens or closes.
  final void Function(bool expanded) onExpandedChanged;

  /// Delay before a pill that the pointer has left closes again.
  final Duration collapseDelay;

  /// How long a pill reopened from the remembered pointer stays without a
  /// pointer event. While the capsule did not apply the window may have moved
  /// or hidden, and no exit event arrives then, so the memory can be stale.
  final Duration unconfirmedHold;

  bool _hovered = false;
  bool _active = true;
  bool _expanded = false;
  Timer? _collapseTimer;

  /// Whether the pill is shown (including during the collapse delay).
  bool get expanded => _expanded;

  /// Whether the pointer is over the button window, whatever its form.
  bool get hovered => _hovered;

  /// The pointer entered or moved inside the button window.
  void pointerEnter() {
    _hovered = true;
    _collapseTimer?.cancel();
    _collapseTimer = null;
    _setExpanded(
      _active &&
          IdleCapsule.expands(
            hovered: _hovered,
            hoverSupported: hoverSupported,
          ),
    );
  }

  /// The pointer left the button window.
  void pointerExit() {
    _hovered = false;
    if (!_expanded) return;
    _collapseTimer?.cancel();
    _collapseTimer = Timer(collapseDelay, () {
      _collapseTimer = null;
      if (!_hovered) _setExpanded(false);
    });
  }

  /// Whether the capsule applies right now (the button is idle and the
  /// setting is on). Turning it off closes the pill at once but keeps the
  /// pointer; turning it on opens the pill if the pointer is still there and
  /// forgets it after [unconfirmedHold] unless a pointer event confirms it.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _collapseTimer?.cancel();
    _collapseTimer = null;
    _setExpanded(
      active &&
          IdleCapsule.expands(
            hovered: _hovered,
            hoverSupported: hoverSupported,
          ),
    );
    if (_expanded) {
      _collapseTimer = Timer(unconfirmedHold, () {
        _collapseTimer = null;
        _hovered = false;
        _setExpanded(false);
      });
    }
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
