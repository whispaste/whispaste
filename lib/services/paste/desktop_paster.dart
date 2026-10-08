import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../clipboard_history/app_clipboard.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import 'paster.dart';

final _log = AppLogger('DesktopPaster');

/// [Paster] implementation for Windows and macOS using [DesktopPasteController].
///
/// Implements the full paste lifecycle:
/// - Blocklist check via bundle ID
/// - Classic clipboard save → set transcript → native paste → wait →
///   clipboard restore sequence, on every platform — this is the default,
///   not a fallback. If the native paste shortcut doesn't land (e.g. an app
///   that only reacts to direct keystrokes), macOS/Windows retry once via
///   direct Unicode typing (see [typeText]) — skipped for multi-line text
///   (see [requiresRealPaste]), since typing delivers "\n" as a literal
///   Return keydown some apps read as "submit". Linux stays on the classic
///   sequence only; it has no native typeText handler to fall back to.
///
/// The choice of native mechanism is an implementation detail: from the
/// user's perspective there is one "paste" action, regardless of which of
/// the two channels actually delivered the text.
///
/// With a [ClipboardReceiptBridge] (macOS/Windows), the "wait" step is
/// receipt-based: the restore runs [receiptSafetyMargin] after the target
/// app actually read the transcript, and only while WhisPaste still owns the
/// clipboard. Without a receipt within the classic buffer, the restore
/// happens after that buffer as before (still ownership-checked).
class DesktopPaster implements Paster {
  const DesktopPaster(this._controller, {this._receipts});

  final DesktopPasteController _controller;
  final ClipboardReceiptBridge? _receipts;

  /// Pause between the target's read receipt and the restore, so a reader
  /// that pulls the data in several quick calls (or re-reads it while
  /// handling the paste event) still sees the transcript.
  static const receiptSafetyMargin = Duration(milliseconds: 150);

  @override
  Future<void> prime() async {
    try {
      await _controller.capturePasteTarget();
    } on MissingPluginException catch (e) {
      // Not available in test environments — silently degrade.
      _log.debug('capturePasteTarget unavailable (MissingPlugin)', e);
    }
  }

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async {
    try {
      final raw = await _controller.checkCapability(
        promptIfMissing: promptIfMissing,
      );
      return PasteCapability(
        status: switch (raw.status) {
          NativeCapabilityStatus.ready => PasteCapabilityStatus.ready,
          NativeCapabilityStatus.permissionMissing =>
            PasteCapabilityStatus.permissionMissing,
          NativeCapabilityStatus.unsupported =>
            PasteCapabilityStatus.unsupported,
        },
        canPrompt: raw.canPrompt,
        detail: raw.detail,
      );
    } on MissingPluginException {
      return const PasteCapability(status: PasteCapabilityStatus.unsupported);
    } on Exception {
      return const PasteCapability(status: PasteCapabilityStatus.unsupported);
    }
  }

  @override
  Future<String?> getTargetBundleId() async {
    try {
      final id = await _controller.getTargetBundleId();
      return (id == null || id.isEmpty) ? null : id;
    } on MissingPluginException catch (e) {
      _log.debug('getTargetBundleId unavailable (MissingPlugin)', e);
      return null;
    }
  }

  /// Returns [PasteOutcome.blocked] when the captured target's bundle ID is
  /// on [blocklist]; `null` otherwise (including when the lookup is
  /// unsupported or the target ID is unavailable). Shared by [paste] and
  /// [typeText] — both gate on the same blocklist.
  Future<PasteOutcome?> _checkBlocklist(String blocklist) async {
    final trimmed = blocklist.trim();
    if (trimmed.isEmpty) return null;
    try {
      final targetId = await _controller.getTargetBundleId();
      if (targetId == null || targetId.isEmpty) return null;
      final blocked = trimmed
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (blocked.contains(targetId.toLowerCase())) {
        return PasteOutcome.blocked;
      }
      return null;
    } on MissingPluginException catch (e) {
      // Bundle ID lookup unsupported — skip blocklist.
      _log.debug(
        'getTargetBundleId unavailable (MissingPlugin) — blocklist skipped',
        e,
      );
      return null;
    }
  }

  /// Maps a non-success [NativePasteResult] to the matching [PasteOutcome].
  /// Shared by [paste] and [typeText] — both native bridges report the same
  /// status vocabulary.
  PasteOutcome _mapFailure(NativePasteResult result) => switch (result.status) {
    NativePasteStatus.noTarget => PasteOutcome.noTarget,
    NativePasteStatus.permissionMissing => PasteOutcome.permissionMissing,
    NativePasteStatus.foregroundBlocked => PasteOutcome.elevationBlocked,
    _ => PasteOutcome.failed,
  };

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    // 1. Blocklist check
    final blocked = await _checkBlocklist(options.blocklist);
    if (blocked != null) return blocked;

    // 2. Save current clipboard contents so we can restore after paste.
    String? previousClipboard;
    try {
      final data = await Clipboard.getData(
        Clipboard.kTextPlain,
      ).timeout(const Duration(seconds: 2));
      previousClipboard = data?.text;
    } on Exception catch (e) {
      // Best-effort snapshot; failure here is non-fatal.
      _log.debug(
        'Clipboard read before paste failed — proceeding without restore',
        e,
      );
    }

    // 3. Write transcript to clipboard — preferably as a receipt write
    // (lazily rendered, so the native host learns when the target reads it),
    // otherwise as the classic transient write. Both are history-excluded on
    // platforms that support it, so this transient write never becomes a
    // new Win+V/cloud-clipboard entry (issue #146).
    final receipts = await _armReceipt(text) ? _receipts : null;
    if (receipts == null) {
      try {
        await _writeTransientClipboardText(
          text,
        ).timeout(const Duration(seconds: 5));
      } on Exception {
        return PasteOutcome.failed;
      }
    }

    // 4. Trigger native paste shortcut.
    final delayMs = options.autoPasteDelayMs.clamp(0, 30000);
    final delay = Duration(milliseconds: delayMs);
    NativePasteResult pasteResult = const NativePasteResult(
      status: NativePasteStatus.unknown,
    );
    try {
      pasteResult = await _controller.pasteClipboard(delay: delay);
    } on MissingPluginException {
      return PasteOutcome.platformUnavailable;
    } on Exception {
      return PasteOutcome.failed;
    }

    // Always log the native detail string so we can diagnose silent-drop
    // scenarios where Swift reports success (CGEvent post returned, no
    // error) but the keystroke didn't actually land in the target app.
    _log.info(
      'Native paste result: status=${pasteResult.status.name} '
      'detail=${pasteResult.detail ?? "<none>"}',
    );

    if (!pasteResult.isSuccess) {
      // The native paste shortcut didn't land — retry once via direct
      // Unicode typing on macOS/Windows (some apps don't react to a
      // synthetic paste shortcut at all). Multi-line text skips this
      // retry regardless of platform: CGEvent Unicode-typing delivers
      // "\n"/"\r" as a literal Return keydown, which chat UIs (ChatGPT,
      // Slack, ...) read as "submit" — better to report the paste failure
      // than risk an unwanted send. Linux's typeText routes through the
      // exact same clipboard+uinput-Ctrl+V path as pasteClipboard (no
      // layout-independent direct-typing primitive exists there either —
      // see desktop_paste_host.cc), so retrying it after a failed paste
      // would just reproduce the same failure; a failed paste there is
      // reported as-is.
      if ((Platform.isMacOS || Platform.isWindows) &&
          !requiresRealPaste(text)) {
        final typeOutcome = await _typeTextCore(text, options);
        if (typeOutcome == PasteOutcome.success) return typeOutcome;
        _log.info(
          'Fallback typing also did not land ($typeOutcome) — reporting '
          'the original paste failure',
        );
      }
      return _mapFailure(pasteResult);
    }

    // 5. Wait before restoring clipboard.
    // Minimum 500 ms so the OS paste has landed before we overwrite it —
    // with a receipt, this is only the upper bound (timeout fallback).
    final restoreBuffer = Duration(milliseconds: math.max(500, delayMs + 350));
    if (receipts != null) {
      await _restoreAfterReceipt(receipts, previousClipboard, restoreBuffer);
      return PasteOutcome.success;
    }
    await Future<void>.delayed(restoreBuffer);

    // 6. Restore previous clipboard contents — same history-exclusion as the
    // transcript write above: restoring is WhisPaste's own housekeeping, not
    // a fresh copy the user made, so it shouldn't surface as a new history
    // entry either (issue #146).
    try {
      await _writeTransientClipboardText(
        previousClipboard ?? '',
      ).timeout(const Duration(seconds: 5));
    } on Exception catch (e) {
      // Non-fatal — clipboard restore is best-effort.
      _log.debug('Clipboard restore after paste failed', e);
    }

    return PasteOutcome.success;
  }

  /// Tries the receipt write for [text]; `false` (no bridge, unsupported,
  /// channel failure) means the caller uses the classic transient write.
  Future<bool> _armReceipt(String text) async {
    final receipts = _receipts;
    if (receipts == null) return false;
    try {
      AppClipboard.markSelfWrite(text);
      return await receipts
          .writeClipboardTextWithReceipt(text)
          .timeout(const Duration(seconds: 5));
    } on Exception catch (e) {
      _log.debug('Receipt clipboard write unavailable — classic path', e);
      return false;
    }
  }

  /// Waits for the target's read receipt (bounded by [restoreBuffer]), then
  /// restores [previousClipboard] unless another process took the clipboard
  /// over in the meantime.
  Future<void> _restoreAfterReceipt(
    ClipboardReceiptBridge receipts,
    String? previousClipboard,
    Duration restoreBuffer,
  ) async {
    final stopwatch = Stopwatch()..start();
    // The fixed buffer doubles as the timeout and as the floor for every
    // "no usable signal" answer (superseded receipt, channel error).
    final fallback = Future<void>.delayed(
      restoreBuffer,
    ).then((_) => ClipboardReadReceipt.unknown);
    final signal = receipts.waitForClipboardRead().then<ClipboardReadReceipt>(
      (r) => r == ClipboardReadReceipt.unknown ? fallback : r,
      onError: (Object e) {
        _log.debug('Waiting for the clipboard read receipt failed', e);
        return fallback;
      },
    );
    final receipt = await Future.any<ClipboardReadReceipt>([signal, fallback]);
    switch (receipt) {
      case ClipboardReadReceipt.read:
        await Future<void>.delayed(receiptSafetyMargin);
      case ClipboardReadReceipt.ownershipLost:
        _log.info('Clipboard taken over by another writer — skipping restore');
        return;
      case ClipboardReadReceipt.unknown:
        break;
    }

    final restoreText = previousClipboard ?? '';
    AppClipboard.markSelfWrite(restoreText);
    ClipboardRestoreOutcome outcome;
    try {
      outcome = await receipts
          .restoreClipboardTextIfOwner(restoreText)
          .timeout(const Duration(seconds: 5));
    } on Exception catch (e) {
      // Non-fatal — clipboard restore is best-effort.
      _log.debug('Clipboard restore after paste failed', e);
      outcome = ClipboardRestoreOutcome.failed;
    }
    _log.info(
      'Receipt restore: receipt=${receipt.name} restore=${outcome.name} '
      'after=${stopwatch.elapsedMilliseconds}ms',
    );
  }

  /// Writes [text] to the clipboard for a transient purpose (the paste
  /// source, or restoring the user's prior clipboard right after) rather
  /// than a real user-facing copy action. Always marks WhisPaste's own
  /// self-write-suppression fingerprint first (so the app's internal
  /// clipboard-history panel doesn't record it), then prefers the native,
  /// OS-history-excluded write where the platform supports one — falling
  /// back to the plain clipboard write everywhere else.
  Future<void> _writeTransientClipboardText(String text) async {
    AppClipboard.markSelfWrite(text);
    final excluded = await _controller.writeClipboardTextExcludingHistory(text);
    if (!excluded) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async {
    // 1. Blocklist check — same policy as paste().
    final blocked = await _checkBlocklist(options.blocklist);
    if (blocked != null) return blocked;
    return _typeTextCore(text, options);
  }

  /// The actual native Unicode-type call, without a blocklist check — reused
  /// by both [typeText] (which does its own check first) and [paste]'s
  /// macOS-preferred-mechanism attempt (which already checked the blocklist
  /// before calling this, so re-checking would be a redundant native round
  /// trip). No clipboard involved, so there is nothing to save/restore.
  Future<PasteOutcome> _typeTextCore(String text, PasteOptions options) async {
    final delayMs = options.autoPasteDelayMs.clamp(0, 30000);
    NativePasteResult typeResult = const NativePasteResult(
      status: NativePasteStatus.unknown,
    );
    try {
      typeResult = await _controller.typeText(
        text,
        delay: Duration(milliseconds: delayMs),
      );
    } on MissingPluginException {
      return PasteOutcome.platformUnavailable;
    } on Exception {
      return PasteOutcome.failed;
    }

    _log.info(
      'Native type result: status=${typeResult.status.name} '
      'detail=${typeResult.detail ?? "<none>"}',
    );

    if (!typeResult.isSuccess) {
      return _mapFailure(typeResult);
    }

    return PasteOutcome.success;
  }
}

final pasterProvider = Provider<Paster?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  if (controller == null) return null;
  return DesktopPaster(
    controller,
    // macOS/Windows only — Linux's controller has no receipt bridge.
    receipts: controller is ClipboardReceiptBridge
        ? controller as ClipboardReceiptBridge
        : null,
  );
});
