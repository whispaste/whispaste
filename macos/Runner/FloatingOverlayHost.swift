import Cocoa
import FlutterMacOS

/// MethodChannel host for the floating recording overlay on macOS.
///
/// ADR 0002 (Approach 1 / Variant B): the overlay window is a lifecycle-only
/// shell. It no longer draws — it hosts a dedicated **second Flutter engine**
/// (entrypoint `floatingOverlayMain`) inside a transparent, non-activating
/// `FloatingOverlayPanel` and forwards the main engine's render state to it.
///
/// Seam:
/// - The app's MAIN engine talks to this host over `com.whispaste.floating_overlay`
///   exactly as before (`updateSnapshot` / `setWaveformBars` / `setOpacity` /
///   `setPosition` / `setContextMenuItems`).
/// - This host relays the render payloads to the overlay engine over the
///   private `com.whispaste.floating_overlay_render` channel, and translates
///   the overlay engine's coarse interactions (`startDrag` / `bodyClicked` /
///   `showContextMenu`) back into the existing main-engine events
///   (`onDragEnded` / `onBodyClicked` / `onContextMenu`).
///
/// The panel is lazily created on the first `updateSnapshot` with
/// `visible: true` — matching the Windows C++ host behavior.
class FloatingOverlayHost {
  private var channel: FlutterMethodChannel
  private var panel: FloatingOverlayPanel?

  // Secondary Flutter engine that renders the shared FloatingOverlayView.
  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?

  private var pendingPosition: NSPoint?
  private var pendingOpacity: Double = 1.0
  private var pendingAnchorMode: String = "topCenter"
  private var isCompact: Bool = false
  private var contextMenuItems: [(id: String, label: String)] = []
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

    case "setWaveformBars":
      // Relay the pre-computed bar array straight to the render engine; the
      // shell keeps no waveform state of its own.
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      renderChannel?.invokeMethod("setWaveformBars", arguments: args)
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
      contextMenuItems = items.compactMap { item in
        guard let id = item["id"] as? String,
              let label = item["label"] as? String else { return nil }
        return (id: id, label: label)
      }
      result(nil)

    case "setOpacity":
      guard let args = call.arguments as? [String: Any],
            let opacity = (args["opacity"] as? NSNumber)?.doubleValue else {
        result(nil)
        return
      }
      pendingOpacity = opacity
      renderChannel?.invokeMethod("setOpacity", arguments: ["opacity": opacity])
      result(nil)

    case "destroy":
      teardown()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - updateSnapshot (lazy-creates panel + engine, handles show/hide)

  private func handleUpdateSnapshot(_ args: [String: Any]) {
    let visible = args["visible"] as? Bool ?? false
    let compact = args["compact"] as? Bool ?? false

    // Lazy-create the panel + render engine on first visible snapshot.
    if visible && panel == nil {
      ensurePanel()
    }

    // Resize the shell if the size class changed (compact ↔ normal).
    if compact != isCompact {
      isCompact = compact
      resizePanelToContent()
    }

    // Relay the full snapshot to the render engine.
    renderChannel?.invokeMethod("updateSnapshot", arguments: args)

    // Show or hide the native shell.
    if visible {
      panel?.orderFront(nil)
    } else {
      panel?.orderOut(nil)
    }
  }

  // MARK: - Panel + render-engine creation

  /// Full native-window size = pill box + 8pt shadow padding per side.
  /// Mirrors `OverlayDesignSpec.windowSize` (Dart). Normal `346 × 80`,
  /// compact `236 × 56`. The shell MUST match this so the painted soft shadow
  /// is not clipped.
  private func contentSize() -> NSSize {
    return isCompact
      ? NSSize(width: 236, height: 56)
      : NSSize(width: 346, height: 80)
  }

  private func ensurePanel() {
    let size = contentSize()

    // Boot the dedicated overlay engine and host its view in the panel.
    let engine = FlutterEngine(name: "floating_overlay", project: nil)
    engine.run(withEntrypoint: "floatingOverlayMain")
    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.floating_overlay_render",
      binaryMessenger: engine.binaryMessenger
    )
    renderCh.setMethodCallHandler { [weak self] call, result in
      self?.handleRenderCall(call, result: result)
    }

    let p = FloatingOverlayPanel(width: size.width, height: size.height)
    p.contentViewController = vc
    p.setContentSize(size)
    // REAL surface transparency: without a clear VC background the engine
    // composites onto opaque black and the pill sits in a black box.
    vc.backgroundColor = .clear

    panel = p
    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh

    // Apply any opacity that arrived before the engine existed.
    renderCh.invokeMethod("setOpacity", arguments: ["opacity": pendingOpacity])

    // Apply pending position if one was set before the panel existed.
    if let pos = pendingPosition {
      p.setFrameOrigin(pos)
      pendingPosition = nil
    }
  }

  private func resizePanelToContent() {
    guard let p = panel else { return }
    let origin = p.frame.origin
    p.setContentSize(contentSize())
    p.setFrameOrigin(origin)
  }

  // MARK: - Render-engine interactions (overlay engine → native → main engine)

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startDrag":
      if let event = NSApp.currentEvent, let p = panel {
        p.performDrag(with: event)
        // The drag loop has ended — persist the final origin via the existing
        // main-engine event (topLeft = raw coordinates).
        let origin = p.frame.origin
        pendingAnchorMode = "topLeft"
        channel.invokeMethod("onDragEnded", arguments: [
          "x": Double(origin.x),
          "y": Double(origin.y),
          "anchorMode": "topLeft",
        ])
      }
      result(nil)

    case "bodyClicked":
      channel.invokeMethod("onBodyClicked", arguments: nil)
      result(nil)

    case "showContextMenu":
      showContextMenu()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showContextMenu() {
    guard !contextMenuItems.isEmpty else { return }
    let menu = NSMenu()
    for item in contextMenuItems {
      let menuItem = NSMenuItem(
        title: item.label,
        action: #selector(contextMenuItemSelected(_:)),
        keyEquivalent: ""
      )
      menuItem.target = self
      menuItem.representedObject = item.id
      menu.addItem(menuItem)
    }
    if let event = NSApp.currentEvent, let view = renderViewController?.view {
      NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
  }

  @objc private func contextMenuItemSelected(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel.invokeMethod("onContextMenu", arguments: ["action": id])
  }

  // MARK: - Teardown

  private func teardown() {
    if let obs = screenObserver {
      NotificationCenter.default.removeObserver(obs)
      screenObserver = nil
    }
    renderChannel?.setMethodCallHandler(nil)
    panel?.close()
    panel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    channel.setMethodCallHandler(nil)
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
    let size = contentSize()
    let margin: CGFloat = 16

    switch anchorMode {
    case "topCenter":
      // NSView Y-up: "top" means near maxY of visible frame.
      let px = visibleFrame.origin.x + (visibleFrame.width - size.width) / 2
      let py = visibleFrame.maxY - size.height - margin
      return NSPoint(x: px, y: py)

    case "bottomCenter":
      // NSView Y-up: "bottom" means near minY of visible frame.
      let px = visibleFrame.origin.x + (visibleFrame.width - size.width) / 2
      let py = visibleFrame.origin.y + margin
      return NSPoint(x: px, y: py)

    default: // "topLeft" — raw coordinates
      return NSPoint(x: x, y: y)
    }
  }
}
