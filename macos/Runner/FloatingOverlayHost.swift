import Cocoa
import FlutterMacOS

/// MethodChannel host for the floating recording overlay on macOS.
///
/// Manages the lifecycle of a [FloatingOverlayPanel] and routes
/// method calls/events between Dart and the native view.
///
/// The panel is lazily created on the first `updateSnapshot` call with
/// `visible: true` — matching the Windows C++ host behavior.
class FloatingOverlayHost {
  private var channel: FlutterMethodChannel
  private var panel: FloatingOverlayPanel?
  private var overlayView: FloatingOverlayView?
  private var pendingPosition: NSPoint?
  private var pendingOpacity: CGFloat = 1.0
  private var pendingAnchorMode: String = "topCenter"
  private var screenObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.floating_overlay",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
    observeScreenChanges()
  }

  /// Observes monitor connect/disconnect events and repositions the overlay
  /// so it stays on-screen — matching the Windows WM_DISPLAYCHANGE behavior.
  private func observeScreenChanges() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.validateOnScreen()
    }
  }

  /// Recalculates the overlay position for the current screen geometry.
  private func validateOnScreen() {
    guard let p = panel, p.isVisible else { return }
    // Re-resolve position using the last anchor mode.
    let origin = p.frame.origin
    let resolved = resolvePosition(x: Double(origin.x), y: Double(origin.y), anchorMode: pendingAnchorMode)
    if resolved != origin {
      p.setFrameOrigin(resolved)
      channel.invokeMethod("onDragEnded", arguments: [
        "x": Double(resolved.x),
        "y": Double(resolved.y),
        "anchorMode": pendingAnchorMode,
      ])
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateSnapshot":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      handleUpdateSnapshot(args)
      result(nil)

    case "setAudioLevel":
      guard let args = call.arguments as? [String: Any],
            let level = (args["level"] as? NSNumber)?.floatValue else {
        result(nil)
        return
      }
      overlayView?.audioLevel = level
      result(nil)

    case "setWaveformBars":
      // Additive path (issue 05): Dart pushes a pre-computed bar array
      // (length kBarCount = 30). When set, the view renders stateless from
      // this array; the legacy setAudioLevel ring-buffer is bypassed but
      // not removed in this slice.
      guard let args = call.arguments as? [String: Any],
            let rawBars = args["bars"] as? [Any] else {
        result(nil)
        return
      }
      let bars: [Double] = rawBars.compactMap { ($0 as? NSNumber)?.doubleValue }
      overlayView?.waveformBars = bars
      result(nil)

    case "setPosition":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
      let anchorMode = args["anchorMode"] as? String ?? "topLeft"
      pendingAnchorMode = anchorMode
      let resolved = resolvePosition(x: x, y: y, anchorMode: anchorMode)
      if let p = panel {
        p.setFrameOrigin(resolved)
      } else {
        pendingPosition = resolved
      }
      result(nil)

    case "setContextMenuItems":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: Any]] else {
        result(nil)
        return
      }
      overlayView?.contextMenuItems = items
      result(nil)

    case "setOpacity":
      guard let args = call.arguments as? [String: Any],
            let opacity = (args["opacity"] as? NSNumber)?.doubleValue else {
        result(nil)
        return
      }
      pendingOpacity = CGFloat(opacity)
      overlayView?.masterOpacity = CGFloat(opacity)
      result(nil)

    case "destroy":
      if let obs = screenObserver {
        NotificationCenter.default.removeObserver(obs)
        screenObserver = nil
      }
      panel?.close()
      panel = nil
      overlayView = nil
      channel.setMethodCallHandler(nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - updateSnapshot (lazy-creates panel, handles visible show/hide)

  private func handleUpdateSnapshot(_ args: [String: Any]) {
    let visible = args["visible"] as? Bool ?? false

    // Lazy-create the panel on first visible snapshot.
    if visible && panel == nil {
      ensurePanel()
    }

    // Apply all snapshot fields with defaults, matching the Windows host
    // which rebuilds the entire OverlaySnapshot from scratch each call.
    if let stateStr = args["state"] as? String,
       let state = OverlayRecordingState(rawValue: stateStr) {
      overlayView?.recordingState = state
    }
    overlayView?.labelText = args["label"] as? String ?? ""
    overlayView?.transcriptText = args["transcript"] as? String ?? ""
    overlayView?.elapsedText = args["elapsed"] as? String ?? ""
    overlayView?.hintText = args["hint"] as? String ?? ""
    overlayView?.errorMessage = args["errorMessage"] as? String
    overlayView?.showRetry = args["showRetry"] as? Bool ?? false
    overlayView?.progressValue = (args["progress"] as? NSNumber)?.doubleValue ?? 0
    overlayView?.isDark = args["isDark"] as? Bool ?? true
    overlayView?.isCompact = args["compact"] as? Bool ?? false

    // Show or hide.
    if visible {
      panel?.orderFront(nil)
    } else {
      panel?.orderOut(nil)
    }
  }

  // MARK: - Panel creation

  private func ensurePanel() {
    // Pill dimensions + shadow padding (28pt each side).
    let pillW: CGFloat = 380
    let pillH: CGFloat = 64
    let p = FloatingOverlayPanel(width: pillW, height: pillH)
    let totalW = pillW + 56
    let totalH = pillH + 56
    let view = FloatingOverlayView(
      frame: NSRect(x: 0, y: 0, width: totalW, height: totalH)
    )

    view.onDragEnded = { [weak self] dx, dy in
      self?.channel.invokeMethod("onDragEnded", arguments: ["x": dx, "y": dy])
    }
    view.onCloseClicked = { [weak self] in
      self?.channel.invokeMethod("onCloseClicked", arguments: nil)
    }
    view.onBodyClicked = { [weak self] in
      self?.channel.invokeMethod("onBodyClicked", arguments: nil)
    }
    view.onRetryClicked = { [weak self] in
      self?.channel.invokeMethod("onRetryClicked", arguments: nil)
    }
    view.onContextMenu = { [weak self] itemId in
      self?.channel.invokeMethod("onContextMenu", arguments: ["action": itemId])
    }

    view.masterOpacity = pendingOpacity

    p.contentView = view
    panel = p
    overlayView = view

    // Apply pending position if one was set before the panel existed.
    if let pos = pendingPosition {
      p.setFrameOrigin(pos)
      pendingPosition = nil
    }
  }

  // MARK: - Position resolution (anchor mode → screen coordinates)

  /// Compute the frame origin for the overlay based on anchor mode.
  ///
  /// Mirrors the Windows `RecalcPosition()` logic:
  /// - topCenter: centered horizontally, 16pt from top of visible frame
  /// - bottomCenter: centered horizontally, 16pt from bottom of visible frame
  /// - topLeft: use raw x/y as frame origin
  private func resolvePosition(x: Double, y: Double, anchorMode: String) -> NSPoint {
    guard let screen = NSScreen.main else {
      return NSPoint(x: x, y: y)
    }

    let visibleFrame = screen.visibleFrame
    // Panel width/height including shadow padding
    let pillW = (overlayView?.isCompact ?? false) ? CGFloat(280) : CGFloat(380)
    let pillH = (overlayView?.isCompact ?? false) ? CGFloat(40) : CGFloat(64)
    let totalW = pillW + 56
    let totalH = pillH + 56
    let margin: CGFloat = 16

    switch anchorMode {
    case "topCenter":
      // NSView Y-up: "top" means near maxY of visible frame
      let px = visibleFrame.origin.x + (visibleFrame.width - totalW) / 2
      let py = visibleFrame.maxY - totalH - margin
      return NSPoint(x: px, y: py)

    case "bottomCenter":
      // NSView Y-up: "bottom" means near minY of visible frame
      let px = visibleFrame.origin.x + (visibleFrame.width - totalW) / 2
      let py = visibleFrame.origin.y + margin
      return NSPoint(x: px, y: py)

    default: // "topLeft" — raw coordinates
      return NSPoint(x: x, y: y)
    }
  }
}
