/// Decides whether a snapshot must reach the native overlay shell (WP-84 phase
/// 2, plan items 2 and 3).
///
/// Every visible snapshot is sent: it carries content. A hidden snapshot is
/// only sent when the shell needs it: the first hide, a hide that changes the
/// size class (so the shell resizes while hidden, off the hot path), or a hide
/// that changes the background or wave preset (the shell keeps those for its
/// next show, so a theme change made while hidden must not be swallowed).
/// Repeated hides with the same size and presets are dropped, so an idle
/// settings sync does not touch an already hidden panel.
library;

import '../../core/theme/overlay_design_spec.dart'
    show OverlayBackground, OverlaySizeVariant, OverlayWave;
import 'floating_overlay_controller_interface.dart';

class OverlayShellGate {
  bool _lastVisible = false;
  OverlaySizeVariant? _lastSize;
  OverlayBackground? _lastBackground;
  OverlayWave? _lastWave;
  bool _sentAny = false;

  /// Returns true when [snapshot] should be sent to the shell, and records it
  /// as the shell's latest state when it is.
  bool shouldSend(FloatingOverlaySnapshot snapshot) {
    if (snapshot.visible) {
      _record(snapshot);
      return true;
    }

    final needed =
        !_sentAny ||
        _lastVisible ||
        _lastSize != snapshot.size ||
        _lastBackground != snapshot.background ||
        _lastWave != snapshot.wave;
    if (needed) _record(snapshot);
    return needed;
  }

  void _record(FloatingOverlaySnapshot snapshot) {
    _sentAny = true;
    _lastVisible = snapshot.visible;
    _lastSize = snapshot.size;
    _lastBackground = snapshot.background;
    _lastWave = snapshot.wave;
  }
}
