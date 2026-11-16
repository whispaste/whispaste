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

  /// The Developer-ID release identity. Only it inherits the legacy state:
  /// local Debug/Profile builds (`de.whispaste.direct.dev`) never copy the
  /// legacy preferences or clear the legacy app's privacy grants.
  static let releaseBundleId = "de.whispaste.direct"

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
  ///
  /// Runs for [releaseBundleId] only.
  static func adoptLegacyIdentityIfNeeded() {
    guard Bundle.main.bundleIdentifier == releaseBundleId else { return }
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
    // The app stores its secrets in the file-based login keychain (the
    // data-protection keychain needs an entitlement the Runner lacks, see
    // `defaultSecureStorage`), so look there first; the data-protection
    // keychain is only a fallback for items an earlier build may have left.
    for dataProtection in [false, true] {
      var query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: account,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
      ]
      if dataProtection { query[kSecUseDataProtectionKeychain] = true }
      // Runs at start, before any explanation: an item with a foreign ACL
      // must fail silently instead of prompting (#1161).
      var item: CFTypeRef?
      let status = QuietKeychain.withoutInteraction {
        SecItemCopyMatching(query as CFDictionary, &item)
      }
      if status == errSecSuccess,
        let data = item as? Data, let value = String(data: data, encoding: .utf8)
      {
        return value
      }
    }
    return nil
  }
}

/// The old file-based login keychain (ADR 0036, #1163): quiet reads (#1161),
/// reads after consent, and deletes. Every call goes through
/// [oldKeychainQuery], so read and delete address the same item.
///
/// Items in the file-based login keychain carry an ACL bound to the code
/// signature that created them. A build signed differently (a local
/// Developer-ID build over the App Store install, or the other way round)
/// gets one "allow access" prompt per item and read. Before the app has
/// explained why it needs the key store, it must not cause such a prompt.
///
/// `kSecUseAuthenticationUIFail` alone does not suppress the prompt for the
/// file-based keychain (measured: prompt, then -128 after the dialog). The
/// process-wide `SecKeychainSetUserInteractionAllowed(false)` does: an item
/// with a foreign ACL then fails at once with errSecAuthFailed, while an
/// item this signature may read returns its data as usual.
///
/// Only the file-based keychains (#1674). A SecItem query without
/// `kSecMatchSearchList` is not confined to them in a sandboxed build with a
/// keychain access group: measured on macOS 27.2 (Developer ID, sandbox,
/// `Q7V3X27S2U.de.whispaste.app`), the login keychain held no WhisPaste item
/// at all, yet such a query read the data-protection item, and the
/// `flutter_secure_storage` delete with `usesDataProtectionKeychain: false`
/// removed it. The old-keychain move then "moved" the new item onto itself
/// and deleted it, at every start. The explicit search list of file-based
/// keychains (the user's keychain search list) rules that out: such a
/// query is served by the file-based implementation only.
enum QuietKeychain {
  /// The query for one old-keychain item, or nil when the keychain search
  /// list is unavailable (then nothing is read or deleted).
  static func oldKeychainQuery(service: String, account: String) -> [CFString: Any]? {
    var searchList: CFArray?
    guard SecKeychainCopySearchList(&searchList) == errSecSuccess,
      let list = searchList, CFArrayGetCount(list) > 0
    else { return nil }
    return [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecMatchSearchList: list,
    ]
  }

  /// Result as the Dart side reads it: `status` is `ok`, `missing`,
  /// `needsConsent` or `error`; `code` is the OSStatus. Never logs the value.
  static func read(service: String, account: String) -> [String: Any] {
    guard var query = oldKeychainQuery(service: service, account: account) else {
      return ["status": "error", "code": Int(errSecNoSuchKeychain)]
    }
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
    var item: CFTypeRef?
    let status = withoutInteraction {
      SecItemCopyMatching(query as CFDictionary, &item)
    }
    return readResult(status: status, item: item)
  }

  /// Like [read], but the system may show its "allow access" dialog. Only
  /// after the user agreed to the move (#1163).
  static func readAllowingPrompt(service: String, account: String) -> [String: Any] {
    guard var query = oldKeychainQuery(service: service, account: account) else {
      return ["status": "error", "code": Int(errSecNoSuchKeychain)]
    }
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return readResult(status: status, item: item)
  }

  /// Deletes every old-keychain item for service/account, by reference, so
  /// only file-based items are touched. `status` is `ok` (deleted or none
  /// there) or `error` with the OSStatus.
  static func delete(service: String, account: String) -> [String: Any] {
    guard var query = oldKeychainQuery(service: service, account: account) else {
      return ["status": "error", "code": Int(errSecNoSuchKeychain)]
    }
    query[kSecReturnRef] = true
    query[kSecMatchLimit] = kSecMatchLimitAll
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound { return ["status": "ok", "code": Int(status)] }
    guard status == errSecSuccess, let items = found as? [AnyObject] else {
      return ["status": "error", "code": Int(status)]
    }
    for item in items {
      let deleted = SecItemDelete(
        [kSecClass: kSecClassGenericPassword, kSecValueRef: item] as CFDictionary)
      if deleted != errSecSuccess && deleted != errSecItemNotFound {
        return ["status": "error", "code": Int(deleted)]
      }
    }
    return ["status": "ok", "code": Int(errSecSuccess)]
  }

  private static func readResult(status: OSStatus, item: CFTypeRef?) -> [String: Any] {
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
        return ["status": "error", "code": Int(status)]
      }
      return ["status": "ok", "code": Int(status), "value": value]
    case errSecItemNotFound:
      return ["status": "missing", "code": Int(status)]
    case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled,
      errSecInteractionRequired:
      return ["status": "needsConsent", "code": Int(status)]
    default:
      return ["status": "error", "code": Int(status)]
    }
  }

  /// Runs [body] with keychain user interaction switched off and restores the
  /// previous setting afterwards. The switch is process-wide, so callers stay
  /// on the main thread and keep [body] short.
  static func withoutInteraction(_ body: () -> OSStatus) -> OSStatus {
    var previous: DarwinBoolean = true
    let known = SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess
    SecKeychainSetUserInteractionAllowed(false)
    defer { SecKeychainSetUserInteractionAllowed(known ? previous.boolValue : true) }
    return body()
  }
}
