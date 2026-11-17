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
/// `SMAppService.mainApp` (macOS 13+, the app's `MACOSX_DEPLOYMENT_TARGET`)
/// registers/unregisters the app itself as a login item, no separate
/// helper-bundle target required.
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

    // WhisPaste-specific additions on the plugin's channel. `register()` on a
    // login item that the user has not approved yet succeeds silently and the
    // status stays `.requiresApproval`, so Dart needs its own answer for it.
    case "launchAtStartupRequiresApproval":
      result(requiresApproval())

    case "launchAtStartupOpenLoginItems":
      SMAppService.openSystemSettingsLoginItems()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
  }

  private func requiresApproval() -> Bool {
    SMAppService.mainApp.status == .requiresApproval
  }

  private func setEnabled(_ enabled: Bool, result: @escaping FlutterResult) {
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
