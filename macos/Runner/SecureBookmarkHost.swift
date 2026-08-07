import Cocoa
import FlutterMacOS

/// MethodChannel host for macOS security-scoped bookmarks (PRD
/// `settings-portability-vollumfang`, Ticket 04).
///
/// An `NSOpenPanel`/`NSSavePanel` selection made via `package:file_selector`
/// grants sandbox access to the chosen file only for the lifetime of the
/// current process. `SettingsPortabilityController` (Dart side) remembers
/// the user's export/import path across app restarts (Ticket 03), but under
/// the Mac App Store sandbox a bare path string is useless after relaunch —
/// it fails with "Operation not permitted". A persisted, app-scoped
/// security-scoped bookmark survives the restart instead.
///
/// No pub package used deliberately — see `AutostartHost.swift`'s docstring
/// for the established precedent of calling Apple's own framework directly
/// rather than vendoring a third-party dependency for a narrow API.
class SecureBookmarkHost {
  private var channel: FlutterMethodChannel

  /// URLs with an active `startAccessingSecurityScopedResource()` session,
  /// keyed by the bookmark's base64 string. `stopAccess` must call
  /// `stopAccessingSecurityScopedResource()` on this exact same `URL`
  /// instance — a freshly re-resolved `URL` for the same bookmark data is a
  /// distinct object and would not balance the access count.
  private var activeAccess: [String: URL] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.secure_bookmark",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
      return
    }

    switch call.method {
    case "create":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path'", details: nil))
        return
      }
      result(create(path: path))

    case "resolve":
      guard let bookmark = args["bookmark"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'bookmark'", details: nil))
        return
      }
      result(resolve(bookmark: bookmark))

    case "startAccess":
      guard let bookmark = args["bookmark"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'bookmark'", details: nil))
        return
      }
      result(startAccess(bookmark: bookmark))

    case "stopAccess":
      guard let bookmark = args["bookmark"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'bookmark'", details: nil))
        return
      }
      stopAccess(bookmark: bookmark)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Creates a security-scoped bookmark for `path`. The caller must
  /// currently have sandbox access to `path` — either because it was just
  /// selected via an `NSOpenPanel`/`NSSavePanel` in this process, or
  /// because an access session from [startAccess] is still open for it.
  private func create(path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    do {
      let data = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      return data.base64EncodedString()
    } catch {
      return nil
    }
  }

  /// Resolves `bookmark` to its current path and staleness, without
  /// starting an access session.
  private func resolve(bookmark: String) -> [String: Any]? {
    guard let data = Data(base64Encoded: bookmark) else { return nil }
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      return ["path": url.path, "isStale": isStale]
    } catch {
      return nil
    }
  }

  /// Resolves `bookmark` and starts a security-scoped access session,
  /// caching the resolved `URL` so [stopAccess] can balance it later.
  private func startAccess(bookmark: String) -> Bool {
    guard let data = Data(base64Encoded: bookmark) else { return false }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else { return false }
    guard url.startAccessingSecurityScopedResource() else { return false }
    activeAccess[bookmark] = url
    return true
  }

  private func stopAccess(bookmark: String) {
    guard let url = activeAccess.removeValue(forKey: bookmark) else { return }
    url.stopAccessingSecurityScopedResource()
  }
}
