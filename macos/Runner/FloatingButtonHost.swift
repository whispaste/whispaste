import Cocoa
import FlutterMacOS

/// MethodChannel host for the floating button on macOS.
///
/// Manages the lifecycle of a [FloatingButtonPanel] and routes
/// method calls between Dart and the native panel/view.
class FloatingButtonHost {
  private var channel: FlutterMethodChannel
  private var panel: FloatingButtonPanel?
  private var buttonView: FloatingButtonView?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.floating_button",
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
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 200
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 200
      let size = (args["size"] as? NSNumber)?.doubleValue ?? 56
      show(x: x, y: y, size: size)
      result(nil)

    case "hide":
      panel?.orderOut(nil)
      result(nil)

    case "setState":
      guard let args = call.arguments as? [String: Any],
            let stateName = args["state"] as? String,
            let state = FloatingButtonVisualState(rawValue: stateName) else {
        result(nil)
        return
      }
      buttonView?.visualState = state
      result(nil)

    case "setTheme":
      guard let args = call.arguments as? [String: Any],
            let isDark = args["isDark"] as? Bool else {
        result(nil)
        return
      }
      buttonView?.isDark = isDark
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

    case "setSize":
      guard let args = call.arguments as? [String: Any],
            let size = (args["size"] as? NSNumber)?.doubleValue else {
        result(nil)
        return
      }
      if let p = panel {
        let margin: Double = 28 // 14pt each side — must match show()
        let totalSize = size + margin
        var frame = p.frame
        frame.size = NSSize(width: totalSize, height: totalSize)
        p.setFrame(frame, display: true)
        // Also resize the button view so the rendering updates.
        buttonView?.frame = NSRect(
          x: margin / 2, y: margin / 2,
          width: size, height: size
        )
        buttonView?.needsDisplay = true
      }
      result(nil)

    case "setOpacity":
      guard let args = call.arguments as? [String: Any],
            let opacity = (args["opacity"] as? NSNumber)?.doubleValue else {
        result(nil)
        return
      }
      buttonView?.masterOpacity = CGFloat(opacity)
      result(nil)

    case "getPosition":
      guard let p = panel else {
        result(nil)
        return
      }
      let origin = p.frame.origin
      result(["x": origin.x, "y": origin.y])

    case "setContextMenuItems":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: Any]] else {
        result(nil)
        return
      }
      buttonView?.contextMenuItems = items
      result(nil)

    case "destroy":
      panel?.close()
      panel = nil
      buttonView = nil
      channel.setMethodCallHandler(nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(x: Double, y: Double, size: Double) {
    // Add shadow margin so the view has room for multi-layer soft shadows
    let margin: Double = 28 // 14pt each side
    let totalSize = size + margin

    if panel == nil {
      let p = FloatingButtonPanel(size: CGFloat(totalSize))
      let view = FloatingButtonView(frame: NSRect(x: 0, y: 0, width: totalSize, height: totalSize))

      // Wire native → Dart events.
      view.onClicked = { [weak self] in
        self?.channel.invokeMethod("onClicked", arguments: nil)
      }
      view.onSecondaryClicked = { [weak self] in
        self?.channel.invokeMethod("onSecondaryClicked", arguments: nil)
      }
      view.onContextMenu = { [weak self] id in
        self?.channel.invokeMethod("onContextMenu", arguments: ["id": id])
      }
      view.onDragEnded = { [weak self] dx, dy in
        self?.channel.invokeMethod("onDragEnded", arguments: ["x": dx, "y": dy])
      }

      p.contentView = view
      panel = p
      buttonView = view
    }

    // Offset by half-margin so the logical center aligns with (x,y)
    let offset = margin / 2
    panel?.setFrameOrigin(NSPoint(x: x - offset, y: y - offset))
    panel?.orderFront(nil)
  }
}
