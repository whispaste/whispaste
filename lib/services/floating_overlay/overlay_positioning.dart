/// Overlay pill sizing.
///
/// The size lookup reads from the single source of truth
/// ([OverlayDesignSpec]); this module owns no geometry constants of its own.
///
/// Anchor resolution and screen-edge clamping used to live here too (ADR
/// 0002, issue 05 AC3 originally intended one shared Dart implementation
/// consumed by all three native shells), but in practice each native shell
/// (macOS `FloatingOverlayHost.swift`, Windows `floating_overlay_host.cpp`,
/// Linux `floating_overlay_host.cc`) ended up with its own positioning/
/// clamping implementation, so the Dart versions were never called from
/// production and have been removed — see those files for the current
/// (now cross-platform-aligned) anchor and clamp logic.
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
}
