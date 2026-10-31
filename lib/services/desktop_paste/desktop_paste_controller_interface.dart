/// Pure interface for the desktop paste controller.
///
/// All shared types, enums, and the abstract [DesktopPasteController] class
/// live here so that platform implementations can import only this file and
/// avoid a circular dependency with the factory/provider layer.
library;

/// Structured outcome of a native paste call. Mirrors the `{status, detail}`
/// map returned by the platform bridges so the UI can distinguish the
/// silent failure modes (no target / permission missing / post failed)
/// instead of seeing a bare `false`.
enum NativePasteStatus {
  success,
  noTarget,
  permissionMissing,

  /// Windows-only: `SetForegroundWindow` was refused because the target
  /// window belongs to a process running with higher privileges than
  /// WhisPaste (UIPI). Distinct from [postFailed] because the fix is
  /// specific — restart WhisPaste elevated — not "just retry".
  foregroundBlocked,
  postFailed,

  /// The captured target is no longer the frontmost app: the user switched
  /// away during transcription. Nothing is pasted into the wrong window.
  targetChanged,

  /// macOS 15.4+: the user denied WhisPaste access to the general pasteboard
  /// (NSPasteboard accessBehavior "always deny"). Nothing is read or
  /// overwritten, so the clipboard stays as the user left it.
  clipboardAccessDenied,
  unknown;

  static NativePasteStatus fromCode(String? code) => switch (code) {
    'success' => NativePasteStatus.success,
    'no_target' => NativePasteStatus.noTarget,
    'no_accessibility' ||
    'permission_missing' => NativePasteStatus.permissionMissing,
    'foreground_blocked' => NativePasteStatus.foregroundBlocked,
    'post_failed' || 'send_input_failed' => NativePasteStatus.postFailed,
    'target_changed' => NativePasteStatus.targetChanged,
    'clipboard_access_denied' => NativePasteStatus.clipboardAccessDenied,
    _ => NativePasteStatus.unknown,
  };
}

class NativePasteResult {
  const NativePasteResult({required this.status, this.detail});

  final NativePasteStatus status;
  final String? detail;

  bool get isSuccess => status == NativePasteStatus.success;

  factory NativePasteResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    }
    final code = map['status'] as String?;
    final detail = map['detail'] as String?;
    return NativePasteResult(
      status: NativePasteStatus.fromCode(code),
      detail: detail,
    );
  }

  factory NativePasteResult.fromLegacyBool(bool? value) => NativePasteResult(
    status: value == true
        ? NativePasteStatus.success
        : NativePasteStatus.postFailed,
  );
}

/// Outcome of [DesktopPasteController.diagnosticPaste].
///
/// Mirrors the `{status, detail?}`-map returned by the native bridges in a
/// closed, exhaustive set so the onboarding UI can switch on it without
/// resorting to stringly typed status codes.
///
///   - [TestPasteOutcomeSuccess]   — the demo keystroke landed.
///   - [TestPasteOutcomeNoFrontmost] — no frontmost window was reachable
///     when the paste fired; the user usually has to click the demo field
///     and retry.
///   - [TestPasteOutcomeFailure]   — the paste did not land. `reason` is a
///     PII-free status code (`"not_trusted"`, `"uipi_blocked"`,
///     `"exception"`, `"unknown"`, ...).
///   - [TestPasteOutcomeUnsupported] — the platform has no native bridge
///     (Linux, or controller running in a test env without a real channel).
sealed class TestPasteOutcome {
  const TestPasteOutcome();

  factory TestPasteOutcome.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const TestPasteOutcomeUnsupported();
    }
    final status = map['status'] as String?;
    return switch (status) {
      'success' => const TestPasteOutcomeSuccess(),
      'no_frontmost' => const TestPasteOutcomeNoFrontmost(),
      'unsupported' => const TestPasteOutcomeUnsupported(),
      'failure' => TestPasteOutcomeFailure(
        (map['detail'] as String?) ?? 'unknown',
      ),
      _ => const TestPasteOutcomeFailure('unknown_status'),
    };
  }
}

class TestPasteOutcomeSuccess extends TestPasteOutcome {
  const TestPasteOutcomeSuccess();
}

class TestPasteOutcomeNoFrontmost extends TestPasteOutcome {
  const TestPasteOutcomeNoFrontmost();
}

class TestPasteOutcomeFailure extends TestPasteOutcome {
  const TestPasteOutcomeFailure(this.reason);

  /// PII-free status code, e.g. `"not_trusted"`, `"uipi_blocked"`,
  /// `"exception"`, `"unknown"`.
  final String reason;
}

class TestPasteOutcomeUnsupported extends TestPasteOutcome {
  const TestPasteOutcomeUnsupported();
}

enum NativeCapabilityStatus { ready, permissionMissing, unsupported }

class NativeCapabilityResult {
  const NativeCapabilityResult({
    required this.status,
    this.canPrompt = false,
    this.detail,
  });

  final NativeCapabilityStatus status;
  final bool canPrompt;
  final String? detail;

  factory NativeCapabilityResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const NativeCapabilityResult(
        status: NativeCapabilityStatus.unsupported,
      );
    }
    final code = map['status'] as String?;
    return NativeCapabilityResult(
      status: switch (code) {
        'ready' => NativeCapabilityStatus.ready,
        'permission_missing' => NativeCapabilityStatus.permissionMissing,
        _ => NativeCapabilityStatus.unsupported,
      },
      canPrompt: map['canPrompt'] as bool? ?? false,
      detail: map['detail'] as String?,
    );
  }
}

/// What [ClipboardReceiptBridge.waitForClipboardRead] observed.
enum ClipboardReadReceipt {
  /// A reader pulled the transcript off the clipboard after the paste
  /// shortcut was posted — the target app has the text.
  read,

  /// Another writer replaced the clipboard — WhisPaste no longer owns it, so
  /// restoring would clobber someone else's content.
  ownershipLost,

  /// No usable signal (superseded, no receipt armed, channel unavailable) —
  /// the caller keeps waiting for its fixed fallback buffer.
  unknown;

  static ClipboardReadReceipt fromCode(String? code) => switch (code) {
    'read' => ClipboardReadReceipt.read,
    'lost' => ClipboardReadReceipt.ownershipLost,
    _ => ClipboardReadReceipt.unknown,
  };
}

/// Whether the OS currently routes keystrokes into a secure input field
/// (macOS `IsSecureEventInputEnabled`, e.g. a password field). Only macOS
/// has such a system signal; elsewhere the answer is [unsupported].
enum SecureInputState {
  active,
  inactive,
  unsupported;

  static SecureInputState fromCode(String? code) => switch (code) {
    'active' => SecureInputState.active,
    'inactive' => SecureInputState.inactive,
    _ => SecureInputState.unsupported,
  };
}

/// The app that holds macOS secure input right now (F35-8). All fields are
/// optional: a holder without a name or bundle id gets the generic notice.
class SecureInputHolder {
  const SecureInputHolder({this.name, this.bundleId, this.pid});

  /// The localized app name, e.g. "Terminal".
  final String? name;

  /// The bundle id, e.g. "com.apple.Terminal", for app-specific tips.
  final String? bundleId;

  /// The process id, for the secure input log line.
  final int? pid;
}

/// Implemented by controllers that can ask the OS about secure input (W-E1).
abstract interface class SecureInputProbe {
  Future<SecureInputState> secureInputState();

  /// The app holding secure input, or null when none is known. Only read
  /// after a paste was skipped, never on the paste path (F35-8).
  Future<SecureInputHolder?> secureInputHolder();
}

/// Outcome of [ClipboardReceiptBridge.restoreClipboardTextIfOwner].
enum ClipboardRestoreOutcome {
  restored,

  /// Skipped: another process changed the clipboard in the meantime.
  notOwner,
  failed;

  static ClipboardRestoreOutcome fromCode(String? code) => switch (code) {
    'restored' => ClipboardRestoreOutcome.restored,
    'not_owner' => ClipboardRestoreOutcome.notOwner,
    _ => ClipboardRestoreOutcome.failed,
  };
}

/// Receipt-based clipboard restore on all three desktop platforms.
///
/// Instead of "write transcript → paste → wait a fixed buffer → restore",
/// the transcript is put on the clipboard *lazily* (macOS
/// `NSPasteboardItemDataProvider`, Windows delayed rendering via
/// `SetClipboardData(fmt, NULL)` + `WM_RENDERFORMAT`, Linux
/// `gtk_clipboard_set_with_data`, served per X selection request), so the
/// native host learns the moment the target app actually reads it. The
/// restore then happens right after that read, and only while WhisPaste
/// still owns the clipboard (macOS `changeCount`, Windows
/// `WM_DESTROYCLIPBOARD`/`GetClipboardOwner`, Linux the selection clear).
abstract interface class ClipboardReceiptBridge {
  /// Writes [text] as a lazily rendered, history-excluded clipboard item
  /// (macOS: marked `org.nspasteboard.TransientType` + `ConcealedType`).
  /// Returns `false` when the platform can't arm a receipt — the caller then
  /// uses the classic write + fixed-delay restore.
  Future<bool> writeClipboardTextWithReceipt(String text);

  /// Completes once the receipt written by [writeClipboardTextWithReceipt]
  /// was read after the paste shortcut went out, or ownership was lost.
  /// Never times out on its own — the caller bounds it.
  Future<ClipboardReadReceipt> waitForClipboardRead();

  /// Writes [text] back (history-excluded) only if WhisPaste is still the
  /// clipboard owner since the receipt write.
  Future<ClipboardRestoreOutcome> restoreClipboardTextIfOwner(String text);
}

/// Platform-agnostic interface for desktop clipboard pasting.
///
/// The controller captures the current paste target before recording starts and
/// later restores focus so a simulated paste lands back in the intended app.
abstract class DesktopPasteController {
  /// Captures the current desktop window/application as the paste target.
  ///
  /// Returns `true` when a suitable external target window was captured.
  Future<bool> capturePasteTarget();

  /// Returns the bundle ID (macOS) or process name (Windows) of the captured
  /// paste target, or `null` if no target was captured.
  Future<String?> getTargetBundleId();

  /// Restores the captured target and sends the paste shortcut.
  ///
  /// Returns a [NativePasteResult] so the caller can distinguish silent
  /// failure modes (no target, permission missing, OS post failed).
  Future<NativePasteResult> pasteClipboard({required Duration delay});

  /// Restores the captured target and sends the copy shortcut
  /// (Cmd/Ctrl+C), so the target app copies its current selection to the
  /// clipboard ("edit selection by voice"). The caller owns the clipboard
  /// snapshot/restore around this call and detects "nothing selected" by
  /// the clipboard staying unchanged — the shortcut itself reports success
  /// either way.
  ///
  /// Same [NativePasteResult] vocabulary as [pasteClipboard].
  Future<NativePasteResult> copySelection({required Duration delay});

  /// Restores the captured target and types [text].
  ///
  /// Only macOS types directly via synthetic Unicode keystrokes, without the
  /// clipboard. Windows and Linux route through the same clipboard + Ctrl+V
  /// path as [pasteClipboard] (on Windows, Unicode SendInput corrupts text in
  /// Notepad's TSF control) and back up and restore the clipboard around it,
  /// so they are no independent second way in: after a failed paste status
  /// they could insert the text twice. The typing retry after a failed paste
  /// therefore runs on macOS only (P1.2).
  ///
  /// Returns the same [NativePasteResult] shape as [pasteClipboard] so
  /// callers can distinguish the same silent failure modes.
  Future<NativePasteResult> typeText(String text, {required Duration delay});

  /// Writes [text] to the OS clipboard using the platform's clipboard-
  /// history / cloud-clipboard opt-out formats where available (Windows'
  /// `ExcludeClipboardContentFromMonitorProcessing` etc.), so a transient
  /// write never surfaces as a new entry in e.g. Windows' Win+V history.
  /// On macOS the native write marks the item `org.nspasteboard.TransientType`
  /// and `ConcealedType` (BIZ-61). On Linux it sets the
  /// `x-kde-passwordManagerHint` target, which only Klipper honours; GPaste
  /// and other managers still record the text.
  ///
  /// Returns `false` on any channel failure — callers then fall back to an
  /// ordinary clipboard write that the OS may record in its own history. The
  /// fallback is a warning on Windows and macOS, info on Linux (6c+a).
  Future<bool> writeClipboardTextExcludingHistory(String text);

  /// Probes whether the OS would allow Auto-Paste right now — without
  /// actually pasting. When [promptIfMissing] is `true`, triggers the
  /// OS-native permission dialog if applicable (macOS Accessibility).
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  });

  /// Diagnostic paste — exercises the production Auto-Paste pipeline with a
  /// caller-supplied `demoText` so the onboarding flow can prove Auto-Paste
  /// works *before* the user finishes onboarding.
  ///
  /// The native side is expected to: (1) backup the current clipboard,
  /// (2) write [demoText] into it, (3) synthesise the platform's paste
  /// shortcut, (4) wait briefly for the keystroke to be delivered, (5)
  /// restore the original clipboard — even on the failure path. Returns a
  /// [TestPasteOutcome] mirroring the native `{status, detail?}` response;
  /// exceptions thrown by the channel call map to
  /// [TestPasteOutcomeFailure] with `reason: "exception"`.
  Future<TestPasteOutcome> diagnosticPaste(String demoText);

  /// Wipes stale TCC entries for the permission services Auto-Paste uses
  /// (macOS Accessibility + AppleEvents). The next paste attempt will
  /// trigger fresh OS prompts bound to the current binary's signature —
  /// the documented workaround for ad-hoc-signed apps whose UI toggle
  /// shows "ON" but `AXIsProcessTrusted()` returns `false`.
  ///
  /// No-op on platforms without TCC (Windows). Returns the per-service
  /// counts of cleared entries (negative = call failed).
  Future<TccRepairResult> repairTccEntries();

  /// Releases any native resources held by the controller.
  Future<void> dispose();
}

class TccRepairResult {
  const TccRepairResult({
    required this.accessibilityCleared,
    required this.appleEventsCleared,
    this.error,
  });

  /// Count of Accessibility entries cleared. -1 = call failed, 0 = nothing
  /// to clear (clean state), 1+ = stale entries removed.
  final int accessibilityCleared;
  final int appleEventsCleared;
  final String? error;

  bool get isSupported => error == null;

  factory TccRepairResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const TccRepairResult(
        accessibilityCleared: -1,
        appleEventsCleared: -1,
        error: 'no_response',
      );
    }
    return TccRepairResult(
      accessibilityCleared: (map['ax'] as int?) ?? -1,
      appleEventsCleared: (map['ae'] as int?) ?? -1,
      error: map['error'] as String?,
    );
  }

  factory TccRepairResult.unsupported() => const TccRepairResult(
    accessibilityCleared: 0,
    appleEventsCleared: 0,
    error: 'unsupported_platform',
  );
}

/// What [ClipboardSnapshotBridge.snapshotClipboard] saved.
enum ClipboardSnapshotStatus {
  /// Every readable format is held natively, ready for the restore.
  saved,

  /// The clipboard holds nothing: there is nothing to restore.
  empty,

  /// macOS pasteboard privacy: WhisPaste may not read the clipboard.
  denied,

  /// No native snapshot (unsupported, too large, too slow, channel error):
  /// the caller falls back to the plain-text snapshot.
  failed;

  static ClipboardSnapshotStatus fromCode(String? code) => switch (code) {
    'saved' => ClipboardSnapshotStatus.saved,
    'empty' => ClipboardSnapshotStatus.empty,
    'denied' => ClipboardSnapshotStatus.denied,
    _ => ClipboardSnapshotStatus.failed,
  };
}

/// Result of [ClipboardSnapshotBridge.snapshotClipboard]. [text] is the
/// plain-text form of the saved content, when it has one, so the restore can
/// be marked as WhisPaste's own write; [formats] and [bytes] are for the log.
class ClipboardSnapshot {
  const ClipboardSnapshot(
    this.status, {
    this.text,
    this.formats = 0,
    this.bytes = 0,
  });

  final ClipboardSnapshotStatus status;
  final String? text;
  final int formats;
  final int bytes;

  factory ClipboardSnapshot.fromMap(Object? raw) {
    if (raw is! Map) {
      return const ClipboardSnapshot(ClipboardSnapshotStatus.failed);
    }
    return ClipboardSnapshot(
      ClipboardSnapshotStatus.fromCode(raw['status'] as String?),
      text: raw['text'] as String?,
      formats: (raw['formats'] as num?)?.toInt() ?? 0,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Full clipboard backup around a paste (P1.1): every format the user had
/// copied (image, files, rich text, HTML, ...) comes back, not only plain
/// text. The native host keeps the snapshot (macOS all pasteboard item types,
/// Windows every memory-backed clipboard format, Linux every selection
/// target), so the data never crosses the channel.
///
/// The restore runs under the same owner check as
/// [ClipboardReceiptBridge.restoreClipboardTextIfOwner] and is
/// history-excluded the same way.
abstract interface class ClipboardSnapshotBridge {
  /// Saves the current clipboard natively, replacing an earlier snapshot.
  Future<ClipboardSnapshot> snapshotClipboard();

  /// Writes the saved snapshot back only while WhisPaste still owns the
  /// clipboard since the receipt write. [ClipboardRestoreOutcome.failed]
  /// when no snapshot is held.
  Future<ClipboardRestoreOutcome> restoreClipboardSnapshotIfOwner();

  /// Drops the saved snapshot without restoring it.
  Future<void> discardClipboardSnapshot();
}
