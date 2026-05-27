import CoreAudio
import FlutterMacOS
import Foundation
import os.log

/// Bridge that lets Dart temporarily switch the system's default audio-input
/// device for the duration of a recording.
///
/// Background — why this exists:
///
/// The `record_macos` Flutter plugin uses `AVAudioEngine.inputNode` for the
/// streaming recorder. On macOS 15/26 (Sequoia/Tahoe),
/// `inputNode.auAudioUnit.setDeviceID(...)` is silently ignored — the input
/// node stays bound to whatever device the system default was at engine
/// construction time, no matter what device the user picked in WhisPaste's
/// settings. A direct switch to `AVCaptureSession` solves the routing bug
/// but holds the audio HAL in exclusive-mode and blocks the SoLoud-backed
/// sound-feedback output (start/stop chimes go silent).
///
/// The workaround Logic Pro, Audacity, OBS and others use: flip the system
/// default input device to the desired one *just* before opening the input
/// stream, then restore the original on stop. The user-perceived window is
/// the recording duration (a few seconds), during which other apps that
/// happen to follow the system default see the same switch.
class AudioRoutingHost {
  private static let logger = OSLog(
    subsystem: "com.whispaste.audio", category: "AudioRoutingHost")

  private var channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.audio_routing",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDefaultInputDevice":
      result(getDefaultInputDeviceUID())

    case "setDefaultInputDevice":
      guard let args = call.arguments as? [String: Any],
        let uid = args["uid"] as? String
      else {
        result(
          FlutterError(code: "INVALID_ARGS", message: "Missing 'uid'", details: nil))
        return
      }
      let ok = setDefaultInputDevice(uid: uid)
      result(ok)

    case "listInputDevices":
      result(listInputDevices())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Enumerates every CoreAudio device that has at least one input stream.
  /// Returns `[{"id": <UID>, "label": <name>}]` so the Flutter side gets the
  /// same UID that [setDefaultInputDevice] expects — avoiding the
  /// `AVCaptureDevice.uniqueID` vs. CoreAudio-UID mismatch that bites the
  /// `record_macos` path. Available without microphone permission because
  /// CoreAudio device discovery doesn't go through TCC.
  private func listInputDevices() -> [[String: String]] {
    var size: UInt32 = 0
    var devicesAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &devicesAddress,
      0,
      nil,
      &size
    )
    guard status == noErr else { return [] }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &devicesAddress,
      0,
      nil,
      &size,
      &devices
    )
    guard status == noErr else { return [] }

    var result: [[String: String]] = []
    for id in devices {
      guard isInputDevice(deviceID: id) else { continue }
      guard let uid = uidForDevice(deviceID: id) else { continue }
      let label = nameForDevice(deviceID: id) ?? uid
      result.append(["id": uid, "label": label])
    }
    return result
  }

  /// `true` when the device exposes at least one input stream.
  private func isInputDevice(deviceID: AudioDeviceID) -> Bool {
    var size: UInt32 = 0
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyDataSize(
      deviceID, &address, 0, nil, &size
    )
    return status == noErr && size > 0
  }

  /// Returns the user-visible name of a CoreAudio device.
  private func nameForDevice(deviceID: AudioDeviceID) -> String? {
    var cfName: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      deviceID, &address, 0, nil, &size, &cfName
    )
    guard status == noErr, let cf = cfName?.takeRetainedValue() else {
      return nil
    }
    return cf as String
  }

  // MARK: - CoreAudio helpers

  /// Returns the `kAudioDevicePropertyDeviceUID` of the system's current
  /// default input device, or nil if the lookup fails.
  private func getDefaultInputDeviceUID() -> String? {
    var deviceID: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    guard status == noErr else {
      os_log(
        "getDefaultInputDevice: AudioObjectGetPropertyData failed: %{public}d",
        log: Self.logger, type: .error, status)
      return nil
    }
    return uidForDevice(deviceID: deviceID)
  }

  /// Sets the system default input device to the one matching `uid`. Returns
  /// `true` when the switch landed, `false` otherwise.
  private func setDefaultInputDevice(uid: String) -> Bool {
    guard let deviceID = deviceForUID(uid: uid) else {
      os_log(
        "setDefaultInputDevice: no device with uid=%{public}@",
        log: Self.logger, type: .error, uid)
      return false
    }
    var newDevice = deviceID
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      size,
      &newDevice
    )
    if status != noErr {
      os_log(
        "setDefaultInputDevice: AudioObjectSetPropertyData failed: %{public}d",
        log: Self.logger, type: .error, status)
      return false
    }
    os_log(
      "setDefaultInputDevice: switched to uid=%{public}@ (id=%{public}d)",
      log: Self.logger, type: .info, uid, newDevice)
    return true
  }

  /// Returns the `kAudioDevicePropertyDeviceUID` string for `deviceID`.
  private func uidForDevice(deviceID: AudioDeviceID) -> String? {
    var cfUID: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &cfUID
    )
    guard status == noErr, let cf = cfUID?.takeRetainedValue() else {
      return nil
    }
    return cf as String
  }

  /// Returns the `AudioDeviceID` for the device with the given UID, or nil
  /// if no input device matches.
  private func deviceForUID(uid: String) -> AudioDeviceID? {
    // Get list of all devices.
    var size: UInt32 = 0
    var devicesAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &devicesAddress,
      0,
      nil,
      &size
    )
    guard status == noErr else { return nil }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &devicesAddress,
      0,
      nil,
      &size,
      &devices
    )
    guard status == noErr else { return nil }

    for id in devices {
      if let candidate = uidForDevice(deviceID: id), candidate == uid {
        return id
      }
    }
    return nil
  }
}
