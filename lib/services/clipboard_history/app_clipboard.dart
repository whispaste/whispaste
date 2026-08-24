import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'clipboard_fingerprint.dart';
import 'clipboard_platform_capability.dart';
import 'self_write_signal.dart';
import 'self_write_suppression_registry.dart';

/// Central write path for every clipboard write WhisPaste performs on its
/// own behalf: transcript paste, clipboard restore after paste, panel-
/// triggered inserts, internal copy actions (history/markdown copy, etc.).
///
/// Marks the self-write suppression fingerprint *before* writing so
/// clipboard history never captures WhisPaste's own output as a new entry
/// -- see PRD.md "Self-Write-Suppression". [registry] is marked
/// unconditionally (cheap, in-memory) so the Linux snapshot-on-open path
/// (issue 06, no native monitor there) can consult it directly; the native
/// [signal] is only fired on platforms that actually run a rolling
/// clipboard monitor (issues 04-05) -- sending it on a platform with no
/// monitor installed is a pointless channel round trip on every single
/// paste.
///
/// The native signal is fired but deliberately not awaited: this sits
/// directly in the dictation hot path (Hotkey→Text is the product's core
/// speed metric), and a native monitor's *reply* round trip must never gate
/// the actual paste. [MethodChannelSelfWriteSignal] catches every exception
/// it can throw internally, so leaving it unawaited never drops an error
/// silently.
///
/// Dispatch-order assumption (unverified as of issues 01-02, to be checked
/// once issue 04's real native handler exists): Dart runs an async function
/// body synchronously up to its first real suspension point, so calling
/// [SelfWriteSignal.markSelfWrite] here dispatches its platform message
/// before the `Clipboard.setData` call below dispatches its own -- but
/// `com.whispaste.clipboard_history` and the clipboard platform channel are
/// two different channels, and cross-channel dispatch/handler-execution
/// order on the native side is not something the embedder promises. This
/// is why suppression matches by content fingerprint rather than by
/// predicting a native change-sequence number: even if the mark's native
/// handler runs *after* the monitor's next poll, a poll that observed
/// WhisPaste's own content can still be matched and suppressed
/// retroactively once the mark lands, as long as it arrives within
/// [SelfWriteSuppressionRegistry.expiry] resp. the native monitor's
/// equivalent window.
class AppClipboard {
  AppClipboard._();

  static SelfWriteSignal signal = const MethodChannelSelfWriteSignal();
  static SelfWriteSuppressionRegistry registry = SelfWriteSuppressionRegistry();

  static Future<void> setText(String text) async {
    final fingerprint = ClipboardFingerprint.ofText(text);
    registry.markSelfWrite(fingerprint);
    if (clipboardHistoryCapabilityFor(defaultTargetPlatform) ==
        ClipboardHistoryCapability.rollingHistory) {
      unawaited(signal.markSelfWrite(fingerprint));
    }
    await Clipboard.setData(ClipboardData(text: text));
  }
}
