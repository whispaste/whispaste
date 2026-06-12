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
///   exactly as before (`updateSnapshot` / `setWaveformBars` /
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
  private var pendingAnchorMode: String = "topCenter"
  private var isCompact: Bool = false
  private var contextMenuItems: [(id: String, label: String)] = []
  private var screenObserver: NSObjectProtocol?

  // The render engine boots asynchronously: its Dart MethodChannel handler is
  // only ready a few runloop turns after `engine.run`. Until the engine sends
  // `ready`, relayed messages would be dropped — so we cache the latest render
  // state here and flush it the moment the engine announces itself.
  private var renderReady: Bool = false
  private var latestSnapshotArgs: [String: Any]?
  private var latestBars: [String: Any]?

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
      latestBars = args
      if renderReady {
        renderChannel?.invokeMethod("setWaveformBars", arguments: args)
      }
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
    let sizeChanged = compact != isCompact
    // Set the size class BEFORE lazy-creating the panel so the very first
    // (possibly compact) snapshot sizes the shell correctly instead of
    // creating it at normal size and resizing a frame later.
    isCompact = compact

    if visible && panel == nil {
      ensurePanel()
    } else if sizeChanged {
      // Re-size + re-anchor the existing shell on a compact ↔ normal switch.
      resizePanelToContent()
    }

    // Cache + relay (relay no-ops until the engine is ready; flushed on ready).
    latestSnapshotArgs = args
    if renderReady {
      renderChannel?.invokeMethod("updateSnapshot", arguments: args)
    }

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
    renderReady = false

    // Boot the dedicated overlay engine and host its view in the panel.
    // macOS `runWithEntrypoint:` resolves the name only against the ROOT
    // library, so `floatingOverlayMain` is declared in Dart's main.dart (it
    // delegates into the overlay render app). There is no `libraryURI:`
    // variant on macOS FlutterEngine.
    let engine = FlutterEngine(name: "floating_overlay", project: nil)
    let didRun = engine.run(withEntrypoint: "floatingOverlayMain")
    NSLog("[overlay] ensurePanel: engine.run(floatingOverlayMain) -> \(didRun)")

    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    // REAL surface transparency: must be set so the engine composites onto a
    // clear surface instead of opaque black. Set before the view is shown.
    vc.backgroundColor = .clear

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

    panel = p
    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh
    NSLog("[overlay] ensurePanel: panel created, content \(size.width)x\(size.height)")

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
    // Re-anchor: a top/bottom-centre overlay must stay centred after the size
    // changes; a dragged (topLeft) overlay keeps its raw origin.
    let resolved = resolvePosition(
      x: Double(origin.x), y: Double(origin.y), anchorMode: pendingAnchorMode)
    p.setFrameOrigin(resolved)
  }

  // MARK: - Render-engine interactions (overlay engine → native → main engine)

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      // The render engine's Dart handler is live — flush the cached state so
      // the first visible frame is never lost to the boot race.
      NSLog("[overlay] render engine ready — flushing cached state")
      renderReady = true
      if let bars = latestBars {
        renderChannel?.invokeMethod("setWaveformBars", arguments: bars)
      }
      if let snap = latestSnapshotArgs {
        renderChannel?.invokeMethod("updateSnapshot", arguments: snap)
      }
      result(nil)

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
    renderReady = false
    latestSnapshotArgs = nil
    latestBars = nil
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
