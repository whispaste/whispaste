import Cocoa
import Darwin
import FlutterMacOS
import Security
import Sentry

@main
class AppDelegate: FlutterAppDelegate {

  private var desktopPasteHost: DesktopPasteHost?
  private var floatingButtonHost: FloatingButtonHost?
  private var floatingOverlayHost: FloatingOverlayHost?
  private var sidePanelHost: SidePanelHost?
  private var clipboardMonitorHost: ClipboardMonitorHost?
  private var snippetPickerHost: SnippetPickerHost?
  private var audioRoutingHost: AudioRoutingHost?
  private var bundleIdMigrationHost: BundleIdMigrationHost?
  private var autostartHost: AutostartHost?
  private var modifierKeyHost: ModifierKeyHost?
private var audioFileDecodeHost: AudioFileDecodeHost?
  private var secureBookmarkHost: SecureBookmarkHost?
  private var supportStoreHost: SupportStoreHost?
  private var settingsWindowPlacementHost: SettingsWindowPlacementHost?
  private var permissionHelperHost: PermissionHelperHost?
  private var appIdentityHost: AppIdentityHost?
  private var lifecycleChannel: FlutterMethodChannel?
  private var powerChannel: FlutterMethodChannel?

  /// Whether macOS launched this process as a login item. Captured once at
  /// launch: the launch Apple event is only readable while it is being
  /// handled, and an `SMAppService` login item cannot pass `--autostart`
  /// the way the Windows/Linux autostart entries do.
  private var launchedAsLoginItem = false

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

  /// One-shot observer for the stale-entry removal guide: fires the follow-up
  /// restart alert the moment the user comes back from System Settings.
  private var staleRemovalReturnObserver: NSObjectProtocol?

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
    // Hard limit behind the Dart-side deadline (kQuitHardDeadline, 3 s). If
    // Dart still has not replied, end without C++ destructors (_exit): a
    // normal termination would run them while Metal may still be busy.
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
      if self.didReplyToTerminate { return }
      _exit(0)
    }
    return .terminateLater
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Before anything else: the run loop has not delivered a single platform
    // message yet, so Dart's first SharedPreferences read already sees the
    // adopted legacy preferences.
    #if !MAS_BUILD
    BundleIdMigrationHost.adoptLegacyIdentityIfNeeded()
    #endif
    launchedAsLoginItem = Self.isLoginItemLaunch(
      NSAppleEventManager.shared().currentAppleEvent
    )

    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }

    let messenger = controller.engine.binaryMessenger

    // Register native MethodChannel hosts.
    desktopPasteHost = DesktopPasteHost(messenger: messenger)
    floatingButtonHost = FloatingButtonHost(messenger: messenger)
    floatingOverlayHost = FloatingOverlayHost(messenger: messenger)
    sidePanelHost = SidePanelHost(messenger: messenger)
    clipboardMonitorHost = ClipboardMonitorHost(messenger: messenger)
    snippetPickerHost = SnippetPickerHost(messenger: messenger)
    audioRoutingHost = AudioRoutingHost(messenger: messenger)
    bundleIdMigrationHost = BundleIdMigrationHost(messenger: messenger)
    autostartHost = AutostartHost(messenger: messenger)
    modifierKeyHost = ModifierKeyHost(messenger: messenger)
    audioFileDecodeHost = AudioFileDecodeHost(messenger: messenger)
    secureBookmarkHost = SecureBookmarkHost(messenger: messenger)
    supportStoreHost = SupportStoreHost(messenger: messenger)
    settingsWindowPlacementHost = SettingsWindowPlacementHost(messenger: messenger)
    permissionHelperHost = PermissionHelperHost(messenger: messenger)
    appIdentityHost = AppIdentityHost(messenger: messenger)

    // Lifecycle channel: activation policy toggle for close-to-tray.
    lifecycleChannel = FlutterMethodChannel(
      name: "com.whispaste.app_lifecycle",
      binaryMessenger: messenger
    )
    lifecycleChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleLifecycleCall(call, result: result)
    }

    // Power channel (WP-39, 9.5): system sleep and wake, so Dart can finish a
    // running recording before the machine suspends. Outbound only.
    powerChannel = FlutterMethodChannel(
      name: "com.whispaste.power",
      binaryMessenger: messenger
    )
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceCenter.addObserver(
      self,
      selector: #selector(systemWillSleep(_:)),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspaceCenter.addObserver(
      self,
      selector: #selector(systemDidWake(_:)),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )

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

  /// `kAEOpenApplication` carries `keyAELaunchedAsLogInItem` as its
  /// `keyAEPropData` when the launch came from the user's login items.
  private static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    guard let event,
          event.eventClass == AEEventClass(kCoreEventClass),
          event.eventID == AEEventID(kAEOpenApplication) else {
      return false
    }
    return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
      == AEKeyword(keyAELaunchedAsLogInItem)
  }

  @objc private func systemWillSleep(_ notification: Notification) {
    powerChannel?.invokeMethod("willSleep", arguments: nil)
  }

  @objc private func systemDidWake(_ notification: Notification) {
    powerChannel?.invokeMethod("didWake", arguments: nil)
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

    case "hideOtherApplications":
      NSApp.hideOtherApplications(nil)
      result(nil)

    case "unhideAllApplications":
      NSApp.unhideAllApplications(nil)
      result(nil)

    case "wasLaunchedAsLoginItem":
      result(launchedAsLoginItem)

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

    case "signingRequirement":
      // The designated requirement TCC binds every grant to. Dart persists it
      // once the permission works; a different value on a later start proves
      // the existing entry belongs to another signature (stale, cannot be
      // switched on). Security-framework reads of our own code are
      // sandbox-legal.
      result(currentDesignatedRequirement())

    case "showStaleEntryRemovalGuide":
      // Mac App Store build only: a sandboxed app cannot delete its own TCC
      // entry (no tccutil, Guideline 2.5.2), and toggling a stale row never
      // rebinds it — only removing it with "−" and relaunching does. Step 1
      // explains that and opens the Accessibility pane; step 2 appears when
      // the user returns to WhisPaste and offers the relaunch. The relaunch
      // itself stays in Dart (it persists the recovery marker first), so only
      // the final choice is reported back via `permissionAlertConfirmed`.
      let guideArgs = call.arguments as? [String: Any]
      let guideId = guideArgs?["id"] as? String ?? ""
      result(nil)
      presentAlwaysOnTopAlert(
        title: guideArgs?["title"] as? String ?? "",
        body: guideArgs?["body"] as? String ?? "",
        confirmLabel: guideArgs?["confirmLabel"] as? String ?? "OK",
        cancelLabel: guideArgs?["cancelLabel"] as? String
      ) { [weak self] confirmed in
        guard let self else { return }
        guard confirmed else {
          self.reportPermissionAlert(id: guideId, confirmed: false)
          return
        }
        self.awaitReturnFromSettings {
          self.presentAlwaysOnTopAlert(
            title: guideArgs?["restartTitle"] as? String ?? "",
            body: guideArgs?["restartBody"] as? String ?? "",
            confirmLabel: guideArgs?["restartConfirmLabel"] as? String ?? "OK",
            cancelLabel: guideArgs?["restartCancelLabel"] as? String
          ) { restart in
            self.reportPermissionAlert(id: guideId, confirmed: restart)
          }
        }
        self.openAccessibilityPane()
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reportPermissionAlert(id: String, confirmed: Bool) {
    lifecycleChannel?.invokeMethod(
      "permissionAlertConfirmed",
      arguments: ["id": id, "confirmed": confirmed]
    )
  }

  private func openAccessibilityPane() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ) {
      NSWorkspace.shared.open(url)
    }
  }

  /// Runs [action] once, the next time WhisPaste becomes the active app —
  /// i.e. after the user switched to System Settings and came back. Armed
  /// before the pane opens, so the activation switch is never missed.
  private func awaitReturnFromSettings(_ action: @escaping () -> Void) {
    if let previous = staleRemovalReturnObserver {
      NotificationCenter.default.removeObserver(previous)
    }
    staleRemovalReturnObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      if let observer = self.staleRemovalReturnObserver {
        NotificationCenter.default.removeObserver(observer)
        self.staleRemovalReturnObserver = nil
      }
      action()
    }
  }

  /// Designated requirement of the running code as text, or `nil` when it
  /// cannot be read (unsigned build).
  private func currentDesignatedRequirement() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
      let requirement
    else { return nil }
    var text: CFString?
    guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
      let text
    else { return nil }
    return text as String
  }

  /// Shows an app-level, always-on-top alert and reports the user's choice
  /// via [onDismiss] (`true` = confirm button). Safe to call repeatedly: the
  /// `restartAlertShowing` latch coalesces re-triggers into the single
  /// already-visible modal, so a re-derived "restart needed" can't stack a
  /// second copy.
  ///
  /// [cancelLabel] is optional: the forced-restart alert
  /// stays deliberately single-action (it repairs a state the user already
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

      // runModal blocks the main thread until the user answers, which
      // Sentry's watchdog reports as an "App Hanging" event every time the
      // alert stays open for 2 s -- noise on the shared error quota.
      SentrySDK.pauseAppHangTracking()
      let response = alert.runModal()
      SentrySDK.resumeAppHangTracking()
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

/// Moves WhisPaste's main window beside the System Settings window after the
/// Accessibility deep-link (Onboarding v6, S2), channel
/// `whispaste/settings_window`, method `placeBesideSystemSettings`.
///
/// The Settings window is found by the owner PID of the running app with
/// bundle id `com.apple.systempreferences`, so the lookup does not depend on
/// the system language. Only window bounds are read (CGWindowList without
/// window names), which needs no Screen Recording permission. The method
/// polls for up to three seconds, because the deep-link opens Settings with a
/// delay, and answers `false` when no window shows up or none can be moved.
final class SettingsWindowPlacementHost {
  private let channel: FlutterMethodChannel
  private let gap: CGFloat = 12

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "whispaste/settings_window",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "placeBesideSystemSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.placeWhenReady(deadline: Date().addingTimeInterval(3), result: result)
    }
  }

  private func placeWhenReady(deadline: Date, result: @escaping FlutterResult) {
    if let settingsRect = systemSettingsRect(), let window = whisPasteWindow() {
      result(move(window, besideSettingsRect: settingsRect))
      return
    }
    if Date() >= deadline {
      result(false)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.placeWhenReady(deadline: deadline, result: result)
    }
  }

  /// Bounds of the largest on-screen System Settings window, in CoreGraphics
  /// coordinates (origin at the top left of the primary display).
  private func systemSettingsRect() -> CGRect? {
    guard let app = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.systempreferences"
    ).first else {
      return nil
    }
    let pid = app.processIdentifier
    guard let windows = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]] else {
      return nil
    }
    var best: CGRect?
    for info in windows {
      guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
            owner.int32Value == pid,
            let layer = info[kCGWindowLayer as String] as? NSNumber,
            layer.intValue == 0,
            let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: boundsDict),
            rect.width >= 200, rect.height >= 200 else {
        continue
      }
      if best == nil || rect.width * rect.height > best!.width * best!.height {
        best = rect
      }
    }
    return best
  }

  private func whisPasteWindow() -> NSWindow? {
    NSApp.windows.first { $0 is MainFlutterWindow && $0.isVisible }
  }

  /// Puts the window to the right of the Settings window, or to its left when
  /// the right side has no room, top-aligned with it and kept on screen.
  private func move(_ window: NSWindow, besideSettingsRect cg: CGRect) -> Bool {
    guard let primary = NSScreen.screens.first else { return false }
    // CoreGraphics uses a top-left origin, AppKit a bottom-left one; both are
    // anchored to the primary display.
    let settings = NSRect(
      x: cg.minX,
      y: primary.frame.height - cg.maxY,
      width: cg.width,
      height: cg.height
    )
    let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? primary
    let visible = screen.visibleFrame
    let size = window.frame.size

    var x = settings.maxX + gap
    if x + size.width > visible.maxX {
      x = settings.minX - gap - size.width
    }
    x = min(max(x, visible.minX), visible.maxX - size.width)
    var y = settings.maxY - size.height
    y = min(max(y, visible.minY), visible.maxY - size.height)
    window.setFrameOrigin(NSPoint(x: x, y: y))
    return true
  }
}
