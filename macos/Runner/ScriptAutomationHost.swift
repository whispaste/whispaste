import Cocoa
import FlutterMacOS

/// MethodChannel host for the MAS "script" automation action type
/// (`.scratch/dictation-automations/issues/04-automation-skript-editor-mas.md`).
///
/// A sandboxed app may only *read* `applicationScriptsDirectory`, never
/// write to it — confirmed both in Apple's `NSUserUnixTask` docs and
/// empirically (a direct write fails with `NSCocoaErrorDomain` 513, and even
/// a user-mediated `NSSavePanel` silently redirects the write one level up
/// into the shared, non-functional parent folder instead of the app's own
/// subfolder). So this host never creates files there itself: the user
/// drops their script in via Finder (`revealScriptsFolder`), and this host
/// only lists what's already there and executes it via `NSUserUnixTask`,
/// the API sandboxed apps are meant to use for exactly this folder.
class ScriptAutomationHost {
  private var channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.script_automation",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "revealScriptsFolder":
      revealScriptsFolder()
      result(nil)

    case "listScripts":
      result(listScripts())

    case "runScript":
      guard let args = call.arguments as? [String: Any],
            let scriptName = args["scriptName"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'scriptName'", details: nil))
        return
      }
      runScript(named: scriptName, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Resolved at runtime from the process's actual code-signing identity
  /// (`create: true` also creates the folder on first launch, which is the
  /// one write FileManager itself is allowed to do here — it's provisioning
  /// the reserved directory, not writing app content into it).
  private func scriptsDirectory() -> URL? {
    try? FileManager.default.url(
      for: .applicationScriptsDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    )
  }

  private func revealScriptsFolder() {
    guard let dir = scriptsDirectory() else { return }
    NSWorkspace.shared.activateFileViewerSelecting([dir])
  }

  /// Hidden files (dotfiles like a stray `.DS_Store`) are filtered out —
  /// they're never something the user meant to install as a script.
  private func listScripts() -> [String] {
    guard let dir = scriptsDirectory() else { return [] }
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return names.filter { !$0.hasPrefix(".") }.sorted()
  }

  /// `NSUserUnixTask` requires [scriptName] to already carry the executable
  /// bit and a shebang — set by the user when they placed it via Finder, not
  /// something this host can fix up (it can't write to the folder either).
  /// A missing/non-executable/malformed file all surface the same way: a
  /// clean `false`, no crash.
  private func runScript(named scriptName: String, result: @escaping FlutterResult) {
    guard let dir = scriptsDirectory() else {
      result(false)
      return
    }
    let scriptURL = dir.appendingPathComponent(scriptName)
    guard FileManager.default.fileExists(atPath: scriptURL.path) else {
      result(false)
      return
    }
    do {
      let task = try NSUserUnixTask(url: scriptURL)
      task.execute(withArguments: nil) { error in
        DispatchQueue.main.async {
          if let error {
            NSLog("ScriptAutomationHost: runScript(\(scriptName)) failed: \(error)")
            result(false)
          } else {
            result(true)
          }
        }
      }
    } catch {
      NSLog("ScriptAutomationHost: NSUserUnixTask init failed: \(error)")
      result(false)
    }
  }
}
