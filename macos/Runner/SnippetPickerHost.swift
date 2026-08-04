import Cocoa
import FlutterMacOS
import os.log

/// MethodChannel host for the Snippet-Picker on macOS (dictation-automations
/// ticket 06).
///
/// Same shell architecture as `FloatingButtonHost`/`FloatingOverlayHost`
/// (ADR 0002): the panel is a lifecycle-only shell hosting a **second Flutter
/// engine** (entrypoint `snippetPickerMain`) that paints the searchable
/// snippet list. Unlike those two, this is a **one-shot** surface — `show`
/// opens the panel with a fixed item list and returns immediately; the
/// eventual pick (or cancellation) arrives later as `onItemSelected` /
/// `onCancelled` on this same channel, entirely decoupled from the call that
/// opened it. There is no continuous state relay to build/tear down per
/// frame, which is why this host skips the retry/stall-recovery machinery
/// `FloatingOverlayHost` needs for its 30Hz relay — a picker is opened
/// rarely, and a slow boot only delays the panel's first appearance, not an
/// ongoing visual.
///
/// Seam:
/// - The main engine talks to this host over `com.whispaste.snippet_picker`
///   (`show` / `hide` / `destroy`, plus the `onItemSelected` / `onCancelled` /
///   `onRenderEngineDiagnostic` events it sends back).
/// - This host relays the item list to the picker engine over the private
///   `com.whispaste.snippet_picker_render` channel, and translates the picker
///   engine's `selectItem` / `cancel` calls back into the main-engine events.
///
/// The panel is lazily created on first `show`, then reused across pickers
/// for the app session — matching `FloatingButtonHost`'s pattern, so only the
/// very first trigger pays the engine-boot cost.
class SnippetPickerHost: NSObject, NSWindowDelegate {
  private static let logger = OSLog(subsystem: "com.whispaste.snippet_picker", category: "SnippetPickerHost")

  /// Fixed panel content size — the placeholder Dart UI doesn't yet report a
  /// measured size back, so this host picks a reasonable default. Revisit
  /// once the Fable design pass lands (ticket 06) if it needs to vary.
  private static let contentSize = NSSize(width: 360, height: 420)

  private var channel: FlutterMethodChannel

  private var panel: SnippetPickerPanel?
  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?

  private var renderReady = false
  private var pendingItems: [[String: String]]?

  /// Guards [dismiss] against a re-entrant second call: `orderOut(nil)`
  /// resigns the panel's key status, which fires `windowDidResignKey` — that
  /// would otherwise call [dismiss] a second time (with `fireCancelled:
  /// true`) on top of an explicit `selectItem`/`hide` dismissal. AppKit does
  /// not guarantee the resign-key notification fires strictly after
  /// `isVisible` flips to false, so gating on `p.isVisible` alone isn't
  /// reliable — this latch is.
  private var isDismissing = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.snippet_picker",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: String]] else {
        result(nil)
        return
      }
      show(items: items)
      result(nil)

    case "hide":
      dismiss(fireCancelled: false)
      result(nil)

    case "destroy":
      teardown()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Show / dismiss

  /// Reads the cursor position natively (`NSEvent.mouseLocation`, AppKit's
  /// own bottom-left-origin space) rather than accepting x/y from Dart.
  ///
  /// An earlier version took the position from Dart's `ScreenRetriever`,
  /// which converts to a top-down y (`visibleHeight - mouseLocation.y`) for
  /// Flutter's own coordinate space — mixing that back into this AppKit-
  /// native positioning code silently mirrored the panel vertically
  /// whenever the cursor wasn't near vertical screen-center (where the two
  /// conventions happen to coincide, which is why a live test done there
  /// didn't catch it). Reading the cursor here avoids the cross-convention
  /// conversion entirely.
  private func show(items: [[String: String]]) {
    ensurePanel()
    guard let p = panel else { return }

    let cursor = NSEvent.mouseLocation
    // Anchor the panel's top-left at the cursor — it opens downward/rightward,
    // matching typical context-menu placement. Screen selection (for
    // clamping) uses the raw cursor point, not the already-offset origin —
    // picking the display the user is actually pointing at, not whichever
    // display the arithmetic happens to land the offset point on.
    let origin = clampToVisibleScreen(
      cursor: cursor,
      desiredOrigin: NSPoint(x: cursor.x, y: cursor.y - Self.contentSize.height),
      size: Self.contentSize
    )
    p.setFrameOrigin(origin)

    if renderReady {
      renderChannel?.invokeMethod("setItems", arguments: ["items": items])
    } else {
      pendingItems = items
    }

    p.orderFrontRegardless()
    p.makeKey()
  }

  /// Closes the panel and — unless [fireCancelled] is false (an explicit
  /// `hide()` from Dart, or a pick already in flight) — reports the
  /// dismissal to the main engine.
  ///
  /// Orders the panel out **before** invoking the callback so a snippet
  /// insert's native `typeText`/re-activation of the target app never races
  /// this panel's own teardown (see `SnippetPickerPanel`'s doc comment).
  private func dismiss(fireCancelled: Bool) {
    guard !isDismissing, let p = panel, p.isVisible else { return }
    isDismissing = true
    defer { isDismissing = false }
    p.orderOut(nil)
    if fireCancelled {
      channel.invokeMethod("onCancelled", arguments: nil)
    }
  }

  // MARK: - Positioning

  /// Clamps [desiredOrigin] (top-left-anchored) so the panel stays fully
  /// within some connected screen's visible frame — same algorithm as
  /// `FloatingOverlayHost.clampToVisibleScreen`, but the target screen is
  /// picked from [cursor] itself rather than from [desiredOrigin]: the
  /// origin is already offset upward by the panel's height, so on a
  /// multi-display setup with screens of different heights, selecting by
  /// the offset point could pick the wrong (e.g. neighbouring) display.
  private func clampToVisibleScreen(cursor: NSPoint, desiredOrigin: NSPoint, size: NSSize) -> NSPoint {
    guard let target = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
      ?? nearestScreen(to: cursor) else {
      return desiredOrigin
    }

    let visible = target.visibleFrame
    let maxX = max(visible.minX, visible.maxX - size.width)
    let maxY = max(visible.minY, visible.maxY - size.height)
    let clampedX = min(max(desiredOrigin.x, visible.minX), maxX)
    let clampedY = min(max(desiredOrigin.y, visible.minY), maxY)
    return NSPoint(x: clampedX, y: clampedY)
  }

  private func nearestScreen(to point: NSPoint) -> NSScreen? {
    NSScreen.screens.min { distance(point, $0.frame) < distance(point, $1.frame) }
  }

  private func distance(_ point: NSPoint, _ rect: NSRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return (dx * dx + dy * dy).squareRoot()
  }

  // MARK: - Panel + render-engine creation

  private func ensurePanel() {
    guard panel == nil else { return }
    let p = SnippetPickerPanel(contentSize: Self.contentSize)
    p.delegate = self
    panel = p
    bootRenderEngine()
    os_log("ensurePanel: panel created", log: Self.logger, type: .info)
  }

  private func bootRenderEngine() {
    guard let p = panel else { return }
    renderReady = false

    // macOS `runWithEntrypoint:` resolves the name only against the ROOT
    // library, so `snippetPickerMain` is declared in Dart's main.dart (it
    // delegates into the render app) — same constraint as the button/overlay
    // engines.
    let engine = FlutterEngine(name: "snippet_picker", project: nil)
    let didRun = engine.run(withEntrypoint: "snippetPickerMain")
    os_log("bootRenderEngine: engine.run(snippetPickerMain) -> %{public}@", log: Self.logger, type: .info, didRun ? "true" : "false")

    guard didRun else {
      renderEngine = engine
      return
    }

    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    vc.backgroundColor = .clear

    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.snippet_picker_render",
      binaryMessenger: engine.binaryMessenger
    )
    renderCh.setMethodCallHandler { [weak self] call, result in
      self?.handleRenderCall(call, result: result)
    }

    p.contentViewController = vc
    p.setContentSize(Self.contentSize)

    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh
  }

  // MARK: - Render-engine interactions (picker engine → native → main engine)

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      os_log("render engine ready", log: Self.logger, type: .info)
      renderReady = true
      if let items = pendingItems {
        renderChannel?.invokeMethod("setItems", arguments: ["items": items])
        pendingItems = nil
      }
      result(nil)

    case "selectItem":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String else {
        result(nil)
        return
      }
      dismiss(fireCancelled: false)
      channel.invokeMethod("onItemSelected", arguments: ["id": id])
      result(nil)

    case "cancel":
      dismiss(fireCancelled: true)
      result(nil)

    case "reportError":
      if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
        os_log("render engine reported an error: %{public}@", log: Self.logger, type: .error, message)
        channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - NSWindowDelegate

  /// Clicking outside the panel resigns its key status — treat that the same
  /// as pressing Esc: close and report a cancellation.
  func windowDidResignKey(_ notification: Notification) {
    dismiss(fireCancelled: true)
  }

  // MARK: - Teardown

  private func teardown() {
    renderChannel?.setMethodCallHandler(nil)
    panel?.delegate = nil
    panel?.close()
    panel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderReady = false
    pendingItems = nil
    channel.setMethodCallHandler(nil)
  }
}
