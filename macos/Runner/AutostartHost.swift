import Cocoa
import FlutterMacOS
import ServiceManagement

/// MethodChannel host implementing the `launch_at_startup` plugin's macOS
/// contract natively via `ServiceManagement`.
///
/// The `launch_at_startup` pub package (see `pubspec.yaml`) ships Windows and
/// Linux native implementations, but its macOS support requires the app to
/// manually vendor a third-party Swift Package
/// (`sindresorhus/LaunchAtLogin`) via Xcode and hand-wire a
/// `FlutterMethodChannel` in `MainFlutterWindow.swift` — see the package's
/// README "macOS Support" section. That was never done here, so every
/// `launchAtStartup*` call threw `MissingPluginException` and the Settings
/// "Launch at login" toggle silently never took effect on macOS (Windows
/// worked because its native implementation ships inside the plugin).
///
/// Rather than vendor a third-party SPM dependency (risky to add via direct
/// `project.pbxproj` edits without Xcode's own package-resolution UI), this
/// host answers the exact same `launch_at_startup` channel/method contract
/// directly with Apple's own `ServiceManagement` framework:
/// - macOS 13+: `SMAppService.mainApp` — registers/unregisters the app itself
///   as a login item, no separate helper-bundle target required.
/// - macOS 10.15–12 (this app's `MACOSX_DEPLOYMENT_TARGET`): not supported.
///   The legacy `SMLoginItemSetEnabled` API needs a dedicated helper-bundle
///   target embedded in `Contents/Library/LoginItems/`, which is a real,
///   separate build-system undertaking — out of scope here. `isEnabled`
///   reports `false` and `setEnabled(true)` fails with a clear
///   `FlutterError` instead of the previous opaque `MissingPluginException`,
///   so `AutostartService.report(Object?)` (Dart side) surfaces an honest
///   "not supported on this macOS version" failure rather than crashing.
class AutostartHost {
  private var channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "launchAtStartupIsEnabled":
      result(isEnabled())

    case "launchAtStartupSetEnabled":
      guard let args = call.arguments as? [String: Any],
            let enabled = args["setEnabledValue"] as? Bool else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'setEnabledValue'", details: nil))
        return
      }
      setEnabled(enabled, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return false
  }

  private func setEnabled(_ enabled: Bool, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(FlutterError(
        code: "UNSUPPORTED_OS_VERSION",
        message: "Launch at login requires macOS 13 or later.",
        details: nil
      ))
      return
    }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      result(nil)
    } catch {
      result(FlutterError(
        code: "AUTOSTART_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }
}
