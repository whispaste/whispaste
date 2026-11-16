import ApplicationServices
import Cocoa
import FlutterMacOS

/// MethodChannel host `com.whispaste.field_type` (issue #949, parent #167):
/// answers what kind of field has the keyboard focus before a paste, so Dart
/// can skip the automatic paste in a password or PIN field. Same contract as
/// the Windows runner (`field_type_host.cpp`), documented in
/// `desktop_paste_controller_interface.dart`.
///
/// `focusedFieldType` answers one of `password`, `normal`, `unknown`. Only the
/// role and subrole of the focused element are read, never its value, title or
/// any other content.
///
/// - Subrole `AXSecureTextField` is `password`.
/// - A text field, text area, combo box or search field without that subrole is
///   `normal`.
/// - Everything else is `unknown`: no Accessibility permission (the check never
///   prompts, so there is no new permission request), no focused element, our
///   own window, a role that is no text field, a slow or failing target app,
///   and the Mac App Store build (its sandbox blocks the Accessibility API for
///   other apps). `unknown` keeps the previous paste behaviour.
///
/// The read runs on a background queue with a short AX messaging timeout, so a
/// hanging target app never blocks the platform thread.
final class FieldTypeHost {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "com.whispaste.field_type", qos: .userInitiated)
  /// Chromium/Electron apps whose accessibility tree was already requested.
  private var enabledPids = Set<pid_t>()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.whispaste.field_type", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "focusedFieldType" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.queue.async {
        let code = self?.read() ?? "unknown"
        DispatchQueue.main.async { result(code) }
      }
    }
  }

  private func read() -> String {
#if MAS_BUILD
    return "unknown"
#else
    guard AXIsProcessTrusted() else { return "unknown" }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.5)
    guard let focused = Self.element(system, kAXFocusedUIElementAttribute) else { return "unknown" }
    AXUIElementSetMessagingTimeout(focused, 0.5)
    var pid: pid_t = 0
    AXUIElementGetPid(focused, &pid)
    if pid == ProcessInfo.processInfo.processIdentifier { return "unknown" }
    requestTree(pid: pid)
    let subrole = Self.string(focused, kAXSubroleAttribute)
    if subrole == kAXSecureTextFieldSubrole { return "password" }
    let role = Self.string(focused, kAXRoleAttribute)
    let textRoles: Set<String> = [
      kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
    ]
    if let role = role, textRoles.contains(role) { return "normal" }
    return "unknown"
#endif
  }

  private func requestTree(pid: pid_t) {
    guard !enabledPids.contains(pid) else { return }
    enabledPids.insert(pid)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.5)
    AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
    return raw as? String
  }

  private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
      let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    // swiftlint:disable:next force_cast
    return (value as! AXUIElement)
  }
}
