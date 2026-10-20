import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../app_profiles/app_profile_resolver.dart'
    show targetEvidenceFromNativeId;
import '../clipboard_history/app_clipboard.dart';
import '../desktop_paste/channel_desktop_paste_controller.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import 'auto_paste_blocklist.dart';
import 'clipboard_unsaved_notifier.dart';
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
/// Success is only reported with proof. With a [ClipboardReceiptBridge]
/// (macOS, Windows, Linux) the proof is the target's read of the transcript: the
/// restore then runs [receiptSafetyMargin] later, and only while WhisPaste
/// still owns the clipboard. Without that read (no receipt bridge, timeout,
/// takeover, or typed keystrokes) the outcome is [PasteOutcome.unconfirmed]:
/// nothing is restored, and the transcript stays on the clipboard so the user
/// can paste it by hand (briefing N12).
///
/// Pastes and typing run one after the other, so a second dictation cannot
/// snapshot the clipboard while the first one still uses it.
class DesktopPaster implements Paster, UndoKeystrokeSender {
  DesktopPaster(
    this._controller, {
    this._receipts,
    this._expectsHistoryExclusion,
    this.onSnapshotUnavailable,
  });

  /// Called when a paste that landed would have restored the previous
  /// clipboard, but that content could not be read (macOS pasteboard privacy,
  /// or an empty read). The transcript stays on the clipboard then.
  final VoidCallback? onSnapshotUnavailable;

  /// Tail of the paste queue. Every paste and typing call runs after the one
  /// before it, so a second dictation cannot snapshot or restore the clipboard
  /// while the first one is still using it (briefing N12).
  Future<void> _queue = Future<void>.value();

  Future<PasteOutcome> _serialized(Future<PasteOutcome> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  final DesktopPasteController _controller;
  final ClipboardReceiptBridge? _receipts;

  /// Whether this platform has a native history-excluded clipboard write, so
  /// falling back to the plain write is a Win+V leak worth a warning rather
  /// than the expected path. Null defaults to Windows and macOS; injectable
  /// for tests.
  final bool? _expectsHistoryExclusion;

  /// Insert counter and the serial of the last clean (native clipboard) paste,
  /// see [cleanPasteSerial]. Every insert and every recording start clears it.
  int _insertCounter = 0;
  int? _cleanPasteSerial;

  @override
  int? get cleanPasteSerial => _cleanPasteSerial;

  /// Pause between the target's read receipt and the restore, so a reader
  /// that pulls the data in several quick calls (or re-reads it while
  /// handling the paste event) still sees the transcript.
  static const receiptSafetyMargin = Duration(milliseconds: 150);

  @override
  Future<void> prime() async {
    // A new recording invalidates any earlier insert for undo (DEV-165).
    _cleanPasteSerial = null;
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

  /// Cmd+Z / Ctrl+Z in the frontmost app. False where the platform has no
  /// undo keystroke (then the caller copies the original text instead).
  @override
  Future<bool> sendUndoShortcut() async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.sendUndoShortcut()
        : false;
  }

  /// Input-idle snapshot from the native host. Null where the host cannot
  /// answer (no handler on this platform, channel error); the caller then
  /// counts the input as typed.
  @override
  Future<InputIdleSnapshot?> inputIdleSnapshot() async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.inputIdleSnapshot()
        : null;
  }

  @override
  Future<bool> copyOriginalToClipboard(String text) async {
    try {
      await _writeTransientClipboardText(
        text,
      ).timeout(const Duration(seconds: 5));
      return true;
    } on Exception catch (e) {
      _log.debug('Copying the original text for undo failed', e);
      return false;
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

  /// Returns [PasteOutcome.blocked] when the block list applies: the captured
  /// target is listed, or the list is set and the target is unknown (AUF-1,
  /// fail-closed). `null` when auto-paste may proceed. An empty list never
  /// blocks. Shared by [paste] and [typeText].
  Future<PasteOutcome?> _checkBlocklist(String blocklist) async {
    if (blocklist.trim().isEmpty) return null;
    String? targetId;
    try {
      targetId = await _controller.getTargetBundleId();
    } on Exception catch (e) {
      // Missing plugin, platform error or timeout: the target is unknown.
      _log.debug('getTargetBundleId failed — target unknown', e);
    }
    final verdict = evaluateAutoPasteBlocklist(
      raw: blocklist,
      target: targetEvidenceFromNativeId(targetId),
      isMacOS: Platform.isMacOS,
    );
    switch (verdict) {
      case AutoPasteBlocklistVerdict.allowed:
        return null;
      case AutoPasteBlocklistVerdict.listed:
        _log.info('Auto-paste blocked: target app is on the block list');
        return PasteOutcome.blocked;
      case AutoPasteBlocklistVerdict.targetUnknown:
        _log.warning(
          'Auto-paste blocked: block list is set but the target app is '
          'unknown (copied only)',
        );
        return PasteOutcome.blocked;
    }
  }

  /// Maps a non-success [NativePasteResult] to the matching [PasteOutcome].
  /// Shared by [paste] and [typeText] — both native bridges report the same
  /// status vocabulary.
  PasteOutcome _mapFailure(NativePasteResult result) => switch (result.status) {
    NativePasteStatus.noTarget => PasteOutcome.noTarget,
    NativePasteStatus.permissionMissing => PasteOutcome.permissionMissing,
    NativePasteStatus.foregroundBlocked => PasteOutcome.elevationBlocked,
    NativePasteStatus.targetChanged => PasteOutcome.targetChanged,
    _ => PasteOutcome.failed,
  };

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) =>
      _serialized(() => _pasteUnlocked(text, options));

  Future<PasteOutcome> _pasteUnlocked(String text, PasteOptions options) async {
    _cleanPasteSerial = null;
    // 1. Blocklist check
    final blocked = await _checkBlocklist(options.blocklist);
    if (blocked != null) {
      // GS-075: a blocked paste still leaves the transcript on the clipboard,
      // unless the user switched that off (maintainer 4a+c).
      if (options.copyBlockedToClipboard) {
        await _writeTransientClipboardText(text);
      }
      return blocked;
    }

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

    // Wait before restoring clipboard. Minimum 500 ms so the OS paste has
    // landed before we overwrite it — with a receipt, this is only the upper
    // bound (timeout fallback).
    final restoreBuffer = Duration(milliseconds: math.max(500, delayMs + 350));

    // Briefing B3 criterion 1: the captured app is no longer frontmost. The
    // native side refused on purpose. Retyping would send the transcript into
    // whatever app the user switched to, and restoring would drop it, so the
    // transcript stays on the clipboard for a manual paste.
    if (pasteResult.status == NativePasteStatus.targetChanged) {
      _log.info('Paste refused: the target app changed during processing');
      return PasteOutcome.targetChanged;
    }

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
        if (typeOutcome == PasteOutcome.unconfirmed) {
          // Keystrokes were sent, but nothing proves they reached the field.
          // The transcript stays on the clipboard as the fallback.
          return typeOutcome;
        }
        _log.info(
          'Fallback typing also did not land ($typeOutcome) — reporting '
          'the original paste failure',
        );
      }
      return _mapFailure(pasteResult);
    }

    // 5. The shortcut was sent. Only a read receipt from the target proves
    // the text arrived (briefing N12). Without one the outcome is unconfirmed,
    // and the transcript stays on the clipboard so the user can paste it. The
    // same holds when the receipt write itself was refused: nothing tells
    // whether the paste landed, so nothing is restored on any platform
    // (PAR-033).
    if (receipts == null) {
      _log.info('Paste unconfirmed: no read receipt — transcript kept');
      return PasteOutcome.unconfirmedNoBridge;
    }
    final receipt = await _awaitReceipt(receipts, restoreBuffer);
    if (receipt != ClipboardReadReceipt.read) {
      _log.info('Paste unconfirmed: receipt=${receipt.name}');
      return PasteOutcome.unconfirmed;
    }
    if (options.restoreClipboardAfterPaste) {
      _noteUnavailableSnapshot(previousClipboard);
      await _restoreOwnedClipboard(receipts, previousClipboard);
    } else {
      _log.info('Clipboard setting keeps the transcript — no restore');
    }
    // Only this path (native paste landed and the target read the transcript)
    // is a clean insert for undo.
    _cleanPasteSerial = ++_insertCounter;
    return PasteOutcome.success;
  }

  /// Tries the receipt write for [text]; `false` (no bridge, unsupported,
  /// channel failure) means the caller uses the classic transient write.
  Future<bool> _armReceipt(String text) async {
    final receipts = _receipts;
    if (receipts == null) return false;
    try {
      AppClipboard.markTransientWrite(text);
      return await receipts
          .writeClipboardTextWithReceipt(text)
          .timeout(const Duration(seconds: 5));
    } on Exception catch (e) {
      // Warning, not debug: a failed receipt means the restore falls back to
      // a fixed delay, and we need to see how often that happens in practice.
      _log.warning('Receipt clipboard write unavailable — classic path', e);
      return false;
    }
  }

  /// Waits for the target's read receipt, bounded by [restoreBuffer]. Returns
  /// [ClipboardReadReceipt.read] only when the target really read the
  /// transcript; a timeout or a takeover returns something else.
  Future<ClipboardReadReceipt> _awaitReceipt(
    ClipboardReceiptBridge receipts,
    Duration restoreBuffer,
  ) async {
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
    if (receipt == ClipboardReadReceipt.read) {
      await Future<void>.delayed(receiptSafetyMargin);
    }
    return receipt;
  }

  /// An unreadable or empty snapshot is unknown content, so it is never
  /// restored: writing it back would erase whatever the clipboard holds.
  void _noteUnavailableSnapshot(String? previousClipboard) {
    if (previousClipboard != null && previousClipboard.isNotEmpty) return;
    _log.info('Previous clipboard unreadable — not restored');
    onSnapshotUnavailable?.call();
  }

  /// Restores [previousClipboard], but only while WhisPaste still owns the
  /// clipboard, so a copy the user made meanwhile is never overwritten.
  Future<void> _restoreOwnedClipboard(
    ClipboardReceiptBridge receipts,
    String? previousClipboard,
  ) async {
    final stopwatch = Stopwatch()..start();
    if (previousClipboard == null || previousClipboard.isEmpty) {
      _log.info(
        'No plain-text snapshot before paste — leaving the transcript on the '
        'clipboard',
      );
      return;
    }
    AppClipboard.markTransientWrite(previousClipboard);
    ClipboardRestoreOutcome outcome;
    try {
      outcome = await receipts
          .restoreClipboardTextIfOwner(previousClipboard)
          .timeout(const Duration(seconds: 5));
    } on Exception catch (e) {
      // Non-fatal — clipboard restore is best-effort.
      _log.debug('Clipboard restore after paste failed', e);
      outcome = ClipboardRestoreOutcome.failed;
    }
    _log.info(
      'Receipt restore: restore=${outcome.name} '
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
    AppClipboard.markTransientWrite(text);
    final excluded = await _controller.writeClipboardTextExcludingHistory(text);
    if (!excluded) {
      // Method and platform only, never the text (GS-114). Warning where a
      // history-excluded write exists (Windows, macOS: BIZ-61); info on Linux
      // (6c+a), where only Klipper honours the hint anyway. Logged once per
      // fallback.
      final message =
          'History-excluded clipboard write not available — plain write used, '
          'which clipboard history (Win+V, Klipper, ...) may record (issue '
          '#146) (platform=${Platform.operatingSystem})';
      final expectsExclusion =
          _expectsHistoryExclusion ?? (Platform.isWindows || Platform.isMacOS);
      if (expectsExclusion) {
        _log.warning(message);
      } else {
        _log.info(message);
      }
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) =>
      _serialized(() => _typeTextUnlocked(text, options));

  Future<PasteOutcome> _typeTextUnlocked(
    String text,
    PasteOptions options,
  ) async {
    _cleanPasteSerial = null;
    // 1. Blocklist check — same policy as paste().
    final blocked = await _checkBlocklist(options.blocklist);
    if (blocked != null) {
      // GS-075: a blocked paste still leaves the transcript on the clipboard,
      // unless the user switched that off (maintainer 4a+c).
      if (options.copyBlockedToClipboard) {
        await _writeTransientClipboardText(text);
      }
      return blocked;
    }
    return _typeTextCore(text, options);
  }

  /// The actual native Unicode-type call, without a blocklist check — reused
  /// by both [typeText] (which does its own check first) and [paste]'s
  /// macOS-preferred-mechanism attempt (which already checked the blocklist
  /// before calling this, so re-checking would be a redundant native round
  /// trip). No clipboard involved, so there is nothing to save/restore.
  Future<PasteOutcome> _typeTextCore(String text, PasteOptions options) async {
    // Criterion 5 (no simulated Enter): typed "\n"/"\r" is a Return keystroke.
    if (requiresRealPaste(text)) return PasteOutcome.failed;
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

    // Typed keystrokes have no read receipt, so they are not proof of delivery
    // (briefing N12).
    return PasteOutcome.unconfirmed;
  }
}

final pasterProvider = Provider<Paster?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  if (controller == null) return null;
  return DesktopPaster(
    controller,
    // Every desktop controller has one (GR-015); test fakes may not.
    receipts: controller is ClipboardReceiptBridge
        ? controller as ClipboardReceiptBridge
        : null,
    // The paste runs asynchronously; the provider may already be disposed
    // when the snapshot turns out unreadable, so check before touching ref.
    onSnapshotUnavailable: Platform.isMacOS
        ? () {
            if (!ref.mounted) return;
            ref.read(clipboardUnsavedNotifierProvider.notifier).report();
          }
        : null,
  );
});
