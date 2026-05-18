/// Deep abstraction over "write text to the active window".
///
/// [RecordingOrchestrator] calls [prime] before recording starts (to capture
/// the target window) and [paste] after transcription. All timing, clipboard
/// management, and blocklist logic are hidden behind this interface.
library;

export 'desktop_paster.dart';

/// The outcome of a paste operation.
enum PasteOutcome {
  /// Text was successfully pasted into the target window.
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

  bool get isReady => status == PasteCapabilityStatus.ready;
}

/// Configuration for a paste operation, derived from [AppSettings].
class PasteOptions {
  const PasteOptions({required this.autoPasteDelayMs, required this.blocklist});

  /// User-configured delay before pasting (milliseconds).
  final int autoPasteDelayMs;

  /// Comma-separated list of app bundle IDs / process names to skip.
  final String blocklist;
}

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

  /// Probes whether Auto-Paste would work right now — without pasting.
  ///
  /// When [promptIfMissing] is `true`, surfaces the OS's native permission
  /// prompt if the required permission is not yet granted (macOS only).
  Future<PasteCapability> checkCapability({bool promptIfMissing = false});
}
