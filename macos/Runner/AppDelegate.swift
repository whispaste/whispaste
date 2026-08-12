import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  private var desktopPasteHost: DesktopPasteHost?
  private var floatingButtonHost: FloatingButtonHost?
  private var floatingOverlayHost: FloatingOverlayHost?
  private var snippetPickerHost: SnippetPickerHost?
  private var audioRoutingHost: AudioRoutingHost?
  private var bundleIdMigrationHost: BundleIdMigrationHost?
  private var autostartHost: AutostartHost?
  private var secureBookmarkHost: SecureBookmarkHost?
  private var lifecycleChannel: FlutterMethodChannel?

  /// How long after launch the snippet-picker's second Flutter engine is
  /// booted (see `SnippetPickerHost.prewarm`).
  ///
  /// The prewarm only has to be *finished before the user's first hotkey
  /// press*; it does not have to be early. Holding it a couple of seconds
  /// keeps the picker isolate's spawn and JIT burst clear of the main
  /// engine's own startup work (STT prewarm, database open, first window
  /// frame) — moving a stall onto the visible app start would just trade one
  /// perceived slowdown for another.
  private static let snippetPickerPrewarmDelay: TimeInterval = 2.5

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Return false so close-to-tray keeps the app alive in background.
    return false
  }

  /// Re-show the main window when the user clicks the Dock icon while hidden.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.setActivationPolicy(.regular)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private var didReplyToTerminate = false

  /// Idempotency latch for the native "restart required" alert. Prevents a
  /// re-emitted `showRestartRequiredAlert` (the app-level state machine can
  /// re-derive `needsRestart` on every probe / window focus) from stacking a
  /// second modal on top of the one the user is already looking at.
  private var restartAlertShowing = false

  /// Native Cmd+Q / Dock "Quit" call `NSApplication.terminate()` directly,
  /// bypassing the Dart-level `onWindowClose` handler entirely — without
  /// this override, the process could start tearing down while the
  /// on-device STT engine still holds native GPU/Metal resources, and
  /// ggml's Metal-residency-set teardown assert aborts the whole app.
  /// `.terminateLater` holds the quit until Dart's graceful shutdown
  /// (`prepareForTermination`, see `MacOSLifecycleChannel`) replies — with a
  /// safety-net timeout so a stuck round-trip can't hang termination
  /// forever (Dart-side internal timeouts already bound it to ~14s).
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let channel = lifecycleChannel else { return .terminateNow }
    didReplyToTerminate = false
    let replyOnce = { [weak self] () -> Void in
      guard let self, !self.didReplyToTerminate else { return }
      self.didReplyToTerminate = true
      sender.reply(toApplicationShouldTerminate: true)
    }
    channel.invokeMethod("prepareForTermination", arguments: nil) { _ in
      replyOnce()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
      replyOnce()
    }
    return .terminateLater
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }

    let messenger = controller.engine.binaryMessenger

    // Register native MethodChannel hosts.
    desktopPasteHost = DesktopPasteHost(messenger: messenger)
    floatingButtonHost = FloatingButtonHost(messenger: messenger)
    floatingOverlayHost = FloatingOverlayHost(messenger: messenger)
    snippetPickerHost = SnippetPickerHost(messenger: messenger)
    audioRoutingHost = AudioRoutingHost(messenger: messenger)
    bundleIdMigrationHost = BundleIdMigrationHost(messenger: messenger)
    autostartHost = AutostartHost(messenger: messenger)
    secureBookmarkHost = SecureBookmarkHost(messenger: messenger)

    // Lifecycle channel: activation policy toggle for close-to-tray.
    lifecycleChannel = FlutterMethodChannel(
      name: "com.whispaste.app_lifecycle",
      binaryMessenger: messenger
    )
    lifecycleChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleLifecycleCall(call, result: result)
    }

    // Boot the snippet-picker's render engine off the critical path. Doing it
    // lazily on the first hotkey press (the old behaviour) put the whole
    // second-engine boot — Dart isolate spawn, theme/L10n resolution, warm-up
    // frame — between the press and the panel appearing, which is exactly the
    // latency this app exists to remove. Dispatched asynchronously rather
    // than called inline so `applicationDidFinishLaunching` stays short and
    // the main window's first frame is never held up by it.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.snippetPickerPrewarmDelay) {
      [weak self] in
      self?.snippetPickerHost?.prewarm()
    }
  }

  private func handleLifecycleCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "setActivationPolicy":
      guard let args = call.arguments as? [String: Any],
            let policy = args["policy"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'policy'", details: nil))
        return
      }
      switch policy {
      case "regular":
        NSApp.setActivationPolicy(.regular)
      case "accessory":
        NSApp.setActivationPolicy(.accessory)
      default:
        result(FlutterError(code: "UNKNOWN_POLICY", message: "Unknown policy: \(policy)", details: nil))
        return
      }
      result(nil)

    case "requestUserAttention":
      // Critical request → dock icon bounces until user activates the app.
      // Informational request → bounces once. We always use critical for
      // paste failures so the bounce keeps going until the user notices,
      // matching the persistent nature of the underlying issue (the user
      // has a TODO that won't go away on its own).
      let level = (call.arguments as? [String: Any])?["level"] as? String ?? "critical"
      let req: NSApplication.RequestUserAttentionType =
        level == "informational" ? .informationalRequest : .criticalRequest
      let token = NSApp.requestUserAttention(req)
      // Returning the token allows Dart to cancel the bounce later via
      // `cancelUserAttentionRequest:` once the issue is resolved.
      result(token)

    case "cancelUserAttentionRequest":
      if let token = (call.arguments as? [String: Any])?["token"] as? Int {
        NSApp.cancelUserAttentionRequest(token)
      }
      result(nil)

    case "restart":
      result(nil)
      performRelaunch()

    case "showRestartRequiredAlert":
      // Native, always-on-top "you must restart" modal. Unlike the in-app
      // Flutter banner, this surfaces even when WhisPaste is a hidden tray
      // (`.accessory`) app with no visible window — the common case, since
      // WhisPaste runs in the background and the user rarely has the window
      // open. Confirming it restarts immediately and directly (single
      // action, no navigate-away step). Localized strings are passed in from
      // Dart so all copy stays in the ARB files.
      let args = call.arguments as? [String: Any]
      result(nil)
      presentAlwaysOnTopAlert(
        title: args?["title"] as? String ?? "Restart WhisPaste",
        body: args?["body"] as? String ?? "",
        confirmLabel: args?["confirmLabel"] as? String ?? "Restart now"
      ) { [weak self] _ in
        self?.performRelaunch()
      }

    case "showPermissionGrantAlert":
      // Generic always-on-top permission dialog for the startup gate. The
      // native side owns nothing but the modal: on dismissal it calls back
      // into Dart with the alert id + the user's confirm/decline choice,
      // and the registered Dart callback performs the actual action
      // (deep-link, grant flow, or nothing on decline). Keeps every
      // recovery decision in one place (Dart) instead of splitting logic
      // across the channel boundary. Always carries a decline button — a
      // permission surface the user cannot dismiss is an HIG violation.
      let permissionArgs = call.arguments as? [String: Any]
      let alertId = permissionArgs?["id"] as? String ?? ""
      result(nil)
      presentAlwaysOnTopAlert(
        title: permissionArgs?["title"] as? String ?? "",
        body: permissionArgs?["body"] as? String ?? "",
        confirmLabel: permissionArgs?["confirmLabel"] as? String ?? "OK",
        cancelLabel: permissionArgs?["cancelLabel"] as? String
      ) { [weak self] confirmed in
        self?.lifecycleChannel?.invokeMethod(
          "permissionAlertConfirmed",
          arguments: ["id": alertId, "confirmed": confirmed]
        )
      }

    case "showManualGrantAlert":
      // Loop exit for the "restart already ran but permission still missing"
      // case: instead of relaunching yet again, confirming opens System
      // Settings → Privacy & Security → Accessibility so the user can verify
      // or re-toggle WhisPaste. Opening a `x-apple.systempreferences:` URL is
      // sandbox-legal (no subprocess, no private API).
      let manualArgs = call.arguments as? [String: Any]
      result(nil)
      presentAlwaysOnTopAlert(
        title: manualArgs?["title"] as? String ?? "Check System Settings",
        body: manualArgs?["body"] as? String ?? "",
        confirmLabel: manualArgs?["confirmLabel"] as? String ?? "Open System Settings"
      ) { _ in
        if let url = URL(
          string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
          NSWorkspace.shared.open(url)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Shows an app-level, always-on-top alert and reports the user's choice
  /// via [onDismiss] (`true` = confirm button). Safe to call repeatedly: the
  /// `restartAlertShowing` latch coalesces re-triggers into the single
  /// already-visible modal, so a re-derived "restart needed" can't stack a
  /// second copy.
  ///
  /// [cancelLabel] is optional: the forced-restart and manual-grant alerts
  /// stay deliberately single-action (they repair a state the user already
  /// opted into), while the permission-grant dialogs always pass a decline
  /// button — a permission surface the user cannot dismiss violates the HIG.
  private func presentAlwaysOnTopAlert(
    title: String, body: String, confirmLabel: String,
    cancelLabel: String? = nil,
    onDismiss: @escaping (Bool) -> Void
  ) {
    // Marshal onto the main thread — method-channel handlers already run
    // there, but this keeps the invariant explicit for the AppKit calls.
    DispatchQueue.main.async {
      guard !self.restartAlertShowing else { return }
      self.restartAlertShowing = true

      // Force the app visible/frontmost first: a background `.accessory`
      // app's modal is otherwise buried behind whatever the user is looking
      // at. Switching to `.regular` gives the alert a Dock presence and an
      // activation context; `activate(ignoringOtherApps:)` pulls it to the
      // front across app boundaries.
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)

      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = title
      alert.informativeText = body
      alert.addButton(withTitle: confirmLabel)
      if let cancelLabel {
        alert.addButton(withTitle: cancelLabel)
      }

      // Realize the alert's window so its level can be raised above normal
      // windows — belt-and-suspenders for the tray-app case where the alert
      // must sit on top of every other application, not just our own.
      alert.layout()
      alert.window.level = .floating
      alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

      let response = alert.runModal()
      self.restartAlertShowing = false
      onDismiss(response == .alertFirstButtonReturn)
    }
  }

  /// Programmatic relaunch. Two independent reasons a fresh process is the
  /// only reliable fix, both because macOS only re-evaluates certain trust/
  /// permission state at process start, never mid-run:
  ///  - Developer-ID: after `tccutil reset` wipes stale ad-hoc-signature TCC
  ///    entries, the app needs a fresh process to bind to the new entry.
  ///  - Mac App Store: `CGPreflightPostEventAccess()` (gating direct-typing/
  ///    paste — see build_config.dart's kAutoPasteSupported) does not refresh
  ///    within an already-running process after the user grants the
  ///    permission via System Settings, even though the OS's actual event
  ///    delivery already respects the live grant. This matches macOS's own UX
  ///    for this exact permission toggle, which offers to quit-and-relaunch
  ///    the app for you.
  private func performRelaunch() {
    #if MAS_BUILD
    // No Process()-spawn here (2.5.2 static-scan avoidance, same reasoning as
    // tccutil in DesktopPasteHost.swift) — NSWorkspace can launch a fresh
    // instance of ourselves without any subprocess symbols, which is
    // sandbox-legal. `createsNewApplicationInstance` is honored for launching
    // a second instance of self, but the sandbox CAN refuse it (macOS 12+
    // has been observed denying sandboxed self-launches). We must NOT swallow
    // that error: if the relaunch never starts, terminating anyway would just
    // quit WhisPaste and strand the user with no running app and no fix.
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL, configuration: configuration
    ) { [weak self] runningApp, error in
      if let error = error {
        NSLog(
          "WhisPaste relaunch: openApplication failed — not terminating "
            + "(app stays usable): \(error.localizedDescription)"
        )
        self?.lifecycleChannel?.invokeMethod(
          "relaunchFailed",
          arguments: ["error": error.localizedDescription]
        )
        return
      }
      NSLog(
        "WhisPaste relaunch: new instance launched (pid "
          + "\(runningApp?.processIdentifier ?? -1)); terminating old process."
      )
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
        NSApp.terminate(nil)
      }
    }
    #else
    let bundlePath = Bundle.main.bundlePath
    // Spawn a detached helper that waits for us to exit, then re-opens the
    // .app bundle. Using `/usr/bin/open -n <bundlePath>` from a detached
    // subshell ensures the relaunched process is not parented to this one and
    // inherits no Accessibility trust from the original.
    let pid = ProcessInfo.processInfo.processIdentifier
    let script = """
      while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
      /usr/bin/open -n "\(bundlePath)"
      """
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", script]
    do {
      try task.run()
    } catch {
      // If we can't spawn the helper there's no clean fallback — bail without
      // terminating so the user can manually relaunch.
      NSLog("WhisPaste relaunch: helper spawn failed: \(error.localizedDescription)")
      lifecycleChannel?.invokeMethod(
        "relaunchFailed", arguments: ["error": error.localizedDescription]
      )
      return
    }
    // Give Dart a moment to flush its method-channel reply, then quit.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
      NSApp.terminate(nil)
    }
    #endif
  }
}
