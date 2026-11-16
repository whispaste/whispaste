import ApplicationServices
import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

/// MethodChannel host `com.whispaste.inserted_span` (issue #384): after a
/// paste, reads back only a bounded section of the focused field around the
/// caret, so Dart can learn from corrections the user makes in the target
/// app. Same contract as the Windows runner (`inserted_span_host.cpp`) and
/// Linux (`target_field_host.cc`), documented in `target_field_learning.dart`.
///
/// `readInsertedSpan({expectedText, slackChars, afterChars})` answers
/// `{readable, text, matchesExpected, reason, pattern}`; `text` reaches from
/// the length of `expectedText` plus `slackChars` before the caret to
/// `afterChars` after it (UTF-16 units, clamped to the field), so the user may
/// click anywhere inside the pasted text.
///
/// - Password fields (`AXSecureTextField`, or secure input on) are never read.
/// - Fields with a caret (`AXSelectedTextRange` + `AXStringForRange`: Terminal,
///   TextEdit, Safari, Chrome) give the section around the caret
///   (`pattern: ax_selected_range`).
/// - Fields with only `AXValue` (Warp's input editor) have no caret. They give
///   the section around the last unchanged copy of the pasted text, or else
///   the last characters in the same total bound, so an edited paste still
///   lies inside (`pattern: ax_value`).
/// - The Mac App Store sandbox blocks the Accessibility API for other apps:
///   that build answers `sandbox` without trying.
///
/// The read runs on a background queue with a short AX messaging timeout, so a
/// hanging target app never blocks the platform thread. Contents are never
/// logged.
final class TargetFieldHost {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "com.whispaste.inserted_span", qos: .utility)
  /// Chromium/Electron apps whose accessibility tree was already requested.
  private var enabledPids = Set<pid_t>()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.whispaste.inserted_span", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "readInsertedSpan" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    guard let expected = args?["expectedText"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing expectedText", details: nil))
      return
    }
    let slack = max(0, min((args?["slackChars"] as? Int) ?? 0, 4096))
    let length = min(expected.utf16.count + slack, 16384)
    let after = max(0, min((args?["afterChars"] as? Int) ?? 0, 16384))
    queue.async { [weak self] in
      var reply = self?.read(expected: expected, length: length, after: after) ?? Self.unreadable("uia_error")
      if let text = reply["text"] as? String {
        let strip = { (s: String) in s.replacingOccurrences(of: "\r", with: "") }
        reply["matchesExpected"] = strip(text).contains(strip(expected))
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  private static func unreadable(_ reason: String) -> [String: Any] {
    return ["readable": false, "text": NSNull(), "matchesExpected": false,
            "reason": reason, "pattern": NSNull()]
  }

  private static func readable(_ text: String, pattern: String) -> [String: Any] {
    return ["readable": true, "text": text, "matchesExpected": false,
            "reason": "ok", "pattern": pattern]
  }

  private func read(expected: String, length: Int, after: Int) -> [String: Any] {
#if MAS_BUILD
    return Self.unreadable("sandbox")
#else
    guard AXIsProcessTrusted() else { return Self.unreadable("permission_missing") }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.5)
    guard let focused = Self.element(system, kAXFocusedUIElementAttribute) else {
      return Self.unreadable("no_focus")
    }
    AXUIElementSetMessagingTimeout(focused, 0.5)
    var pid: pid_t = 0
    AXUIElementGetPid(focused, &pid)
    if pid == ProcessInfo.processInfo.processIdentifier { return Self.unreadable("own_window") }
    if IsSecureEventInputEnabled() || Self.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
      return Self.unreadable("password_field")
    }
    requestTree(pid: pid)
    if let span = caretSpan(focused, length: length, after: after) {
      return Self.readable(span, pattern: "ax_selected_range")
    }
    if let value = Self.string(focused, kAXValueAttribute) {
      return Self.readable(Self.valueSection(value, expected: expected, length: length, after: after),
                           pattern: "ax_value")
    }
    return Self.unreadable("no_text_pattern")
#endif
  }

  /// Bounded section of a caret-less value: around the last unchanged copy of
  /// [expected] when there is one, else its end. Never more than
  /// `length + after` UTF-16 units.
  private static func valueSection(_ value: String, expected: String, length: Int, after: Int) -> String {
    let units = Array(value.utf16)
    let total = length + after
    var end = units.count
    if !expected.isEmpty, let found = value.range(of: expected, options: .backwards) {
      // Centre the copy: half of the slack in front, half behind.
      let foundEnd = found.upperBound.utf16Offset(in: value)
      end = min(units.count, foundEnd + max(0, total - expected.utf16.count) / 2)
    }
    let start = max(0, end - total)
    return String(decoding: units[start..<end], as: UTF16.self)
  }

  /// Chromium and Electron build their accessibility tree only on request.
  /// Other apps ignore the attribute.
  private func requestTree(pid: pid_t) {
    guard !enabledPids.contains(pid) else { return }
    enabledPids.insert(pid)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.5)
    AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
  }

  private func caretSpan(_ element: AXUIElement, length: Int, after: Int) -> String? {
    guard let rangeValue = Self.value(element, kAXSelectedTextRangeAttribute),
      CFGetTypeID(rangeValue) == AXValueGetTypeID()
    else { return nil }
    var selection = CFRange()
    // swiftlint:disable:next force_cast
    guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return nil }
    let caret = selection.location + selection.length
    let start = max(0, caret - length)
    // Characters after the caret only when the field says how long it is;
    // a range past the end fails in most apps.
    var end = caret
    if after > 0, let count = Self.value(element, kAXNumberOfCharactersAttribute) as? Int {
      end = max(caret, min(caret + after, count))
    }
    var range = CFRange(location: start, length: end - start)
    guard let param = AXValueCreate(.cfRange, &range) else { return nil }
    var out: CFTypeRef?
    let status = AXUIElementCopyParameterizedAttributeValue(
      element, kAXStringForRangeParameterizedAttribute as CFString, param, &out)
    guard status == .success else { return nil }
    return out as? String
  }

  private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return status == .success ? value : nil
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    return value(element, attribute) as? String
  }

  private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
      return nil
    }
    // swiftlint:disable:next force_cast
    return (raw as! AXUIElement)
  }
}
