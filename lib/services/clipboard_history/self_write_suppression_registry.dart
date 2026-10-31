import 'clipboard_fingerprint.dart';

/// Tracks content fingerprints that WhisPaste's own writes are expected to
/// produce, so a clipboard history reader (native monitor, or the Linux
/// snapshot-on-open path) can skip them.
///
/// Must be marked *before* the actual `Clipboard.setData` call (see
/// PRD.md "Self-Write-Suppression"): marking after leaves a window where a
/// poller/snapshot can observe the change first and capture WhisPaste's own
/// transcript into clipboard history.
class SelfWriteSuppressionRegistry {
  SelfWriteSuppressionRegistry({
    DateTime Function()? now,
    this.expiry = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration expiry;

  final Map<ClipboardFingerprint, DateTime> _pendingSkips = {};

  void markSelfWrite(ClipboardFingerprint fingerprint) {
    _pendingSkips[fingerprint] = _now().add(expiry);
  }

  /// Consumes the mark for [fingerprint] if present. A failed/aborted write
  /// that never changes the clipboard leaves the mark to expire on its own,
  /// so it can't eat the user's next genuine copy indefinitely.
  bool shouldSuppress(ClipboardFingerprint fingerprint) {
    final expiresAt = _pendingSkips.remove(fingerprint);
    if (expiresAt == null) return false;
    return _now().isBefore(expiresAt);
  }
}
