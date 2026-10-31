import Cocoa
import FlutterMacOS
import XCTest
@testable import Runner

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

  func testFallsBackToAnsiPositionWhenNoKeyTypesTheLetter() {
    let code = keyCode(forCharacter: "v", layoutCharacter: { _ in nil }, fallback: 0x09)
    XCTAssertEqual(code, 0x09)
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
