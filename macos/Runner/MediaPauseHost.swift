import AppKit
import CoreAudio
import AudioToolbox
import FlutterMacOS
import os.log

/// Pauses or turns down running media while WhisPaste records (#1511).
///
/// macOS offers apps no system-wide media control since 15.4 (the old
/// MediaRemote interface was private, #1254). So this host
///  * pauses the players it can address by Apple Events (Music, Spotify) and
///    resumes exactly those, and only if they were playing;
///  * turns the default output device down and back up to the exact previous
///    volume ("Leiser stellen"), but only while another process plays sound.
///
/// Store-compatible: in the sandbox the players are reached through their
/// published scripting access groups (`com.apple.security.scripting-targets`:
/// `com.apple.Music.playback`, `com.spotify.playback`), no temporary
/// exception. The automation permission is asked only from the settings
/// (`requestPlayerAccess`), never during a dictation: there a player without
/// permission is skipped silently.
///
/// Channel "com.whispaste.media_pause", contract in
/// lib/services/media_pause/media_pause_backends.dart.
final class MediaPauseHost {
  private static let log = OSLog(subsystem: "com.whispaste.audio", category: "MediaPause")

  /// A player reachable by Apple Events. Both use the same `player state`
  /// property (`pPlS`) with the enumerators `kPSP` playing / `kPSp` paused.
  private struct Player {
    let bundleId: String
    let suite: String  // event class of play/pause
  }

  private static let players = [
    Player(bundleId: "com.apple.Music", suite: "hook"),
    Player(bundleId: "com.spotify.client", suite: "spfy"),
  ]

  private let channel: FlutterMethodChannel
  /// Pause and resume run here in call order, so a resume never overtakes
  /// its pause.
  private let queue = DispatchQueue(label: "com.whispaste.media_pause")
  /// Volume calls never wait behind an Apple Event to a player that hangs.
  private let duckQueue = DispatchQueue(label: "com.whispaste.media_pause.duck")
  /// The permission dialog can stay open for minutes; it must not hold the
  /// pause of the next dictation.
  private let accessQueue = DispatchQueue(label: "com.whispaste.media_pause.access")
  /// Bundle ids this host paused; only these are resumed. Touched on [queue].
  private var paused: [String] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.whispaste.media_pause", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      // Apple Events and HAL calls can block; keep them off the main thread.
      let target: DispatchQueue
      switch call.method {
      case "duckAvailable", "playingVolumes", "setVolumes": target = self.duckQueue
      case "requestPlayerAccess": target = self.accessQueue
      default: target = self.queue
      }
      target.async {
        let reply = self.handle(call)
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  private func handle(_ call: FlutterMethodCall) -> Any? {
    switch call.method {
    case "isAvailable":
      return true
    case "pauseIfPlaying":
      return pauseIfPlaying()
    case "resumePaused":
      resumePaused()
      return nil
    case "requestPlayerAccess":
      return requestPlayerAccess()
    case "duckAvailable":
      return duckAvailable()
    case "playingVolumes":
      return playingVolumes()
    case "setVolumes":
      setVolumes(call.arguments as? [[String: Any]] ?? [])
      return nil
    default:
      return FlutterMethodNotImplemented
    }
  }

  // MARK: - Pause (Apple Events)

  private static func isRunning(_ player: Player) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleId).isEmpty
  }

  private static func target(_ player: Player) -> NSAppleEventDescriptor {
    NSAppleEventDescriptor(bundleIdentifier: player.bundleId)
  }

  /// noErr when allowed; never shows a dialog unless [ask] is set.
  private static func permission(_ player: Player, ask: Bool) -> OSStatus {
    guard let desc = target(player).aeDesc else { return OSStatus(procNotFound) }
    return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
  }

  /// Players whose permission check has not returned yet. Touched under
  /// [probeLock].
  private static var probing: Set<String> = []
  private static let probeLock = NSLock()

  /// The permission check without dialog, bounded: macOS answers it only
  /// once the player does, and a player stuck in a sheet or a beach ball
  /// would block it for good. Nil when it did not answer in time; the stuck
  /// check is not started again until it returns.
  private static func quickPermission(_ player: Player) -> OSStatus? {
    probeLock.lock()
    guard !probing.contains(player.bundleId) else {
      probeLock.unlock()
      return nil
    }
    probing.insert(player.bundleId)
    probeLock.unlock()
    let done = DispatchSemaphore(value: 0)
    let box = StatusBox()
    DispatchQueue.global(qos: .userInitiated).async {
      box.set(permission(player, ask: false))
      probeLock.lock()
      probing.remove(player.bundleId)
      probeLock.unlock()
      done.signal()
    }
    guard done.wait(timeout: .now() + 1) == .success else { return nil }
    return box.get()
  }

  private final class StatusBox {
    private let lock = NSLock()
    private var status = OSStatus(procNotFound)
    func set(_ value: OSStatus) { lock.lock(); status = value; lock.unlock() }
    func get() -> OSStatus { lock.lock(); defer { lock.unlock() }; return status }
  }

  private static func fourCC(_ s: String) -> FourCharCode {
    s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
  }

  private static func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
    try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
  }

  /// `kPSP`, `kPSp`, `kPSS` … or nil when the player does not answer.
  private static func playerState(_ player: Player) -> FourCharCode? {
    let get = NSAppleEventDescriptor(
      eventClass: fourCC("core"), eventID: fourCC("getd"),
      targetDescriptor: target(player), returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    // Object specifier: property `pPlS` of the application.
    let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: fourCC("obj "))!
    spec.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC("prop")), forKeyword: fourCC("want"))
    spec.setDescriptor(NSAppleEventDescriptor(enumCode: fourCC("prop")), forKeyword: fourCC("form"))
    spec.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC("pPlS")), forKeyword: fourCC("seld"))
    spec.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: fourCC("from"))
    get.setParam(spec, forKeyword: keyDirectObject)
    let reply: NSAppleEventDescriptor
    do {
      reply = try send(get)
    } catch {
      os_log("%{public}@: reading the player state failed: %{public}@", log: log, type: .error,
             player.bundleId, String(describing: error))
      return nil
    }
    let value = reply.paramDescriptor(forKeyword: keyDirectObject) ?? reply
    os_log("%{public}@: player state %{public}@", log: log, type: .info,
           player.bundleId, Self.fourCCString(value.enumCodeValue))
    return value.enumCodeValue
  }

  private static func fourCCString(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
  }

  private static func command(_ player: Player, _ id: String) -> Bool {
    let event = NSAppleEventDescriptor(
      eventClass: fourCC(player.suite), eventID: fourCC(id),
      targetDescriptor: target(player), returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    do {
      _ = try send(event)
      return true
    } catch {
      os_log("%{public}@: %{public}@ failed: %{public}@", log: log, type: .error,
             player.bundleId, id, String(describing: error))
      return false
    }
  }

  private static let playing = fourCC("kPSP")
  private static let pausedState = fourCC("kPSp")

  private func pauseIfPlaying() -> String {
    var any = false
    var reachable = false
    for player in Self.players where Self.isRunning(player) {
      // A player without permission is skipped: no dialog mid-dictation.
      guard let status = Self.quickPermission(player) else {
        os_log("%{public}@: does not answer, skipped", log: Self.log, type: .error,
               player.bundleId)
        continue
      }
      guard status == noErr else {
        os_log("%{public}@: no automation permission (%d), skipped", log: Self.log, type: .info,
               player.bundleId, status)
        continue
      }
      reachable = true
      guard Self.playerState(player) == Self.playing else { continue }
      if Self.command(player, "Paus") {
        paused.append(player.bundleId)
        any = true
      }
    }
    if any { return "paused" }
    return reachable ? "nothing" : "unavailable"
  }

  private func resumePaused() {
    let mine = paused
    paused = []
    for player in Self.players where mine.contains(player.bundleId) {
      // Resume only if still paused: if the user stopped or started it
      // meanwhile, leave it alone.
      guard Self.isRunning(player), Self.playerState(player) == Self.pausedState else { continue }
      _ = Self.command(player, "Play")
    }
  }

  /// Asks macOS once per running supported player; returns how many may be
  /// controlled now. A player that is not running cannot be asked; it is
  /// asked the next time the user picks "Pause" with it running.
  private func requestPlayerAccess() -> Int {
    var granted = 0
    for player in Self.players where Self.isRunning(player) {
      let status = Self.permission(player, ask: true)
      os_log("%{public}@: automation permission %d", log: Self.log, type: .info,
             player.bundleId, status)
      if status == noErr { granted += 1 }
    }
    return granted
  }

  // MARK: - Duck (Core Audio)

  private static func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private static var volumeAddress: AudioObjectPropertyAddress {
    address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
  }

  private static func defaultOutputDevice() -> AudioObjectID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    return status == noErr && device != kAudioObjectUnknown ? device : nil
  }

  private static func uid(of device: AudioObjectID) -> String? {
    var addr = address(kAudioDevicePropertyDeviceUID)
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid) == noErr,
          let value = uid?.takeRetainedValue() else { return nil }
    return value as String
  }

  private static func device(forUID uid: String) -> AudioObjectID? {
    var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
    var cfUID = uid as CFString
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &cfUID) { ptr in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr,
        UInt32(MemoryLayout<CFString>.size), ptr, &size, &device)
    }
    return status == noErr && device != kAudioObjectUnknown ? device : nil
  }

  private static func canSetVolume(_ device: AudioObjectID) -> Bool {
    var addr = volumeAddress
    guard AudioObjectHasProperty(device, &addr) else { return false }
    var settable: DarwinBoolean = false
    return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
  }

  private static func volume(_ device: AudioObjectID) -> Float32? {
    var addr = volumeAddress
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value : nil
  }

  private static func setVolume(_ device: AudioObjectID, _ value: Float32) {
    var addr = volumeAddress
    var v = min(max(value, 0), 1)
    let status = AudioObjectSetPropertyData(
      device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    if status != noErr {
      os_log("setting the output volume failed: %d", log: log, type: .error, status)
    }
  }

  /// Whether a process other than WhisPaste sends sound right now. Needs the
  /// per-process audio objects of macOS 14.2; older systems cannot tell
  /// WhisPaste's own sound output from other playback, so ducking is not
  /// offered there.
  private static func othersPlaying() -> Bool? {
    guard #available(macOS 14.2, *) else { return nil }
    var addr = address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    let sizeStatus = AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size)
    guard sizeStatus == noErr else {
      os_log("audio process list unavailable: %d", log: log, type: .error, sizeStatus)
      return nil
    }
    var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &processes) == noErr else {
      return nil
    }
    let own = getpid()
    os_log("%d audio process objects", log: log, type: .info, processes.count)
    for process in processes {
      var pidAddr = address(kAudioProcessPropertyPID)
      var pid: pid_t = 0
      var pidSize = UInt32(MemoryLayout<pid_t>.size)
      guard AudioObjectGetPropertyData(process, &pidAddr, 0, nil, &pidSize, &pid) == noErr,
            pid != own else { continue }
      var runAddr = address(kAudioProcessPropertyIsRunningOutput)
      var running: UInt32 = 0
      var runSize = UInt32(MemoryLayout<UInt32>.size)
      if AudioObjectGetPropertyData(process, &runAddr, 0, nil, &runSize, &running) == noErr,
         running != 0 {
        os_log("process %d plays sound", log: log, type: .info, pid)
        return true
      }
    }
    return false
  }

  private func duckAvailable() -> Bool {
    guard #available(macOS 14.2, *), let device = Self.defaultOutputDevice() else { return false }
    return Self.canSetVolume(device)
  }

  private func playingVolumes() -> [[String: Any]] {
    let others = Self.othersPlaying()
    os_log("other process playing: %{public}@", log: Self.log, type: .info,
           others.map { $0 ? "yes" : "no" } ?? "unknown")
    guard others == true,
          let device = Self.defaultOutputDevice(),
          Self.canSetVolume(device),
          let uid = Self.uid(of: device),
          let level = Self.volume(device) else { return [] }
    return [["id": uid, "levels": [Double(level)]]]
  }

  private func setVolumes(_ targets: [[String: Any]]) {
    for target in targets {
      guard let uid = target["id"] as? String,
            let level = (target["levels"] as? [NSNumber])?.first,
            let device = Self.device(forUID: uid),  // gone (unplugged): skip
            Self.canSetVolume(device) else { continue }
      Self.setVolume(device, level.floatValue)
    }
  }
}
