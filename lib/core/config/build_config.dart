/// Build-time distribution flags.
///
/// WhisPaste ships two macOS variants from a single codebase:
///
/// - **Developer-ID** (direct download / Homebrew): not sandboxed. Posts
///   synthetic ⌘V / Unicode-type keystrokes via CGEvent, with an AppleScript
///   `System Events` fallback and a `tccutil`-based TCC self-heal tool.
/// - **Mac App Store** (sandboxed): posts the SAME synthetic ⌘V / Unicode-type
///   keystrokes via CGEvent — the sandbox-compatible `PostEvent` TCC service
///   (`CGRequestPostEventAccess`/`CGEventKeyboardSetUnicodeString`) allows
///   this from inside App Sandbox (confirmed by Apple DTS and empirically
///   verified for WhisPaste — see the Phase 0 proof in the direct-typing
///   plan). What's excluded from the MAS binary is narrower: the
///   AppleScript-`keystroke` fallback and the `tccutil`/`Process`-based
///   repair tool, neither of which the sandbox permits, and both of which
///   Apple's static binary scan flags (Guideline 2.5.2) — see the
///   `MAS_BUILD` Swift active-compilation-condition in
///   `macos/Runner/DesktopPasteHost.swift`.
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

/// Whether simulated-keystroke auto-paste/type (⌘V / Ctrl+V / Unicode typing)
/// is available.
///
/// `true` on every current build, MAS included — see the class doc above.
/// Kept as an explicit constant (rather than inlined `true`) because it is
/// the deliberate App Review Guideline 2.4.5 kill switch: if a MAS
/// submission is ever rejected specifically over the keystroke-injection
/// feature, flipping this back to `!kIsMasBuild` (or `false`) cleanly
/// downgrades every build to the clipboard-only behaviour that shipped
/// before this feature existed — see [resolveAfterTranscriptionAction] in
/// `lib/services/paste/paste_policy.dart`.
const bool kAutoPasteSupported = true;

/// Debug-only: when `true`, the dictation WAV is kept on disk after
/// transcription (instead of being deleted immediately, see
/// `RecordingOrchestrator.stopRecording`'s cleanup step) and linked to its
/// history entry as an [EntryAttachment].
///
/// This exists to diagnose intermittent "transcription dropped a sentence"
/// reports: without a retained copy of the exact audio Whisper received,
/// a one-off drop cannot be replayed through the offline test harness to
/// tell capture-side (mic/noise-suppression) issues apart from
/// inference-side (model/prompt/decoding) ones. Defaults to `false` so
/// normal builds never accumulate extra audio on disk. Enable for a
/// diagnosis session with:
/// ```sh
/// flutter build macos --release --dart-define=WHISPASTE_RETAIN_DEBUG_AUDIO=true
/// ```
const bool kRetainDebugAudio = bool.fromEnvironment(
  'WHISPASTE_RETAIN_DEBUG_AUDIO',
  defaultValue: false,
);
