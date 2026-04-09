/// Events emitted by the native floating overlay window.
sealed class FloatingOverlayEvent {
  const FloatingOverlayEvent();
}

/// The overlay was dragged to a new position (logical pixels).
class OverlayDragEnded extends FloatingOverlayEvent {
  const OverlayDragEnded(this.x, this.y, this.anchorMode);
  final double x;
  final double y;
  final String anchorMode;
}

/// The close button (✕) was clicked.
class OverlayCloseClicked extends FloatingOverlayEvent {
  const OverlayCloseClicked();
}

/// The overlay body area was clicked (not a button).
class OverlayBodyClicked extends FloatingOverlayEvent {
  const OverlayBodyClicked();
}

/// The retry button was clicked (error state).
class OverlayRetryClicked extends FloatingOverlayEvent {
  const OverlayRetryClicked();
}

/// A context menu action was selected (compact right-click).
class OverlayContextMenuAction extends FloatingOverlayEvent {
  const OverlayContextMenuAction(this.action);
  final String action;
}
