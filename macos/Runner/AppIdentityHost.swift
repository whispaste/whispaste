import Cocoa
import FlutterMacOS

/// MethodChannel host `com.whispaste.app_identity`: readable name and icon of
/// a target app, so the recording rows show "Warp" with its icon instead of
/// the raw bundle id.
///
/// The history stores the bundle id; Launch Services finds the app for it
/// (installed anywhere, running or not). The name is CFBundleDisplayName,
/// else CFBundleName, else the localized file name; the icon is drawn at the
/// requested pixel size and sent as PNG. Dart caches every answer, so each
/// app is looked up once.
final class AppIdentityHost {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.app_identity",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "resolveApp":
      let args = call.arguments as? [String: Any]
      let id = (args?["id"] as? String) ?? ""
      var size = (args?["size"] as? Int) ?? 64
      if size < 16 || size > 256 { size = 64 }
      result(resolve(id: id, size: size))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func resolve(id: String, size: Int) -> [String: Any] {
    guard !id.isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    else { return [:] }
    var reply: [String: Any] = [:]
    if let name = displayName(of: url) { reply["name"] = name }
    if let png = iconPng(of: url, size: size) {
      reply["icon"] = FlutterStandardTypedData(bytes: png)
    }
    return reply
  }

  private func displayName(of url: URL) -> String? {
    let bundle = Bundle(url: url)
    let keys = ["CFBundleDisplayName", "CFBundleName"]
    for key in keys {
      let value = (bundle?.localizedInfoDictionary?[key] ?? bundle?.infoDictionary?[key])
        as? String
      if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
        return value
      }
    }
    let name = FileManager.default.displayName(atPath: url.path)
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
  }

  private func iconPng(of url: URL, size: Int) -> Data? {
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    icon.draw(
      in: NSRect(x: 0, y: 0, width: size, height: size),
      from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])
  }
}
