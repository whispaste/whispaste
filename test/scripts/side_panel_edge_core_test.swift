// Mirror of linux/runner/side_panel_edge_core_test.cc for SidePanelEdgeCore
// in macos/Runner/SidePanelWindow.swift (#1782): same cases, simulated time.
// Compiled together with the struct extracted from that file by
// test/scripts/side_panel_edge_core_test.sh (macOS only).

import Darwin

var failures = 0

func expect(_ ok: Bool, _ what: String) {
  if !ok {
    print("FAIL: \(what)")
    failures += 1
  }
}

typealias Core = SidePanelEdgeCore
let work = Core.Rect(left: 0, top: 0, right: 1920, bottom: 1040)
let monitor = Core.Rect(left: 0, top: 0, right: 1920, bottom: 1080)

do {
  expect(Core.inZone(x: 0, y: 500, workArea: work, width: 6, dockRight: false), "left edge, middle")
  expect(Core.inZone(x: 5, y: 500, workArea: work, width: 6, dockRight: false), "last px of the left strip")
  expect(!Core.inZone(x: 6, y: 500, workArea: work, width: 6, dockRight: false), "one px right of the strip")
  expect(Core.inZone(x: 0, y: 0, workArea: work, width: 6, dockRight: false), "top-left corner")
  expect(!Core.inZone(x: 0, y: 1040, workArea: work, width: 6, dockRight: false), "below the work area")
  expect(Core.inZone(x: 1919, y: 500, workArea: work, width: 6, dockRight: true), "right edge when docked right")
  expect(!Core.inZone(x: 0, y: 500, workArea: work, width: 6, dockRight: true), "left edge when docked right")
  expect(!Core.inZone(x: 0, y: 500, workArea: work, width: 0, dockRight: false), "zero width never matches")
}
do {
  expect(Core.coversMonitor(window: monitor, monitor: monitor), "exact monitor rect")
  expect(Core.coversMonitor(window: Core.Rect(left: -8, top: -8, right: 1928, bottom: 1088), monitor: monitor), "slightly larger")
  expect(!Core.coversMonitor(window: work, monitor: monitor), "maximised stops at the taskbar")
  expect(!Core.coversMonitor(window: monitor, monitor: Core.Rect(left: 0, top: 0, right: 0, bottom: 0)), "empty monitor")
}
do {
  var t = Core.Tracker(dwellMs: 60)
  var e = t.update(inZone: true, buttonsDown: false, nowMs: 0)
  expect(e.rawEnter && !e.open, "enter is raw only")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 40)
  expect(!e.open, "40 ms: not yet")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 80)
  expect(e.open, "80 ms: opens")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 120)
  expect(!e.open, "resting further does not reopen")
  e = t.update(inZone: false, buttonsDown: false, nowMs: 160)
  expect(e.rawExit && !e.open, "leaving fires raw exit")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 200)
  expect(e.rawEnter, "re-entering is a new visit")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 260)
  expect(e.open, "new visit opens again")
}
do {
  var t = Core.Tracker(dwellMs: 60)
  _ = t.update(inZone: true, buttonsDown: true, nowMs: 0)
  var e = t.update(inZone: true, buttonsDown: true, nowMs: 200)
  expect(!e.open, "dragging to the edge never opens")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 240)
  expect(!e.open, "release restarts the dwell")
  e = t.update(inZone: true, buttonsDown: false, nowMs: 300)
  expect(e.open, "resting after release opens")
}
do {
  var t = Core.Tracker(dwellMs: 60)
  var now: Int64 = 0
  while now < 2000 {
    let e = t.update(inZone: false, buttonsDown: false, nowMs: now)
    expect(!e.rawEnter && !e.rawExit && !e.open, "fullscreen: silent")
    now += 40
  }
  _ = t.update(inZone: true, buttonsDown: false, nowMs: 2000)
  let e = t.update(inZone: false, buttonsDown: false, nowMs: 2040)
  expect(e.rawExit, "fullscreen mid-visit ends it")
}
do {
  var t = Core.Tracker(dwellMs: 60)
  _ = t.update(inZone: true, buttonsDown: false, nowMs: 0)
  t.reset()
  expect(!t.inside, "reset leaves the zone")
  let e = t.update(inZone: false, buttonsDown: false, nowMs: 40)
  expect(!e.rawExit, "no raw exit after reset")
}
expect(Core.zoneWidth == 6 && Core.dwellMs == 60 && Core.pollMs == 40, "constants match the C++ core")

if failures == 0 { print("side_panel_edge_core_test (Swift): all passed") }
exit(failures == 0 ? 0 : 1)
