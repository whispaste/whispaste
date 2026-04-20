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

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.floating_overlay",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
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

    case "setPosition":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
      if let p = panel {
        p.setFrameOrigin(NSPoint(x: x, y: y))
      } else {
        pendingPosition = NSPoint(x: x, y: y)
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

    // Update view properties.
    if let stateStr = args["state"] as? String,
       let state = OverlayRecordingState(rawValue: stateStr) {
      overlayView?.recordingState = state
    }
    if let label = args["label"] as? String {
      overlayView?.labelText = label
    }
    if let text = args["transcript"] as? String {
      overlayView?.transcriptText = text
    }
    if let elapsed = args["elapsed"] as? String {
      overlayView?.elapsedText = elapsed
    }
    if let hint = args["hint"] as? String {
      overlayView?.hintText = hint
    }
    if let errorMessage = args["errorMessage"] as? String {
      overlayView?.errorMessage = errorMessage
    }
    if let progress = (args["progress"] as? NSNumber)?.doubleValue {
      overlayView?.progressValue = progress
    }
    if let isDark = args["isDark"] as? Bool {
      overlayView?.isDark = isDark
    }
    if let showRetry = args["showRetry"] as? Bool {
      overlayView?.showRetry = showRetry
    }

    // Show or hide.
    if visible {
      panel?.orderFront(nil)
    } else {
      panel?.orderOut(nil)
    }
  }

  // MARK: - Panel creation

  private func ensurePanel() {
    let width: CGFloat = 320
    let height: CGFloat = 180
    let p = FloatingOverlayPanel(width: width, height: height)
    let view = FloatingOverlayView(
      frame: NSRect(x: 0, y: 0, width: width, height: height)
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
}
