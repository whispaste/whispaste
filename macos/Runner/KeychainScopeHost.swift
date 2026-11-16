import FlutterMacOS
import Foundation
import Security

/// MethodChannel host `com.whispaste.keychain_scope`: tells Dart whether this
/// build has a keychain access group of its own (ADR 0036).
///
/// The data-protection keychain puts new items into the app's default access
/// group: the first `keychain-access-groups` entry, else the
/// `com.apple.application-identifier`. Developer ID builds carry
/// `keychain-access-groups = [Q7V3X27S2U.de.whispaste.app]`, Store builds get
/// the application identifier `Q7V3X27S2U.de.whispaste.app` from their
/// provisioning profile; both resolve to the same team group. There secrets
/// need no password prompt and survive updates, reinstalls and switching
/// between a local build and the installed one. Debug, ad-hoc and local
/// preview builds have neither entitlement; the data-protection keychain
/// fails there with -34018, so Dart stays on the legacy login keychain.
final class KeychainScopeHost {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.keychain_scope",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "hasAccessGroup":
        result(KeychainScopeHost.hasAccessGroup())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func hasAccessGroup() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let groups = SecTaskCopyValueForEntitlement(
      task, "keychain-access-groups" as CFString, nil)
    if (groups as? [String])?.isEmpty == false { return true }
    let appId = SecTaskCopyValueForEntitlement(
      task, "com.apple.application-identifier" as CFString, nil)
    return (appId as? String)?.isEmpty == false
  }
}
