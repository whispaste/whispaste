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

  /// Paste was attempted but the native bridge reported failure.
  failed,
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
}
