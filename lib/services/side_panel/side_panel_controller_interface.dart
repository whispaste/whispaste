/// Pure interface for the side-panel controller. Kept separate from the
/// implementation so a future platform-specific variant (if issues 04-06
/// ever need one) avoids a circular dependency, mirroring
/// `floating_overlay_controller_interface.dart`.
library;

import 'side_panel_events.dart';
import 'side_panel_snapshot.dart';

/// Platform-agnostic interface for the native side-panel window(s) -- one
/// per monitor (see PRD.md "Trigger-Mechanismus").
///
/// Layer 2 in the three-layer architecture, mirroring
/// [FloatingOverlayController]: Dart owns all state -- every field on a
/// [SidePanelSnapshot] is pre-resolved before it is sent -- and the native
/// side is a dumb renderer.
abstract class SidePanelController {
  /// Sends the complete panel content for rendering. The native host
  /// lazy-creates its window(s) on the first call with `visible: true`.
  Future<void> updateSnapshot(SidePanelSnapshot snapshot);

  /// Stream of events from the native side-panel window(s).
  Stream<SidePanelEvent> get events;

  /// Destroys the native window(s) and releases resources.
  Future<void> dispose();
}
