#!/usr/bin/env swift
//
// Isolated CGEvent-typing drop-rate loop — a diagnosis tool, NOT part of the
// shipped app or Xcode target.
//
// Context: WhisPaste's default macOS insertion path (Sandbox and Dev-ID
// alike) is synthetic Unicode typing via `postUnicodeString`
// (macos/Runner/DesktopPasteHost.swift:585-619), chunked at 20 UTF-16 units
// with a 1 ms inter-chunk gap and a 20 ms flush after the last chunk. That
// function's own doc comment already documents empirically observing the
// trailing character dropped "noticeably often" against real dictations —
// this script measures the ACTUAL drop rate in isolation, against a
// controlled receiving `NSTextView` in this script's own window, with no
// Flutter, no method channel, and no rest of the app in the way. That
// isolates the CGEvent pacing behaviour as a variable from every other
// moving part in the paste pipeline (see the local diagnosis plan).
//
// IMPORTANT: `postUnicodeString` below MUST stay byte-identical to
// `DesktopPasteHost.swift`'s function of the same name — diff them before
// trusting a result from this script. It is duplicated here (not imported)
// because the macOS app is an Xcode project target, not a package a bare
// `swift` script can import from.
//
// Requires CGEventPost / Accessibility trust for the process running this
// script (typically inherited from Terminal's own Accessibility grant) —
// preflight-checked below via `CGPreflightPostEventAccess()`; the script
// exits early with a clear message rather than silently measuring "100%
// drop" if that trust is missing.
//
// Usage:
//   swift tool/paste_drop_loop.swift [--gap-us=1000] [--flush-us=20000] \
//       [--chunk=20] [--iterations=30]
//
// `--gap-us`/`--flush-us`/`--chunk` let you A/B a candidate pacing fix
// (e.g. a larger inter-chunk gap) against the production defaults without
// touching `DesktopPasteHost.swift` first — run once with defaults for the
// baseline, once with candidate values, and compare drop rates.

import AppKit
import CoreGraphics

// ---------------------------------------------------------------------------
// CLI options
// ---------------------------------------------------------------------------

func intOption(_ name: String, default def: Int) -> Int {
  let prefix = "--\(name)="
  for arg in CommandLine.arguments where arg.hasPrefix(prefix) {
    if let value = Int(arg.dropFirst(prefix.count)) { return value }
  }
  return def
}

let interEventDelayUs = useconds_t(intOption("gap-us", default: 1_000))
let finalFlushDelayUs = useconds_t(intOption("flush-us", default: 20_000))
let chunkSize = intOption("chunk", default: 20)
let iterations = intOption("iterations", default: 30)

// ---------------------------------------------------------------------------
// Verbatim copy of DesktopPasteHost.swift:585-619's postUnicodeString, with
// its constants parameterized above instead of hardcoded, so this script
// can both reproduce the exact production behaviour (defaults match) and
// A/B a candidate fix.
// ---------------------------------------------------------------------------

func postUnicodeString(_ text: String) -> Bool {
  let utf16 = Array(text.utf16)
  guard !utf16.isEmpty else { return true }

  var index = 0
  while index < utf16.count {
    var end = min(index + chunkSize, utf16.count)
    if end < utf16.count, (0xD800...0xDBFF).contains(utf16[end - 1]) {
      end += 1
    }
    let chunk = Array(utf16[index..<end])
    let isLastChunk = end >= utf16.count

    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
      return false
    }
    chunk.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else { return }
      keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
      keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    }
    keyDown.post(tap: .cghidEventTap)
    usleep(interEventDelayUs)
    keyUp.post(tap: .cghidEventTap)
    usleep(isLastChunk ? finalFlushDelayUs : interEventDelayUs)

    index = end
  }
  return true
}

// ---------------------------------------------------------------------------
// Known long multi-sentence test string (mirrors a real dictation's length
// and punctuation density — the failure mode the user actually reported).
// ---------------------------------------------------------------------------

let testString = """
Dies ist ein laengerer Testsatz fuer die Einfuege-Diagnose. Er enthaelt mehrere \
Saetze und Satzzeichen, genau wie eine echte Diktion. Manche Woerter sind kurz, \
manche etwas laenger, damit die Chunk-Grenzen nicht zufaellig immer an Wortgrenzen \
landen. Am Ende steht noch ein letzter Satz, der besonders wichtig ist, weil genau \
hier das dokumentierte Problem mit dem letzten Zeichen typischerweise auftritt.
"""

// ---------------------------------------------------------------------------
// Minimal AppKit harness: one window, one focused NSTextView as the
// controlled receiving target.
// ---------------------------------------------------------------------------

struct IterationResult {
  let matched: Bool
  let expected: String
  let actual: String
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  var textView: NSTextView!
  var results: [IterationResult] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard CGPreflightPostEventAccess() else {
      print("BLOCKED: CGPreflightPostEventAccess() is false for this process.")
      print("Grant Accessibility/PostEvent access to whatever runs `swift`")
      print("(usually via Terminal's own grant) in System Settings > Privacy")
      print("& Security, then re-run.")
      NSApp.terminate(nil)
      return
    }

    window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    window.contentView = textView
    window.title = "paste_drop_loop target"
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    print(
      "gap-us=\(interEventDelayUs) flush-us=\(finalFlushDelayUs) "
        + "chunk=\(chunkSize) iterations=\(iterations)"
    )
    print("testString: \(testString.utf16.count) UTF-16 units")

    // Give the window server a moment to actually make our window key
    // before the first post — otherwise the very first iteration would
    // measure "no receiving app focused yet", not the pacing bug.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.runIteration(0)
    }
  }

  func runIteration(_ i: Int) {
    if i >= iterations {
      report()
      NSApp.terminate(nil)
      return
    }
    textView.string = ""
    window.makeFirstResponder(textView)

    // Run on a background queue — mirrors production: DesktopPasteHost's
    // own doc comment notes `postUnicodeString` "always runs on a
    // background-queue dispatch", specifically so `usleep` doesn't block
    // the caller's run loop. Here that matters doubly: it also keeps THIS
    // script's own NSApp run loop free to actually receive and dispatch
    // the keystrokes we're posting into our own window.
    DispatchQueue.global(qos: .userInitiated).async {
      _ = postUnicodeString(testString)
      // Settle window: let the HID pipeline finish delivering into our
      // NSTextView before reading it back.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        let actual = self.textView.string
        self.results.append(
          IterationResult(matched: actual == testString, expected: testString, actual: actual)
        )
        self.runIteration(i + 1)
      }
    }
  }

  func report() {
    let drops = results.filter { !$0.matched }
    let rate = results.isEmpty ? 0.0 : Double(drops.count) / Double(results.count) * 100
    print("")
    print("=== paste_drop_loop result ===")
    print("drops: \(drops.count)/\(results.count) (\(String(format: "%.1f", rate))%)")
    for (idx, r) in results.enumerated() where !r.matched {
      let expectedLen = r.expected.utf16.count
      let actualLen = r.actual.utf16.count
      print("  [\(idx)] expectedLen=\(expectedLen) actualLen=\(actualLen) diff=\(expectedLen - actualLen)")
      if actualLen < expectedLen, r.expected.hasPrefix(r.actual) {
        let dropped = String(r.expected.dropFirst(r.actual.count))
        print("      dropped suffix: \"\(dropped)\"")
      } else {
        print("      actual: \"\(r.actual)\"")
      }
    }
  }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
