import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'clipboard_fingerprint.dart';

final _log = AppLogger('SelfWriteSignal');

/// Signals to the native clipboard-history monitor that WhisPaste itself is
/// about to write [fingerprint] to the clipboard, so a subsequent poll that
/// observes matching content should be skipped in clipboard history.
///
/// Must be called *before* the actual write (see PRD.md
/// "Self-Write-Suppression"): marking after leaves a race window where the
/// native poller can observe the clipboard change first and capture
/// WhisPaste's own output as a new history entry.
abstract class SelfWriteSignal {
  Future<void> markSelfWrite(ClipboardFingerprint fingerprint);
}

const _channel = MethodChannel('com.whispaste.clipboard_history');

/// Talks to the native clipboard-history monitor (added per-platform in
/// issues 04-06). Silently no-ops where no monitor is installed -- on a
/// platform/build that doesn't have the clipboard-history native side yet,
/// or before it ships. Signaling is advisory and must never block the
/// actual clipboard write.
class MethodChannelSelfWriteSignal implements SelfWriteSignal {
  const MethodChannelSelfWriteSignal();

  @override
  Future<void> markSelfWrite(ClipboardFingerprint fingerprint) async {
    // A hard timeout, not just try/catch: this signal sits directly in the
    // dictation hot path (Hotkey→Text is the product's core speed metric).
    // A native monitor that never installed a handler at all -- true in
    // every build before issues 04-06 ship, and reproducibly in this
    // package's own widget tests -- can leave `invokeMethod` unresolved
    // indefinitely instead of throwing, so a plain try/catch is not enough.
    // Callers never await this (see AppClipboard.setText), so logging here
    // never adds latency to the actual clipboard write.
    try {
      await _channel
          .invokeMethod<void>('markSelfWrite', {
            'length': fingerprint.length,
            'hash': fingerprint.hash,
          })
          .timeout(const Duration(milliseconds: 250));
    } on MissingPluginException {
      // No native clipboard-history monitor installed (yet) on this
      // platform/build -- nothing to suppress against.
      _log.debug('markSelfWrite: no native clipboard-history monitor');
    } on PlatformException catch (e) {
      // Advisory signal; a native-side failure must never block the write.
      _log.debug('markSelfWrite: native side reported a failure', e);
    } on TimeoutException {
      // Advisory signal; a stalled native reply must never block the write.
      _log.debug('markSelfWrite: native reply timed out');
    }
  }
}
