import Cocoa
import FlutterMacOS
import XCTest
import Carbon.HIToolbox
@testable import WhisPaste

class RunnerTests: XCTestCase {

  /// Briefing N7: the paste key follows the letter on the active layout. On a
  /// Dvorak-like layout "v" sits on a different physical key than on ANSI.
  func testPasteKeyFollowsTheLayoutLetter() {
    let layout: [CGKeyCode: String] = [0x09: "k", 0x28: "v", 0x08: "j"]
    let code = keyCode(forCharacter: "v", layoutCharacter: { layout[$0] }, fallback: 0x09)
    XCTAssertEqual(code, 0x28)
  }

  func testCopyKeyFollowsTheLayoutLetter() {
    let layout: [CGKeyCode: String] = [0x09: "k", 0x28: "v", 0x08: "j", 0x0D: "c"]
    let code = keyCode(forCharacter: "c", layoutCharacter: { layout[$0] }, fallback: 0x08)
    XCTAssertEqual(code, 0x0D)
  }

  /// Installed layouts, read without switching the active one (#569). With
  /// Command held, "Dvorak - QWERTY ⌘" and Russian keep V on the ANSI key,
  /// plain Dvorak moves it.
  private func installedLayout(_ id: String) throws -> TISInputSource {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    guard let source = list?.first else {
      throw XCTSkip("layout \(id) is not installed on this Mac")
    }
    return source
  }

  func testCommandPasteKeyOnInstalledLayouts() throws {
    for (id, expected) in [
      ("com.apple.keylayout.US", 0x09),
      ("com.apple.keylayout.German", 0x09),
      ("com.apple.keylayout.DVORAK-QWERTYCMD", 0x09),
      ("com.apple.keylayout.Russian", 0x09),
    ] as [(String, CGKeyCode)] {
      let source = try installedLayout(id)
      let code = keyCode(forCharacter: "v",
                         layoutCharacter: { commandCharacter(for: $0, in: source) },
                         fallback: 0xFF)
      XCTAssertEqual(code, expected, id)
    }
    let dvorak = try installedLayout("com.apple.keylayout.Dvorak")
    let code = keyCode(forCharacter: "v",
                       layoutCharacter: { commandCharacter(for: $0, in: dvorak) },
                       fallback: 0xFF)
    XCTAssertEqual(code, 0x2F)
  }

  // MARK: Keystroke undo (#581)

  func testUndoGoesOnlyToKnownTextApps() {
    XCTAssertTrue(isUndoSafeBundle("com.google.Chrome"))
    XCTAssertTrue(isUndoSafeBundle("com.apple.TextEdit"))
    XCTAssertFalse(isUndoSafeBundle("com.apple.Terminal"))
    XCTAssertFalse(isUndoSafeBundle("com.googlecode.iterm2"))
    XCTAssertFalse(isUndoSafeBundle("com.microsoft.VSCode"))
    XCTAssertFalse(isUndoSafeBundle("com.example.Unknown"))
  }

  private func undoCheck(
    target: String? = "com.apple.TextEdit", front: Bool = true, covers: Bool = true,
    since: Double = 5, key: Double = 4.99, synthetic: Double = 5, mouse: Double = 30
  ) -> UndoSendCheck {
    decideUndoSend(targetBundle: target, frontIsTarget: front, covers: covers,
                   sinceInsert: since, keyIdle: key, syntheticIdle: synthetic,
                   mouseIdleOutsideApp: mouse)
  }

  func testUndoKeystrokeNeedsEveryProof() {
    XCTAssertEqual(undoCheck(), .send)
    XCTAssertEqual(undoCheck(target: nil), .noTarget)
    XCTAssertEqual(undoCheck(covers: false), .watcherInactive)
    XCTAssertEqual(undoCheck(front: false), .foregroundChanged)
    XCTAssertEqual(undoCheck(target: "com.apple.Terminal"), .unsafeTarget)
    XCTAssertEqual(undoCheck(key: 2), .userInput)
    XCTAssertEqual(undoCheck(mouse: 2), .userInput)
    // A hardware key-down right after our own synthetic one is not typing.
    XCTAssertEqual(undoCheck(key: 4.97, synthetic: 5), .send)
  }

  func testUndoWatchCoversOnlyAfterAnInsertWithARunningMonitor() {
    var now = 100.0
    let watch = UndoWatch(clock: { now }, install: { _ in NSObject() }, remove: { _ in })
    XCTAssertFalse(watch.covers)
    watch.markInsert()
    XCTAssertTrue(watch.covers)
    now = 111
    XCTAssertEqual(watch.sinceInsert, 11, accuracy: 0.001)
    XCTAssertEqual(watch.mouseIdleOutsideApp, 11, accuracy: 0.001)
    // A sent undo or a new target ends the proof of that insert.
    watch.clearInsert()
    XCTAssertFalse(watch.covers)
    watch.markInsert()
    XCTAssertTrue(watch.covers)
    watch.stop()
    XCTAssertFalse(watch.covers)
  }

  // MARK: User's own Cmd+Z after an auto-paste (#2078)

  func testOnlyPlainCommandZIsTheUndoShortcut() {
    XCTAssertTrue(isUndoShortcut(flags: [.command], characters: "z"))
    XCTAssertTrue(isUndoShortcut(flags: [.command, .capsLock], characters: "Z"))
    XCTAssertFalse(isUndoShortcut(flags: [.command, .shift], characters: "z"))
    XCTAssertFalse(isUndoShortcut(flags: [.command, .option], characters: "z"))
    XCTAssertFalse(isUndoShortcut(flags: [.control], characters: "z"))
    XCTAssertFalse(isUndoShortcut(flags: [], characters: "z"))
    XCTAssertFalse(isUndoShortcut(flags: [.command], characters: "y"))
    XCTAssertFalse(isUndoShortcut(flags: [.command], characters: nil))
  }

  func testUndoShortcutWatchCountsOnlyWhileWatching() {
    var removed = 0
    let watch = UndoShortcutWatch(trusted: { true }, install: { _ in NSObject() },
                                  remove: { _ in removed += 1 })
    watch.note(flags: [.command], characters: "z", isRepeat: false, fromSelf: false)
    XCTAssertFalse(watch.seen, "no watch armed")
    XCTAssertEqual(watch.watch(seconds: 15).watching, true)
    watch.note(flags: [.command], characters: "z", isRepeat: false, fromSelf: true)
    watch.note(flags: [.command], characters: "z", isRepeat: true, fromSelf: false)
    XCTAssertFalse(watch.seen, "own keys and repeats never count")
    watch.note(flags: [.command], characters: "z", isRepeat: false, fromSelf: false)
    XCTAssertTrue(watch.take())
    XCTAssertEqual(removed, 1)
    XCTAssertFalse(watch.take(), "taken once")
  }

  func testUndoShortcutWatchReportsThePreviousWatch() {
    let watch = UndoShortcutWatch(trusted: { true }, install: { _ in NSObject() },
                                  remove: { _ in })
    _ = watch.watch(seconds: 15)
    watch.note(flags: [.command], characters: "z", isRepeat: false, fromSelf: false)
    let next = watch.watch(seconds: 15)
    XCTAssertTrue(next.watching)
    XCTAssertTrue(next.seen)
    XCTAssertFalse(watch.seen, "the new watch starts clean")
  }

  func testUndoShortcutWatchNeedsTheAccessibilityPermission() {
    var installs = 0
    let watch = UndoShortcutWatch(trusted: { false },
                                  install: { _ in installs += 1; return NSObject() },
                                  remove: { _ in })
    XCTAssertFalse(watch.watch(seconds: 15).watching)
    XCTAssertEqual(installs, 0, "no monitor without the permission")
    XCTAssertFalse(watch.watch(seconds: 0).watching)
  }

  func testUndoWatchWithoutAMonitorIsNeverProof() {
    let watch = UndoWatch(clock: { 5 }, install: { _ in nil })
    watch.markInsert()
    XCTAssertFalse(watch.covers)
  }

  /// The undo key follows the letter as well (#581): on AZERTY "z" sits on the
  /// ANSI "w" key (0x0D), and the fixed ANSI "z" position (0x06) would send
  /// Cmd+W there, which closes the window.
  func testUndoKeyFollowsTheLayoutLetter() {
    let layout: [CGKeyCode: String] = [0x06: "w", 0x0D: "z"]
    let code = keyCode(forCharacter: "z", layoutCharacter: { layout[$0] }, fallback: 0x06)
    XCTAssertEqual(code, 0x0D)
  }

  func testFallsBackToAnsiPositionWhenNoKeyTypesTheLetter() {
    let code = keyCode(forCharacter: "v", layoutCharacter: { _ in nil }, fallback: 0x09)
    XCTAssertEqual(code, 0x09)
  }

  // MARK: Permission panel placement (list and +/− stay free, arrow to the list)

  private let panel = NSSize(width: 440, height: 140)
  private let compact = NSSize(width: 380, height: 168)
  private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
  /// Visible frame of a 13-inch 1280×832 display under the menu bar.
  private let small = NSRect(x: 0, y: 0, width: 1280, height: 799)
  /// Visible frame of a large external display.
  private let large = NSRect(x: 0, y: 0, width: 2560, height: 1415)

  private func spot(
    _ window: NSRect?, screen: NSRect? = nil, sidebarOnLeft: Bool = true
  ) -> PermissionPanelPlacement.Spot {
    PermissionPanelPlacement.spot(
      regular: panel, compact: compact, window: window, screen: screen ?? self.screen,
      sidebarOnLeft: sidebarOnLeft
    )
  }

  /// The list and the +/− buttons: the window right of the sidebar, below
  /// the title bar and pane header (about 150 points).
  private func listArea(_ window: NSRect, sidebarOnLeft: Bool = true) -> NSRect {
    let sidebar = PermissionPanelPlacement.sidebarOverlap
    return NSRect(
      x: sidebarOnLeft ? window.minX + sidebar : window.minX,
      y: window.minY,
      width: window.width - sidebar,
      height: window.height - 150
    )
  }

  func testPanelGoesBelowTheWindowWhenThereIsRoom() {
    let window = NSRect(x: 400, y: 300, width: 700, height: 500)
    let s = spot(window)
    XCTAssertEqual(s.side, .below)
    XCTAssertEqual(s.frame.maxY, window.minY - PermissionPanelPlacement.gap)
    XCTAssertEqual(s.frame.midX, window.midX)
    XCTAssertEqual(PermissionPanelPlacement.arrow(for: s.side), "\u{2191}")
  }

  func testSystemDialogCountsOnlyWithAWindowOnScreen() {
    let shown: [String: Any] = [
      kCGWindowOwnerPID as String: 42,
      kCGWindowAlpha as String: 1.0,
      kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": 420.0, "Height": 180.0],
    ]
    XCTAssertTrue(SystemDialogPresence.hasWindowOnScreen(pid: 42, windows: [shown]))
    XCTAssertFalse(SystemDialogPresence.hasWindowOnScreen(pid: 42, windows: []))
    XCTAssertFalse(SystemDialogPresence.hasWindowOnScreen(pid: 7, windows: [shown]))
    var transparent = shown
    transparent[kCGWindowAlpha as String] = 0.0
    XCTAssertFalse(SystemDialogPresence.hasWindowOnScreen(pid: 42, windows: [transparent]))
  }

  func testBottomLiftMovesThePanelUpOverTheWindowEdge() {
    let window = NSRect(x: 400, y: 300, width: 700, height: 500)
    let s = PermissionPanelPlacement.spot(
      regular: panel, compact: compact, window: window, screen: screen, bottomLift: 64
    )
    XCTAssertEqual(s.side, .below)
    XCTAssertEqual(s.frame.maxY, window.minY - PermissionPanelPlacement.gap + 64)
  }

  func testPanelGoesBesideTheWindowAtTheBottomEdge() {
    let window = NSRect(x: 100, y: 0, width: 700, height: 600)
    let s = spot(window)
    XCTAssertEqual(s.side, .right)
    XCTAssertFalse(s.frame.intersects(window))
    XCTAssertEqual(s.frame.minY, window.minY)
    XCTAssertTrue(screen.contains(s.frame))
    XCTAssertEqual(PermissionPanelPlacement.arrow(for: s.side), "\u{2190}")
  }

  func testPanelTakesTheSideWithMoreRoom() {
    let window = NSRect(x: 900, y: 0, width: 500, height: 600)
    let s = spot(window)
    XCTAssertEqual(s.side, .left)
    XCTAssertLessThanOrEqual(s.frame.maxX, window.minX)
    XCTAssertEqual(PermissionPanelPlacement.arrow(for: s.side), "\u{2192}")
  }

  /// The maintainer's case (2026-11-02): a full-height window at the left of
  /// a 1280-point screen leaves about 427 points, too few for the full panel.
  func testSmallScreenPutsTheCompactPanelBesideTheWindow() {
    let window = NSRect(x: 0, y: 0, width: 845, height: 799)
    let s = spot(window, screen: small)
    XCTAssertEqual(s.side, .right)
    XCTAssertEqual(s.frame.size, compact)
    XCTAssertFalse(s.frame.intersects(window))
    XCTAssertTrue(small.contains(s.frame))
  }

  func testSmallScreenWithACentredWindowReachesOnlyOverTheSidebar() {
    let window = NSRect(x: 217, y: 0, width: 845, height: 799)
    let s = spot(window, screen: small)
    XCTAssertEqual(s.side, .left)
    XCTAssertFalse(s.frame.intersects(listArea(window)))
    XCTAssertTrue(small.contains(s.frame))
  }

  func testSidebarOnTheRightInRightToLeftLanguages() {
    let window = NSRect(x: 217, y: 0, width: 845, height: 799)
    let s = spot(window, screen: small, sidebarOnLeft: false)
    XCTAssertEqual(s.side, .right)
    XCTAssertFalse(s.frame.intersects(listArea(window, sidebarOnLeft: false)))
    XCTAssertTrue(small.contains(s.frame))
  }

  func testLargeScreenKeepsTheFullPanelBesideATallWindow() {
    let window = NSRect(x: 860, y: 0, width: 845, height: 1415)
    let s = spot(window, screen: large)
    XCTAssertEqual(s.frame.size, panel)
    XCTAssertFalse(s.frame.intersects(window))
  }

  func testPanelGoesAboveWithTheArrowDown() {
    let window = NSRect(x: 200, y: 0, width: 1100, height: 600)
    let s = spot(window)
    XCTAssertEqual(s.side, .above)
    XCTAssertEqual(s.frame.minY, window.maxY + PermissionPanelPlacement.gap)
    XCTAssertFalse(s.frame.intersects(window))
    XCTAssertEqual(PermissionPanelPlacement.arrow(for: s.side), "\u{2193}")
  }

  func testLastResortSitsOverTheTopWithTheArrowDown() {
    let window = screen
    let s = spot(window)
    XCTAssertEqual(s.side, .overTop)
    XCTAssertTrue(screen.contains(s.frame))
    XCTAssertEqual(s.frame.maxY, screen.maxY - PermissionPanelPlacement.gap)
    XCTAssertEqual(PermissionPanelPlacement.arrow(for: s.side), "\u{2193}")
  }

  func testPanelUsesTheSecondScreenOfTheWindow() {
    let second = NSRect(x: 1440, y: -200, width: 1920, height: 1055)
    let window = NSRect(x: 1600, y: 200, width: 700, height: 500)
    let chosen = PermissionPanelPlacement.screen(for: window, among: [screen, second])
    XCTAssertEqual(chosen, second)
    let s = spot(window, screen: second)
    XCTAssertTrue(second.contains(s.frame))
    XCTAssertFalse(s.frame.intersects(window))
  }

  func testPanelSitsAtTheScreenBottomWithoutAWindow() {
    let s = spot(nil)
    XCTAssertEqual(s.side, .noWindow)
    XCTAssertEqual(s.frame.midX, screen.midX)
    XCTAssertEqual(s.frame.minY, screen.minY + PermissionPanelPlacement.screenInset)
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }


  /// #223: the pasteboard read (`pb.types`, `pb.string`) blocked the main
  /// thread for 2 s+ when the copying app answered slowly. The read runs on a
  /// serial queue, the result lands on main, in copy order.
  func testPasteboardReadRunsOffMainAndDeliversInOrderOnMain() {
    let queue = DispatchQueue(label: "test.pasteboard-read")
    let done = expectation(description: "both deliveries")
    done.expectedFulfillmentCount = 2
    var delivered: [Int] = []
    for n in 1...2 {
      readOffMain(
        on: queue,
        read: { () -> Int in
          XCTAssertFalse(Thread.isMainThread)
          return n
        },
        deliver: { value in
          XCTAssertTrue(Thread.isMainThread)
          delivered.append(value)
          done.fulfill()
        })
    }
    wait(for: [done], timeout: 5)
    XCTAssertEqual(delivered, [1, 2])
  }
}
