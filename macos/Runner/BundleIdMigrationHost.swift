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
