// Mirror of linux/runner/hang_watchdog_core_test.cc for HangWatchdogCore in
// macos/Runner/HangWatchdogHost.swift (#338): same cases, simulated time.
// Compiled together with the struct extracted from that file by
// test/scripts/hang_watchdog_core_test.sh (macOS only).

import Darwin

var failures = 0

func expect(_ ok: Bool, _ what: String) {
  if !ok {
    print("FAIL: \(what)")
    failures += 1
  }
}

/// Ticks every second from `from` to `to` (inclusive); first hang or -1.
func runTicks(_ core: inout HangWatchdogCore, _ from: Int64, _ to: Int64) -> Int64 {
  var t = from
  while t <= to {
    if core.tick(nowMs: t) { return t }
    t += HangWatchdogCore.tickMs
  }
  return -1
}

do {
  var core = HangWatchdogCore()
  expect(runTicks(&core, 0, 120_000) == -1, "unarmed core never reports a hang")
}
do {
  var core = HangWatchdogCore()
  core.arm(nowMs: 0, thresholdMs: 20_000)
  expect(runTicks(&core, 1_000, 19_000) == -1, "below threshold is no hang")
  expect(runTicks(&core, 20_000, 20_000) == 20_000, "threshold reached is a hang")
  expect(core.stalledMs(nowMs: 20_000) == 20_000, "stall length reported")
  expect(runTicks(&core, 21_000, 90_000) == -1, "only one hang per session")
}
do {
  var core = HangWatchdogCore()
  core.arm(nowMs: 0, thresholdMs: 20_000)
  var t: Int64 = 1_000
  while t <= 300_000 {
    if t % 2_000 == 0 { core.beat(nowMs: t) }
    expect(!core.tick(nowMs: t), "regular beats never hang")
    t += 1_000
  }
}
do {
  var core = HangWatchdogCore()
  core.arm(nowMs: 0, thresholdMs: 20_000)
  _ = core.tick(nowMs: 1_000)
  expect(!core.tick(nowMs: 7_201_000), "tick after sleep is no hang")
  expect(runTicks(&core, 7_202_000, 7_231_000) == -1, "no hang inside wake grace")
  expect(runTicks(&core, 7_232_000, 7_260_000) != -1, "silence after the grace still is a hang")
}
do {
  var core = HangWatchdogCore()
  core.arm(nowMs: 0, thresholdMs: 20_000)
  core.disarm()
  expect(runTicks(&core, 1_000, 60_000) == -1, "disarmed core is silent")
}
do {
  let tenMin = HangWatchdogCore.restartCooldownMs
  expect(HangWatchdogCore.mayRestart(nowWallMs: 1_000, lastRestartWallMs: 0), "first restart allowed")
  expect(!HangWatchdogCore.mayRestart(nowWallMs: tenMin - 1, lastRestartWallMs: 1), "restart within 10 min refused")
  expect(HangWatchdogCore.mayRestart(nowWallMs: tenMin + 1, lastRestartWallMs: 1), "restart after 10 min allowed")
  expect(HangWatchdogCore.mayRestart(nowWallMs: 1_000, lastRestartWallMs: 5_000), "clock set back allows a restart")
}

if failures == 0 { print("hang_watchdog_core_test (Swift): all passed") }
exit(failures == 0 ? 0 : 1)
