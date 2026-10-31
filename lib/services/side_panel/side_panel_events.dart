import 'side_panel_snapshot.dart';

/// Events emitted by the native side-panel window.
sealed class SidePanelEvent {
  const SidePanelEvent();
}

/// A row was clicked. [section]/[id] identify it within the snapshot that
/// was showing when the click happened -- the owning [SidePanelService]
/// resolves [id] against the live data it built that snapshot from.
class SidePanelRowClicked extends SidePanelEvent {
  const SidePanelRowClicked(this.section, this.id);
  final SidePanelSection section;
  final String id;
}

/// The pointer left the panel (and its edge sensor zone) -- the panel
/// should close.
class SidePanelHoverLeft extends SidePanelEvent {
  const SidePanelHoverLeft();
}

/// The pointer entered a monitor's edge sensor zone (issue 04+) -- the
/// panel should open. Fired by the native sensor strip, not by the panel
/// window itself (which only ever reports [SidePanelHoverLeft]).
class SidePanelHoverEntered extends SidePanelEvent {
  const SidePanelHoverEntered();
}
