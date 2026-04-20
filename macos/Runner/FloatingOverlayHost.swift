import Cocoa
import FlutterMacOS

/// MethodChannel host for the floating recording overlay on macOS.
///
/// Manages the lifecycle of a [FloatingOverlayPanel] and routes
/// method calls/events between Dart and the native view.
class FloatingOverlayHost {
  private var channel: FlutterMethodChannel
  private var panel: FloatingOverlayPanel?
  private var overlayView: FloatingOverlayView?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.floating_overlay",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 100
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 100
      let w = (args["width"] as? NSNumber)?.doubleValue ?? 320
      let h = (args["height"] as? NSNumber)?.doubleValue ?? 180
      show(x: x, y: y, width: w, height: h)
      result(nil)

    case "hide":
      panel?.orderOut(nil)
      result(nil)

    case "updateSnapshot":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      if let stateStr = args["state"] as? String,
         let state = OverlayRecordingState(rawValue: stateStr) {
        overlayView?.recordingState = state
      }
      if let text = args["transcript"] as? String {
        overlayView?.transcriptText = text
      }
      if let level = (args["audioLevel"] as? NSNumber)?.floatValue {
        overlayView?.audioLevel = level
      }
      if let progress = (args["progress"] as? NSNumber)?.doubleValue {
        overlayView?.progressValue = progress
      }
      if let isDark = args["isDark"] as? Bool {
        overlayView?.isDark = isDark
      }
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
      panel?.setFrameOrigin(NSPoint(x: x, y: y))
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

  private func show(x: Double, y: Double, width: Double, height: Double) {
    if panel == nil {
      let p = FloatingOverlayPanel(width: CGFloat(width), height: CGFloat(height))
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
        self?.channel.invokeMethod("onContextMenu", arguments: ["itemId": itemId])
      }

      p.contentView = view
      panel = p
      overlayView = view
    }

    if let p = panel {
      let frame = NSRect(x: x, y: y, width: width, height: height)
      p.setFrame(frame, display: true)
      overlayView?.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }
    panel?.orderFront(nil)
  }
}
