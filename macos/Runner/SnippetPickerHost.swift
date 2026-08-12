import Carbon.HIToolbox
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
/// The panel is created once and reused across pickers for the app session.
/// It is **not** created lazily on the first `show` (the original
/// `FloatingButtonHost` pattern): booting a second Flutter engine costs a
/// Dart isolate spawn plus theme/L10n resolution and a warm-up frame —
/// seconds in a debug/JIT build — and paying that inside the `show` handler
/// put the entire cost between the user's hotkey press and the panel
/// appearing. [prewarm] moves it to a few seconds after launch instead, off
/// the visible-startup path and long before the first press. `show` still
/// calls [ensurePanel], so a missed or failed prewarm degrades to the old
/// lazy behaviour rather than to no picker at all.
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

  /// Start of the in-flight render-engine boot, so the `ready` handler can
  /// report how long the engine actually took to come up — the number that
  /// tells whether [prewarm] finished before the user's first hotkey press.
  private var renderBootStartedAt: DispatchTime?

  /// Guards [dismiss] against a re-entrant second call: `orderOut(nil)`
  /// resigns the panel's key status, which fires `windowDidResignKey` — that
  /// would otherwise call [dismiss] a second time (with `fireCancelled:
  /// true`) on top of an explicit `selectItem`/`hide` dismissal. AppKit does
  /// not guarantee the resign-key notification fires strictly after
  /// `isVisible` flips to false, so gating on `p.isVisible` alone isn't
  /// reliable — this latch is.
  private var isDismissing = false

  /// Local `keyDown` monitor that guarantees Escape closes the picker (live-
  /// test bug: Escape did nothing while the search field had focus).
  ///
  /// Root-caused empirically: a Dart widget test pumping the picker's
  /// `SnippetPickerBody` directly proves the Dart-side wiring is already
  /// correct — `Shortcuts` maps Escape to `_CancelIntent` → `onCancel`, and
  /// it fires reliably there, on macOS's own `DefaultTextEditingShortcuts`
  /// map (escape only reads as "do nothing, don't propagate further" on
  /// Apple platforms — this widget's own `Shortcuts` sits nearer the focused
  /// leaf and wins first). So the gap isn't in the Dart layer; it's between
  /// the raw macOS keyDown and the Flutter engine: the search field's
  /// keyboard focus is held by the render engine's embedded text-input proxy
  /// view (the object driving `NSTextInputClient` for IME/marked-text), and
  /// that view's own `-interpretKeyEvents:`/`-doCommandBySelector:` handling
  /// for Escape does not reliably keep forwarding it to Flutter's raw
  /// keyboard channel — the same channel that carries Enter's `onSubmitted`
  /// via a different, independent path (`TextInputAction.done`), which is
  /// why Enter already worked while Escape didn't.
  ///
  /// A local event monitor sidesteps that entirely: it runs at
  /// `NSApplication`'s event-dispatch stage, strictly before `-sendEvent:`
  /// hands the key to whatever the current first responder is (Flutter's
  /// text-input proxy or otherwise), so it does not depend on anything the
  /// embedded engine does or doesn't do with the key afterwards. Scoped to
  /// "this picker's own panel is key" so it never touches the main window or
  /// any other panel, and consumes the event (returns `nil`) once handled so
  /// the swallowed keystroke can't *also* reach the search field.
  private var escapeMonitor: Any?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.snippet_picker",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler(handle)
    installEscapeMonitor()
  }

  /// Installed once for the host's lifetime — the closure re-checks
  /// `panel`/`isKeyWindow` on every keystroke, so it is a safe no-op long
  /// before [ensurePanel] ever creates a panel.
  private func installEscapeMonitor() {
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let p = self.panel, p.isKeyWindow, event.keyCode == kVK_Escape else {
        return event
      }
      self.dismiss(fireCancelled: true)
      return nil
    }
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

  // MARK: - Prewarm

  /// Boots the panel and its render engine ahead of the first `show`,
  /// without putting anything on screen. Called once from `AppDelegate`, a
  /// short while after launch.
  ///
  /// Invisible by construction: [ensurePanel] only allocates the panel and
  /// attaches the render `FlutterViewController`; the `orderFrontRegardless`
  /// / `makeKey` pair that puts the panel on screen exists solely in [show],
  /// and a freshly allocated `NSPanel` stays off-screen until it is ordered
  /// in. Nothing is drawn, no window becomes key, and — the property
  /// `SnippetPickerPanel` is built around — WhisPaste never becomes
  /// frontmost, so `DesktopPasteHost.captureTarget()`'s stored paste target
  /// is untouched.
  ///
  /// Deliberately not guarded against a second call: [ensurePanel] is
  /// idempotent *and* re-attempts a failed boot, so calling this after a
  /// failed attempt is a retry rather than a no-op.
  func prewarm() {
    let startedAt = DispatchTime.now()
    ensurePanel()
    os_log(
      "prewarm: boot dispatched, %{public}@ ms on the main thread (engine readiness is reported separately)",
      log: Self.logger, type: .info, Self.elapsedMillis(since: startedAt)
    )
  }

  /// Milliseconds elapsed since [start], preformatted as a string — this
  /// file's `os_log` calls interpolate `%{public}@` only, and there is no
  /// numeric-format precedent to follow.
  private static func elapsedMillis(since start: DispatchTime) -> String {
    let nanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
    return String(format: "%.0f", Double(nanos) / 1_000_000)
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
    // Live-test bug: the search field wasn't focused when the picker opened,
    // so typing did nothing until the user clicked into it first.
    //
    // `bootRenderEngine` sets `p.contentViewController = vc`, which per
    // AppKit makes `vc.view` the panel's `initialFirstResponder` — but that
    // outlet is documented to apply only the FIRST time a window is ordered
    // onto the screen. This panel is deliberately created once and reused
    // for the whole app session (see the class doc), so every `show()`
    // after the very first one is *not* that first appearance, and the
    // reused panel keeps whatever first responder it last had (typically
    // reset to the window itself once `dismiss` orders it back out and it
    // resigns key). Setting first responder explicitly, every time, removes
    // the dependency on that one-shot semantics entirely.
    let focused = p.makeFirstResponder(renderViewController?.view)
    os_log(
      "show: makeFirstResponder(renderView) -> %{public}@",
      log: Self.logger, type: .info, focused ? "true" : "false"
    )
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

  /// Idempotent: creates the panel if it doesn't exist yet, and boots the
  /// render engine unless a live one is already attached.
  ///
  /// The second half matters now that [prewarm] boots the engine before the
  /// user ever asks for a picker: a failed boot (`engine.run` returning
  /// false, so no view controller ever gets attached) used to be permanent,
  /// because the panel existed and this method returned early forever after.
  /// The picker would then stay blank for the whole app session. Keying the
  /// re-boot on `renderViewController` rather than on a separate failure flag
  /// keeps "is there a usable engine?" a single question with a single
  /// answer.
  private func ensurePanel() {
    if panel == nil {
      let p = SnippetPickerPanel(contentSize: Self.contentSize)
      p.delegate = self
      panel = p
      os_log("ensurePanel: panel created", log: Self.logger, type: .info)
    }
    if renderViewController == nil {
      bootRenderEngine()
    }
  }

  private func bootRenderEngine() {
    guard let p = panel else { return }
    renderReady = false

    // Discard the corpse of a failed earlier attempt (engine allocated, run
    // failed, no view controller) before allocating a fresh one, so a retry
    // can't leak a second engine.
    if renderEngine != nil, renderViewController == nil {
      renderEngine?.shutDownEngine()
      renderEngine = nil
    }

    renderBootStartedAt = DispatchTime.now()

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
      let bootMillis = renderBootStartedAt.map { Self.elapsedMillis(since: $0) } ?? "?"
      renderBootStartedAt = nil
      os_log(
        "render engine ready %{public}@ ms after boot start",
        log: Self.logger, type: .info, bootMillis
      )
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
    if let monitor = escapeMonitor {
      NSEvent.removeMonitor(monitor)
      escapeMonitor = nil
    }
    renderChannel?.setMethodCallHandler(nil)
    panel?.delegate = nil
    panel?.close()
    panel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderReady = false
    renderBootStartedAt = nil
    pendingItems = nil
    channel.setMethodCallHandler(nil)
  }
}
