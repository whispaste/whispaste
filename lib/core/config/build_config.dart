/// Build-time distribution flags.
///
/// WhisPaste ships two macOS variants from a single codebase:
///
/// - **Developer-ID** (direct download / Homebrew): full auto-paste — the app
///   synthesizes ⌘V into the frontmost app after transcription.
/// - **Mac App Store** (sandboxed): auto-paste is compiled out. Synthesizing
///   keystrokes into other apps violates App Review Guideline 2.4.5 and is
///   blocked by the App Sandbox. Apple additionally scans the binary for the
///   relevant symbols, so the native CGEvent/AppleScript paste code is excluded
///   from the binary via the `MAS_BUILD` Swift active-compilation-condition
///   (see `macos/Runner/DesktopPasteHost.swift`).
///
/// The Mac App Store build is produced with:
/// ```sh
/// flutter build macos --release --dart-define=WHISPASTE_MAS=true
/// ```
/// On Windows and Linux this flag is always `false` (Microsoft Store and
/// direct distribution both allow keystroke injection), so behaviour there is
/// unchanged.
library;

/// `true` when this build targets the sandboxed Mac App Store variant.
const bool kIsMasBuild = bool.fromEnvironment(
  'WHISPASTE_MAS',
  defaultValue: false,
);

/// Whether simulated-keystroke auto-paste (⌘V / Ctrl+V) is available.
///
/// Always `false` in Mac App Store builds; `true` everywhere else.
const bool kAutoPasteSupported = !kIsMasBuild;
