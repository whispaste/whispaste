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

/// The native shell reported a diagnostic about the dedicated render-engine
/// boot handshake — see [FloatingButtonHost.swift]'s `renderReady` race (the
/// same boot-race class as `OverlayRenderEngineDiagnostic` for the recording
/// overlay).
class FloatingButtonRenderEngineDiagnostic extends FloatingButtonEvent {
  const FloatingButtonRenderEngineDiagnostic(this.message, {required this.isError});
  final String message;
  final bool isError;
}
