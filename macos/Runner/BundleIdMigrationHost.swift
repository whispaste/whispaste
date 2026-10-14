import Cocoa
import FlutterMacOS
import Security

/// Native bridge for the one-time bundle-ID data migration
/// (see `lib/services/bundle_id_migration_service.dart`).
///
/// Reads data that only exists under the *old* app identity
/// (`com.whispaste.whispaste`) and is otherwise unreachable from the pure
/// Dart layer: another bundle ID's `NSUserDefaults` domain, and Keychain
/// items that may be scoped to the old code-signing identity.
///
/// Best-effort by design: a failed Keychain read (e.g. the OS denying
/// cross-identity access) is indistinguishable here from "no old data" —
/// both return nil, which the Dart-side pure migration function already
/// treats as a no-op. This bridge can only help recover data, never make
/// the no-migration-possible case worse.
class BundleIdMigrationHost: NSObject {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.bundle_id_migration",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readOldPreference":
      guard let args = call.arguments as? [String: Any],
            let oldBundleId = args["oldBundleId"] as? String,
            let key = args["key"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing oldBundleId/key", details: nil))
        return
      }
      result(readOldPreference(oldBundleId: oldBundleId, key: key))

    case "readOldKeychainValue":
      guard let args = call.arguments as? [String: Any],
            let service = args["service"] as? String,
            let account = args["account"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing service/account", details: nil))
        return
      }
      result(readOldKeychainValue(service: service, account: account))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Reads a single key from another bundle identity's `NSUserDefaults`
  /// domain. Non-sandboxed macOS apps can read any preference domain by
  /// name — no cross-app entitlement is required for this API.
  ///
  /// `shared_preferences_platform_interface`'s legacy `MethodChannel` store
  /// (what `SharedPreferences.getInstance()` uses) prefixes every key with
  /// `"flutter."` (`_defaultPrefix`) before it ever reaches the native
  /// UserDefaults call — verified against
  /// `shared_preferences_platform_interface`'s source. Without replicating
  /// that prefix here, this would silently find nothing and every
  /// preference migration would be a no-op.
  private func readOldPreference(oldBundleId: String, key: String) -> String? {
    guard let suite = UserDefaults(suiteName: oldBundleId) else { return nil }
    return suite.string(forKey: "flutter.\(key)")
  }

#if !MAS_BUILD
  /// The identity the Developer-ID build shipped under up to 1.4.0 — and the
  /// one the Mac App Store build keeps for good.
  static let legacyBundleId = "de.whispaste.app"

  private static let legacyIdentityAdoptedKey = "whispaste.legacyIdentityAdopted"

  /// Permission state belongs to the identity that earned it — copied over
  /// it would describe a grant this app never had.
  private static let identityBoundPreferenceKeys: Set<String> = [
    "flutter.auto_paste_granted_signing_requirement",
    "flutter.auto_paste_restart_attempted",
  ]

  /// One-time move from [legacyBundleId] to this build's own identity.
  ///
  /// macOS keys privacy grants by bundle ID plus code signature. With both
  /// distributions sharing `de.whispaste.app`, every switch between them left
  /// a stale entry behind that the sandboxed build cannot remove. Separate
  /// identities never collide; this carries the user's state across the cut:
  ///
  /// - preferences: the legacy `NSUserDefaults` domain is copied over without
  ///   overwriting anything already set (must run before Dart's first
  ///   SharedPreferences read — called first thing in
  ///   `applicationDidFinishLaunching`, before the run loop delivers any
  ///   platform message);
  /// - Keychain: nothing to do — the login-keychain items are keyed by
  ///   service/account, not bundle ID, and stay readable for the same team
  ///   without a prompt (verified with two Developer-ID-signed probe apps);
  /// - privacy grants: the legacy entries are cleared best-effort so a later
  ///   install of the App Store build starts with macOS's own prompt instead
  ///   of a stale row — unless the legacy ID now belongs to an installed
  ///   sandboxed (App Store) build, whose grants are valid and stay. `tccutil`
  ///   refuses bundle IDs Launch Services no longer knows; then there is
  ///   nothing more this build can do.
  static func adoptLegacyIdentityIfNeeded() {
    guard let current = Bundle.main.bundleIdentifier, current != legacyBundleId else {
      return
    }
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: legacyIdentityAdoptedKey) else { return }
    defaults.set(true, forKey: legacyIdentityAdoptedKey)

    guard let legacy = defaults.persistentDomain(forName: legacyBundleId), !legacy.isEmpty else {
      return
    }
    for (key, value) in legacy
    where !identityBoundPreferenceKeys.contains(key) && defaults.object(forKey: key) == nil {
      defaults.set(value, forKey: key)
    }
    DispatchQueue.global(qos: .utility).async {
      guard !legacyIdentityIsSandboxedApp() else { return }
      for service in ["Accessibility", "PostEvent", "ListenEvent", "AppleEvents"] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", service, legacyBundleId]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
      }
    }
  }

  private static func legacyIdentityIsSandboxedApp() -> Bool {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: legacyBundleId)
    else { return false }
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
      let code = staticCode
    else { return false }
    var info: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
      let signing = info as? [String: Any],
      let entitlements = signing[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    else { return false }
    return entitlements["com.apple.security.app-sandbox"] as? Bool == true
  }
#endif

  /// Best-effort read of a Generic Password Keychain item, matching the
  /// exact `kSecAttrService`/`kSecAttrAccount` scheme
  /// `flutter_secure_storage_darwin` uses on macOS (service defaults to
  /// `"flutter_secure_storage_service"`, account is the storage key).
  private func readOldKeychainValue(service: String, account: String) -> String? {
    var query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    if #available(macOS 10.15, *) {
      query[kSecUseDataProtectionKeychain] = true
    }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
