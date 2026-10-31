/// Deep abstraction over "write text to the active window".
///
/// [RecordingOrchestrator] calls [prime] before recording starts (to capture
/// the target window) and [paste] after transcription. All timing, clipboard
/// management, and blocklist logic are hidden behind this interface.
library;

import 'input_idle.dart';

export 'desktop_paster.dart';
export 'input_idle.dart';

/// Implemented by a paster that can undo its last insert (DEV-165). Only the
/// native desktop paster does; test doubles do not.
abstract interface class UndoKeystrokeSender {
  /// Serial of the last insert that reached the target through the native
  /// clipboard paste. Null once a recording started, another insert ran or
  /// the last insert was typed (the Unicode fallback), so no keystroke undo
  /// may rely on an earlier insert.
  int? get cleanPasteSerial;

  /// Native input-idle snapshot (keyDown, left/right mouseDown, our own
  /// synthetic keyDown). Null when unknown: [userInputSince] then counts the
  /// input as typed, so the caller takes the safe path.
  Future<InputIdleSnapshot?> inputIdleSnapshot();

  /// Cmd+Z / Ctrl+Z in the frontmost app. False where the platform has no
  /// undo keystroke.
  Future<bool> sendUndoShortcut();

  /// Puts [text] on the clipboard through the transient, history-excluded
  /// write (the same path as the paste source). False on failure.
  Future<bool> copyOriginalToClipboard(String text);
}

/// The outcome of a paste operation.
enum PasteOutcome {
  /// The target app read the transcript (receipt proof on macOS/Windows).
  success,

  /// The target app is on the auto-paste blocklist.
  blocked,

  /// Platform paste bridge not available (unsupported OS / test env).
  platformUnavailable,

  /// No target window was captured (e.g. WhisPaste was frontmost when
  /// recording started, or the previous target window was closed before
  /// transcription finished). The user needs to focus the destination app
  /// before triggering recording.
  noTarget,

  /// The OS denied event injection (macOS Accessibility, Windows UIPI).
  /// Without this permission, the simulated paste shortcut is silently
  /// dropped. The user must grant the permission in system settings.
  permissionMissing,

  /// Windows-only: the target window belongs to a process running with
  /// higher privileges (elevated/administrator) than WhisPaste, so the OS
  /// refused `SetForegroundWindow`/`SendInput` (UIPI — User Interface
  /// Privilege Isolation). There is no permission to grant from inside the
  /// app; WhisPaste itself needs to run elevated to paste into that window.
  elevationBlocked,

  /// The captured target app is no longer frontmost (the user switched apps
  /// during transcription). Nothing is typed or pasted; the text stays in the
  /// clipboard.
  targetChanged,

  /// The paste shortcut was sent but no proof arrived that the text reached
  /// the field (no clipboard read receipt). Never reported as a success.
  /// The text stays in the clipboard.
  unconfirmed,

  /// Like [unconfirmed], but no read receipt could be armed: the paster has
  /// no receipt bridge, or the native receipt write was refused. The shortcut
  /// went out, nothing proves arrival, and the transcript stays on the
  /// clipboard (PAR-033). Unlike [unconfirmed] it raises no warning toast: the
  /// missing receipt says nothing about this paste.
  unconfirmedNoBridge,

  /// The platform has a receipt bridge (macOS/Windows), but the native receipt
  /// write was refused or failed, so the target's read cannot be watched. The
  /// shortcut went out and the transcript stays on the clipboard, unrestored
  /// (PAR-033). Unlike [unconfirmedNoBridge] this is a real, user-visible gap:
  /// the user gets a calm info notice (see `pasteResultNotice`), not a warning.
  unconfirmedReceiptRefused,

  /// macOS secure input is on (another app holds it, or a password field
  /// has focus), so no paste was attempted. The transcript stays on the
  /// clipboard. Not a warning from the paster: the reporter names the app
  /// that holds secure input (F35-8).
  secureInput,

  /// Paste was attempted but the native bridge reported failure for a
  /// reason that doesn't map to a more specific outcome above.
  failed,
}

/// Why [PasteCapability] reports the platform isn't ready to paste.
enum PasteCapabilityStatus {
  /// Everything looks good — a paste should succeed.
  ready,

  /// The required OS permission (Accessibility on macOS, none on Windows)
  /// has not been granted. [PasteCapability.canPrompt] indicates whether
  /// the OS will surface its own permission prompt on the next call to
  /// [Paster.checkCapability] with `promptIfMissing: true`.
  permissionMissing,

  /// Platform bridge isn't available (unsupported OS / test env).
  unsupported,
}

/// Result of a capability probe — answers "would Auto-Paste work right now?"
/// without actually pasting anything.
class PasteCapability {
  const PasteCapability({
    required this.status,
    this.canPrompt = false,
    this.detail,
  });

  final PasteCapabilityStatus status;

  /// Only meaningful when [status] is [PasteCapabilityStatus.permissionMissing]:
  /// `true` means the next prompted check will trigger the OS-native
  /// permission dialog (macOS only — once per process per session).
  final bool canPrompt;

  /// Free-form detail string from the native side for debug logging.
  final String? detail;
}

/// Configuration for a paste operation, derived from [AppSettings].
class PasteOptions {
  const PasteOptions({
    required this.autoPasteDelayMs,
    required this.blocklist,
    this.copyBlockedToClipboard = true,
    this.restoreClipboardAfterPaste = true,
    this.restoreClipboardWithoutReceipt = false,
  });

  /// User-configured delay before pasting (milliseconds).
  final int autoPasteDelayMs;

  /// Comma-separated list of app bundle IDs / process names to skip.
  final String blocklist;

  /// Whether a blocked paste still writes the transcript to the clipboard.
  /// `false` writes nothing on any path; the text stays in the history only.
  final bool copyBlockedToClipboard;

  /// Whether a paste that landed (or cannot be confirmed) puts the user's
  /// previous clipboard content back. `false` keeps the dictation on the
  /// clipboard. A receipt timeout keeps the transcript regardless.
  final bool restoreClipboardAfterPaste;

  /// Legacy switch (W-E1): when a paste was sent but its read receipt timed
  /// out, restore the previous clipboard after the fixed wait anyway, as the
  /// previous release did. Only with [restoreClipboardAfterPaste], and only
  /// while WhisPaste still owns the clipboard. Off, the transcript stays.
  final bool restoreClipboardWithoutReceipt;
}

/// Whether [text] must never fall back to synthetic Unicode-keystroke typing
/// ([Paster.typeText]) if a real OS paste ([Paster.paste]) fails to land.
///
/// CGEvent Unicode-typing (the native `postUnicodeString`) delivers each
/// character as a genuine key-down/key-up event pair. For a line feed or
/// carriage return, the receiving app sees the same event a physical Return
/// key press would produce — many chat UIs (ChatGPT, Slack, ...) bind
/// exactly that event to "submit", so typing multi-line text can trigger an
/// unwanted send. A real OS paste inserts the identical characters as
/// clipboard content instead, without ever dispatching a key event, so a
/// receiving app only ever sees a soft line break — which is why [paste] is
/// always the default and this predicate only gates the typing *fallback*.
bool requiresRealPaste(String text) =>
    text.contains('\n') || text.contains('\r');

/// Manages the full "write text to active window" lifecycle.
abstract class Paster {
  /// Captures the paste target window before recording starts.
  ///
  /// Must be called before [paste]. On platforms without a native bridge,
  /// this is a no-op.
  Future<void> prime();

  /// Writes [text] to the previously captured window.
  ///
  /// Handles clipboard save/restore, delay timing, and blocklist check.
  Future<PasteOutcome> paste(String text, PasteOptions options);

  /// Types [text] directly into the previously captured window via
  /// synthetic Unicode keystrokes — no clipboard involved at all.
  ///
  /// Handles delay timing and the same blocklist check as [paste].
  Future<PasteOutcome> typeText(String text, PasteOptions options);

  /// Probes whether Auto-Paste would work right now — without pasting.
  ///
  /// When [promptIfMissing] is `true`, surfaces the OS's native permission
  /// prompt if the required permission is not yet granted (macOS only).
  Future<PasteCapability> checkCapability({bool promptIfMissing = false});

  /// Returns the bundle ID (macOS) / process identifier (Windows) of the
  /// previously captured paste target, or `null` when no target was
  /// captured or the lookup is unsupported on this platform (Linux, test
  /// env). Same lookup [paste]/[typeText] already use for the blocklist
  /// check (ticket 12) — surfaced here so callers can persist it without
  /// duplicating the platform channel call.
  Future<String?> getTargetBundleId();
}
