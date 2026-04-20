/// Events emitted by the native floating button window.
sealed class FloatingButtonEvent {
  const FloatingButtonEvent();
}

/// The button was clicked (left click inside the circle).
class FloatingButtonClicked extends FloatingButtonEvent {
  const FloatingButtonClicked();
}

/// The button was right-clicked.
class FloatingButtonSecondaryClicked extends FloatingButtonEvent {
  const FloatingButtonSecondaryClicked();
}

/// A context menu item was selected (right-click menu).
class FloatingButtonContextMenuSelected extends FloatingButtonEvent {
  const FloatingButtonContextMenuSelected(this.id);
  final String id;
}

/// The button was dragged to a new position (logical pixels).
class FloatingButtonDragEnded extends FloatingButtonEvent {
  const FloatingButtonDragEnded(this.x, this.y);
  final double x;
  final double y;
}
