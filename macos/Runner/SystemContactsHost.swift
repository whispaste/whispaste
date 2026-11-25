import Contacts
import FlutterMacOS
import Foundation

/// MethodChannel host `com.whispaste.system_contacts` (#2037, part of #161):
/// the macOS contacts as a source of names for the dictionary. The Dart side
/// is `lib/services/dictionary/macos_contact_source.dart`; the reply has the
/// same shape as the Windows host (`windows/runner/system_contacts_host.cpp`).
///
/// * `status` → `notDetermined`, `authorized`, `denied`, `restricted`.
/// * `read {limit}` → `{status: ok, contacts: [[given, family, full, org]]}`
///   or `{status: denied | restricted | tooMany | unavailable}`. Asks macOS
///   for access when it was never asked; Dart calls it only after the user's
///   step in the app, never on the hotkey path.
///
/// Only the name keys and the company are fetched: no addresses, phone
/// numbers, e-mail addresses, notes or images ever leave the store. The
/// enumeration runs on its own queue, the reply comes back on the main
/// thread.
final class SystemContactsHost {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(
    label: "com.whispaste.system_contacts", qos: .userInitiated)

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.system_contacts",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "status":
        result(Self.statusName(CNContactStore.authorizationStatus(for: .contacts)))
      case "read":
        guard let self else {
          result(["status": "unavailable"])
          return
        }
        let args = call.arguments as? [String: Any]
        let limit = max(0, (args?["limit"] as? NSNumber)?.intValue ?? 5000)
        self.read(limit: limit) { reply in
          DispatchQueue.main.async { result(reply) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func statusName(_ status: CNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    default: return "authorized"
    }
  }

  private func read(limit: Int, reply: @escaping ([String: Any]) -> Void) {
    let store = CNContactStore()
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .denied:
      reply(["status": "denied"])
    case .restricted:
      reply(["status": "restricted"])
    case .notDetermined:
      store.requestAccess(for: .contacts) { [queue] granted, _ in
        guard granted else {
          // A refusal and a policy block both end here; the status tells
          // them apart.
          let now = CNContactStore.authorizationStatus(for: .contacts)
          reply(["status": now == .restricted ? "restricted" : "denied"])
          return
        }
        queue.async { reply(Self.enumerate(store, limit: limit)) }
      }
    default:
      queue.async { reply(Self.enumerate(store, limit: limit)) }
    }
  }

  private static func enumerate(_ store: CNContactStore, limit: Int) -> [String: Any] {
    let keys: [CNKeyDescriptor] = [
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactMiddleNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.unifyResults = true
    var contacts: [[String]] = []
    var tooMany = false
    do {
      try store.enumerateContacts(with: request) { contact, stop in
        if contacts.count >= limit {
          tooMany = true
          stop.pointee = true
          return
        }
        let given = [contact.givenName, contact.middleName]
          .filter { !$0.isEmpty }
          .joined(separator: " ")
        contacts.append([
          given, contact.familyName, fullName(contact), contact.organizationName,
        ])
      }
    } catch let error as NSError {
      // CNErrorCodeAuthorizationDenied: access withdrawn meanwhile.
      if error.domain == CNErrorDomain && error.code == CNError.authorizationDenied.rawValue {
        return ["status": "denied"]
      }
      return ["status": "unavailable"]
    }
    if tooMany { return ["status": "tooMany"] }
    return ["status": "ok", "contacts": contacts]
  }

  /// The name as the user's name order shows it, without title and suffix
  /// ("Dr.", "Jr."), which do not belong into a dictionary term.
  private static func fullName(_ contact: CNContact) -> String {
    guard let copy = contact.mutableCopy() as? CNMutableContact else { return "" }
    copy.namePrefix = ""
    copy.nameSuffix = ""
    return CNContactFormatter.string(from: copy, style: .fullName) ?? ""
  }
}
