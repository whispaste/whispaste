import Cocoa
import Darwin
import FlutterMacOS

/// Decision logic of the hang watchdog (#338). Mirrors
/// `linux/runner/hang_watchdog_core.h` rule for rule (that file is shared
/// with the Windows runner and covered by `test/scripts/hang_watchdog_core_test.sh`);
/// change both together.
struct HangWatchdogCore {
  static let defaultThresholdMs: Int64 = 20_000
  static let tickMs: Int64 = 1_000
  static let wakeGapMs: Int64 = 5_000
  static let wakeGraceMs: Int64 = 30_000
  static let restartCooldownMs: Int64 = 10 * 60 * 1_000

  private var armed = false
  private var fired = false
  private var thresholdMs = defaultThresholdMs
  private var lastBeatMs: Int64 = 0
  private var lastTickMs: Int64 = 0
  private var graceUntilMs: Int64 = 0

  mutating func arm(nowMs: Int64, thresholdMs: Int64) {
    armed = true
    fired = false
    self.thresholdMs = thresholdMs > 0 ? thresholdMs : Self.defaultThresholdMs
    lastBeatMs = nowMs
    lastTickMs = nowMs
    graceUntilMs = 0
  }

  mutating func disarm() { armed = false }

  mutating func beat(nowMs: Int64) { lastBeatMs = nowMs }

  /// True exactly once per armed session, when the beat stayed away too long.
  mutating func tick(nowMs: Int64) -> Bool {
    if !armed || fired {
      lastTickMs = nowMs
      return false
    }
    if nowMs - lastTickMs > Self.wakeGapMs {
      // The machine slept; the threshold starts counting after the grace.
      graceUntilMs = nowMs + Self.wakeGraceMs
      lastBeatMs = graceUntilMs
    }
    lastTickMs = nowMs
    if nowMs < graceUntilMs { return false }
    if nowMs - lastBeatMs < thresholdMs { return false }
    fired = true
    return true
  }

  func stalledMs(nowMs: Int64) -> Int64 { nowMs - lastBeatMs }

  static func mayRestart(nowWallMs: Int64, lastRestartWallMs: Int64) -> Bool {
    if lastRestartWallMs <= 0 { return true }
    let since = nowWallMs - lastRestartWallMs
    return since < 0 || since >= restartCooldownMs
  }
}

/// Owns the MethodChannel `com.whispaste.hang_watchdog` (#338).
///
/// Dart arms the watchdog once the app is up and then sends `beat` every 2 s;
/// the call is answered on the main thread, so a beat proves that both the UI
/// isolate and the main run loop still run. A watchdog thread ticks the core
/// once a second. On a hang it writes the marker file (diagnosis for the next
/// start), logs a short diagnosis and, at most once per 10 minutes, restarts
/// the app: a detached shell waits until this process is gone (single
/// instance stays intact) and opens the bundle again; this process then ends
/// with `_exit` because its main thread no longer answers.
final class HangWatchdogHost {
  static let channelName = "com.whispaste.hang_watchdog"
  private static let markerFile = "hang_watchdog_marker"
  private static let lastRestartFile = "hang_watchdog_last_restart"

  private let channel: FlutterMethodChannel
  private let lock = NSLock()
  private var core = HangWatchdogCore()
  private var markerDir = ""
  private var thresholdMs: Int64 = 0
  private var thread: Thread?
  private var stopped = false
  /// Armed by Dart (and not disarmed by an orderly quit).
  private var dartArmed = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    let thread = Thread { [weak self] in self?.loop() }
    thread.name = "whispaste.hang-watchdog"
    thread.qualityOfService = .userInitiated
    self.thread = thread
    thread.start()
  }

  deinit { stop() }

  func stop() {
    lock.lock()
    stopped = true
    core.disarm()
    lock.unlock()
  }

  /// Disarms around deliberate main-thread blocks (modal alerts) and re-arms
  /// with a fresh beat afterwards.
  func pause() {
    lock.lock()
    core.disarm()
    lock.unlock()
  }

  func resume() {
    lock.lock()
    if dartArmed && !stopped { core.arm(nowMs: Self.monotonicMs(), thresholdMs: thresholdMs) }
    lock.unlock()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beat":
      lock.lock()
      core.beat(nowMs: Self.monotonicMs())
      lock.unlock()
    case "arm":
      let args = call.arguments as? [String: Any]
      let dir = args?["markerDir"] as? String ?? ""
      let threshold = (args?["thresholdMs"] as? NSNumber)?.int64Value ?? 0
      lock.lock()
      markerDir = dir
      thresholdMs = threshold
      dartArmed = true
      core.arm(nowMs: Self.monotonicMs(), thresholdMs: threshold)
      lock.unlock()
    case "disarm":
      lock.lock()
      dartArmed = false
      core.disarm()
      lock.unlock()
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  private func loop() {
    while true {
      Thread.sleep(forTimeInterval: Double(HangWatchdogCore.tickMs) / 1_000)
      lock.lock()
      if stopped {
        lock.unlock()
        return
      }
      let now = Self.monotonicMs()
      let hang = core.tick(nowMs: now)
      let stalled = core.stalledMs(nowMs: now)
      let dir = markerDir
      lock.unlock()
      if hang { onHang(stalledMs: stalled, markerDir: dir) }
    }
  }

  private func onHang(stalledMs: Int64, markerDir: String) {
    let wall = Int64(Date().timeIntervalSince1970 * 1_000)
    let lastPath = (markerDir as NSString).appendingPathComponent(Self.lastRestartFile)
    let lastRestart = Int64(
      (try? String(contentsOfFile: lastPath, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    let mayRestart = !markerDir.isEmpty
      && HangWatchdogCore.mayRestart(nowWallMs: wall, lastRestartWallMs: lastRestart)
    NSLog(
      "[hang-watchdog] main thread silent for %lld ms, %@", stalledMs,
      mayRestart ? "restarting" : "restart cooldown, diagnosis only")
    if markerDir.isEmpty { return }
    var restarting = mayRestart
    if restarting {
      // No restart unless the cooldown stamp is on disk: otherwise a full or
      // read-only data directory would restart the app in a loop.
      let stamped: Bool
      do {
        try String(wall).write(toFile: lastPath, atomically: true, encoding: .utf8)
        stamped = true
      } catch {
        stamped = false
      }
      restarting = stamped && Self.spawnRelaunchAfterExit()
    }
    let marker = "stalled_ms=\(stalledMs)\nrestarted=\(restarting ? 1 : 0)\nat_ms=\(wall)\n"
    try? marker.write(
      toFile: (markerDir as NSString).appendingPathComponent(Self.markerFile),
      atomically: true, encoding: .utf8)
    if restarting { _exit(70) }
  }

  /// CLOCK_MONOTONIC keeps counting during sleep on macOS, so a suspend shows
  /// up as a late tick (wake grace).
  private static func monotonicMs() -> Int64 {
    Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000)
  }

  private static func spawnRelaunchAfterExit() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c",
      "p=$1; shift; i=0; while kill -0 \"$p\" 2>/dev/null && [ $i -lt 150 ]; "
        + "do sleep 0.2; i=$((i+1)); done; exec /usr/bin/open \"$1\"",
      "sh", String(getpid()), Bundle.main.bundlePath,
    ]
    do {
      try process.run()
      return true
    } catch {
      return false
    }
  }
}
