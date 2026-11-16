import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../app_profiles/app_profile_resolver.dart'
    show targetEvidenceFromNativeId;
import '../clipboard_history/app_clipboard.dart';
import '../desktop_paste/channel_desktop_paste_controller.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import '../sound_feedback_service.dart';
import 'auto_paste_blocklist.dart';
import 'auto_send.dart';
import 'clipboard_unsaved_notifier.dart';
import 'field_type_policy.dart';
import 'paster.dart';

final _log = AppLogger('DesktopPaster');

/// [Paster] implementation for Windows and macOS using [DesktopPasteController].
///
/// Implements the full paste lifecycle:
/// - Blocklist check via bundle ID
/// - Classic clipboard save → set transcript → native paste → wait →
///   clipboard restore sequence, on every platform — this is the default,
///   not a fallback. If the native paste shortcut doesn't land (e.g. an app
///   that only reacts to direct keystrokes), macOS retries once via direct
///   Unicode typing (see [typeText]) — skipped for multi-line text (see
///   [requiresRealPaste]), since typing delivers "\n" as a literal Return
///   keydown some apps read as "submit". Windows and Linux report the failed
///   paste as-is: their native typeText is the same clipboard + Ctrl+V path,
///   so a retry would be a second paste (see [typingFallbackAfterFailedPaste]).
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
/// can paste it by hand (briefing N12). The one exception is the legacy switch
/// [PasteOptions.restoreClipboardWithoutReceipt] (W-E1), which restores after a
/// timeout only. macOS with secure input active never attempts a paste.
///
/// Pastes and typing run one after the other, so a second dictation cannot
/// snapshot the clipboard while the first one still uses it.
class DesktopPaster implements Paster, UndoKeystrokeSender, AutoSendKeys {
  DesktopPaster(
    this._controller, {
    this._receipts,
    this._snapshots,
    this._expectsHistoryExclusion,
    this.onSnapshotUnavailable,
    this.onPasted,
    bool? typingFallback,
  }) : _typingFallback =
           typingFallback ??
           typingFallbackAfterFailedPaste(defaultTargetPlatform);

  /// Whether a failed native paste is retried once via direct typing. Null
  /// in the constructor means [typingFallbackAfterFailedPaste] for this
  /// platform; injectable for tests.
  final bool _typingFallback;

  /// Called when a paste that landed would have restored the previous
  /// clipboard, but that content could not be read (macOS pasteboard privacy,
  /// or an empty read). The transcript stays on the clipboard then.
  final VoidCallback? onSnapshotUnavailable;

  /// Called after every paste that counts as done, whichever path pasted
  /// (the dictation, a snippet, the side panel, paste again, edit selection),
  /// and never after a failed paste. Plays the paste cue (#1343).
  final VoidCallback? onPasted;

  /// Done means [PasteOutcome.success], or [PasteOutcome.unconfirmedNoBridge]:
  /// a platform without any read receipt (Linux) never reports a success, and
  /// that outcome is its normal, silent paste. Every other unconfirmed outcome
  /// raises a notice, so the cue would contradict it.
  static bool countsAsPasted(PasteOutcome outcome) =>
      outcome == PasteOutcome.success ||
      outcome == PasteOutcome.unconfirmedNoBridge;

  PasteOutcome _reportPasted(PasteOutcome outcome) {
    if (countsAsPasted(outcome)) onPasted?.call();
    return outcome;
  }

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

  /// Full native clipboard backup (P1.1). Without it, or when a snapshot
  /// fails, only plain text is saved and restored.
  final ClipboardSnapshotBridge? _snapshots;

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

  /// How long a paste waits for a field-type answer that is still out. The
  /// probe starts with the recording, so it is normally long done; this only
  /// bounds a very short dictation (#167: no cost on the hotkey path beyond a
  /// short timeout).
  static const fieldTypeWait = Duration(milliseconds: 150);

  /// The field-type probe started by [prime], consumed by the next paste.
  Future<FocusedFieldType>? _fieldType;

  /// Asks for the focused field's type in the background (#948). Never
  /// throws: any failure reads as [FocusedFieldType.unknown].
  void _startFieldTypeProbe() {
    final controller = _controller;
    if (controller is! FocusedFieldTypeProbe) {
      _fieldType = null;
      return;
    }
    final probe = controller as FocusedFieldTypeProbe;
    Future<FocusedFieldType> run() async {
      try {
        return await probe.focusedFieldType();
      } on Object catch (e) {
        _log.debug('Field type probe failed — treated as unknown', e);
        return FocusedFieldType.unknown;
      }
    }

    _fieldType = run();
  }

  /// The type from the pending probe, consumed once. No probe, or no answer
  /// within [fieldTypeWait], is [FocusedFieldType.unknown].
  Future<FocusedFieldType> _takeFieldType() async {
    final pending = _fieldType;
    _fieldType = null;
    var type = FocusedFieldType.unknown;
    if (pending != null) {
      try {
        type = await pending.timeout(fieldTypeWait);
      } on TimeoutException {
        _log.debug('Field type probe too slow — treated as unknown');
      }
    }
    lastFieldType = type;
    return type;
  }

  /// The field type the latest paste decided on. The failure notice reads it:
  /// the general "password fields refuse the paste" hint (macOS) only fits
  /// while the type is [FocusedFieldType.unknown] (#949).
  FocusedFieldType lastFieldType = FocusedFieldType.unknown;

  /// Returns [PasteOutcome.passwordField] when the focused field is a password
  /// or PIN field (#948): no paste attempt, the transcript goes to the
  /// clipboard for a manual paste. `null` when auto-paste may proceed.
  Future<PasteOutcome?> _checkFieldType(String text) async {
    final type = await _takeFieldType();
    if (fieldTypeVerdict(type) == FieldTypeVerdict.paste) return null;
    _log.info(
      'Password field focused: no paste attempted, transcript kept on the '
      'clipboard',
    );
    try {
      await _writeTransientClipboardText(text);
    } on Exception {
      return PasteOutcome.failed;
    }
    return PasteOutcome.passwordField;
  }

  @override
  Future<void> prime() async {
    // A new recording invalidates any earlier insert for undo (DEV-165).
    _cleanPasteSerial = null;
    // Runs alongside the recording; the paste reads the answer (#948).
    _startFieldTypeProbe();
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
    } on TimeoutException {
      // No answer is not a platform verdict: let the caller keep its last
      // known capability instead of reporting "unsupported".
      rethrow;
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

  @override
  Future<bool> extraKeyHeld() async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.extraKeyHeld()
        : false;
  }

  @override
  Future<bool> sendEnter() async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.sendEnter()
        : false;
  }

  @override
  Future<UndoPlatformSupport> undoPlatformSupport() async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.undoPlatformSupport()
        : UndoPlatformSupport.none;
  }

  @override
  Future<ForegroundWindow?> foregroundWindow() async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.foregroundWindow()
        : null;
  }

  @override
  Future<bool> activateTarget(String id) async {
    final controller = _controller;
    return controller is ChannelDesktopPasteController
        ? controller.activateTarget(id)
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

  /// Whether the OS reports secure input right now (W-E1). Controllers without
  /// the probe, and platforms without the signal, count as inactive: the
  /// paste then runs as before.
  Future<bool> _secureInputActive() async {
    final controller = _controller;
    if (controller is! SecureInputProbe) return false;
    final probe = controller as SecureInputProbe;
    try {
      final state = await probe.secureInputState().timeout(
        const Duration(seconds: 2),
      );
      return state == SecureInputState.active;
    } on Object catch (e) {
      // Any probe failure (including Errors such as StateError) must not
      // abort the paste; it simply counts as "not active".
      _log.debug('Secure input probe failed — treated as inactive', e);
      return false;
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
      isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
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
      _serialized(() => _pasteUnlocked(text, options)).then(_reportPasted);

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

    // 1b. Secure input (W-E1, macOS): a secure field or another app holding
    // secure input takes the keystrokes, so the paste cannot land. No paste
    // attempt: the transcript goes to the clipboard and the outcome names the
    // skip (the reporter then names the holder, F35-8).
    if (await _secureInputActive()) {
      _log.info(
        'Secure input active: no paste attempted, transcript kept on the '
        'clipboard',
      );
      try {
        await _writeTransientClipboardText(text);
      } on Exception {
        return PasteOutcome.failed;
      }
      return PasteOutcome.secureInput;
    }

    // 1c. Password or PIN field (#948): same skip, so nothing lands there.
    final passwordField = await _checkFieldType(text);
    if (passwordField != null) return passwordField;

    // 2. Save current clipboard contents so we can restore after paste.
    final saved = await _saveClipboard();
    try {
      return await _pasteSaved(text, options, saved);
    } finally {
      // A snapshot that was not restored is dropped, so a large image does
      // not stay in memory until the next paste.
      if (saved.native && !saved.consumed) _discardSnapshot();
    }
  }

  Future<PasteOutcome> _pasteSaved(
    String text,
    PasteOptions options,
    _SavedClipboard saved,
  ) async {
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
      // The native verdict can be wrong while the keystroke still lands (macOS
      // sandbox: a stale permission preflight reports "denied" although the
      // event is delivered, #705). A read receipt is the hard proof, so it
      // overrides the verdict; no typing retry then, the text is already in.
      if (await _landedDespiteFailure(receipts, pasteResult)) {
        _log.info(
          'Native paste reported ${pasteResult.status.name}, but the target '
          'read the transcript — counting it as pasted',
        );
        // The reader may be a clipboard manager and the keystroke may have
        // been lost: the transcript stays on the clipboard, nothing is
        // restored over it.
        _cleanPasteSerial = ++_insertCounter;
        return PasteOutcome.success;
      }
      return _failedPasteOutcome(text, options, pasteResult);
    }

    // 5. The shortcut was sent. Only a read receipt from the target proves
    // the text arrived (briefing N12). Without one the outcome is unconfirmed,
    // and the transcript stays on the clipboard so the user can paste it. The
    // same holds when the receipt write itself was refused: nothing tells
    // whether the paste landed, so nothing is restored on any platform
    // (PAR-033).
    return _settleReceipt(receipts, restoreBuffer, options, saved);
  }

  /// Outcome of a paste whose native shortcut did not land: retries once via
  /// direct typing where that is safe, otherwise maps the native status.
  Future<PasteOutcome> _failedPasteOutcome(
    String text,
    PasteOptions options,
    NativePasteResult pasteResult,
  ) async {
    // The native paste shortcut didn't land — retry once via direct
    // Unicode typing where the platform has it (macOS; some apps don't react
    // to a synthetic paste shortcut at all). Multi-line text skips this
    // retry: CGEvent Unicode-typing delivers "\n"/"\r" as a literal Return
    // keydown, which chat UIs (ChatGPT, Slack, ...) read as "submit" —
    // better to report the paste failure than risk an unwanted send.
    if (_typingFallback && !requiresRealPaste(text)) {
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

  /// Step 5: only a read receipt from the target proves the paste landed; this
  /// decides the outcome and restores the previous clipboard when allowed.
  Future<PasteOutcome> _settleReceipt(
    ClipboardReceiptBridge? receipts,
    Duration restoreBuffer,
    PasteOptions options,
    _SavedClipboard saved,
  ) async {
    if (receipts == null) {
      return _unarmedReceiptOutcome();
    }
    int? lateMs;
    final receipt = await _awaitReceipt(
      receipts,
      restoreBuffer,
      lateGrace: lateReadGrace,
      onLateRead: (ms) => lateMs = ms,
    );
    await _logReceiptTiming(receipts, receipt, lateMs);
    if (receipt != ClipboardReadReceipt.read) {
      _log.info('Paste unconfirmed: receipt=${receipt.name}');
      // Legacy switch (W-E1): after a timeout the previous content comes back
      // once the fixed wait is over, as in the previous release. Only with
      // the owner check, so a copy made meanwhile is never overwritten. A
      // takeover (ownershipLost) restores nothing. The outcome stays
      // unconfirmed: nothing proves the paste landed.
      if (receipt == ClipboardReadReceipt.unknown &&
          options.restoreClipboardAfterPaste &&
          options.restoreClipboardWithoutReceipt) {
        _log.info(
          'Legacy switch: restoring the previous clipboard unconfirmed',
        );
        _noteUnavailableSnapshot(saved);
        // Only a restore that really ran changes what the message may say:
        // the transcript is then no longer on the clipboard (#1147).
        if (await _restoreOwnedClipboard(receipts, saved)) {
          return PasteOutcome.unconfirmedRestored;
        }
      }
      return PasteOutcome.unconfirmed;
    }
    return _finishConfirmed(receipts, options, saved);
  }

  /// How long a read that missed the wait window is still accepted as proof.
  /// Costs time only on the unconfirmed path.
  static const lateReadGrace = Duration(milliseconds: 1000);

  /// Diagnostic line for every paste with a receipt (#1147): whether and when
  /// the text was read (before the keystroke, in time, late, never) and the
  /// target app. Log only, never a decision.
  Future<void> _logReceiptTiming(
    ClipboardReceiptBridge receipts,
    ClipboardReadReceipt receipt,
    int? lateMs,
  ) async {
    String native = 'n/a';
    if (receipts is ClipboardReceiptDiagnostics) {
      try {
        native = await (receipts as ClipboardReceiptDiagnostics)
            .receiptDiagnostics()
            .timeout(const Duration(seconds: 1));
      } on Exception {
        native = 'unavailable';
      }
    }
    String target = '<unknown>';
    try {
      target = await _controller.getTargetBundleId() ?? '<unknown>';
    } on Exception catch (e) {
      _log.debug('Paste target unavailable for the receipt log', e);
    }
    final String when;
    if (receipt == ClipboardReadReceipt.read) {
      when = lateMs == null
          ? 'read within the wait window'
          : 'read after the wait window (+${lateMs}ms after the keystroke)';
    } else {
      when = 'not read (${receipt.name})';
    }
    _log.info('Paste receipt: $when; $native; target=$target');
  }

  /// The target read the transcript: restores the previous clipboard when the
  /// setting asks for it and reports the paste as done.
  Future<PasteOutcome> _finishConfirmed(
    ClipboardReceiptBridge receipts,
    PasteOptions options,
    _SavedClipboard saved,
  ) async {
    if (options.restoreClipboardAfterPaste) {
      _noteUnavailableSnapshot(saved);
      await _restoreOwnedClipboard(receipts, saved);
    } else {
      _log.info('Clipboard setting keeps the transcript — no restore');
    }
    // Only this path (native paste landed and the target read the transcript)
    // is a clean insert for undo.
    _cleanPasteSerial = ++_insertCounter;
    return PasteOutcome.success;
  }

  /// How long a failed native verdict waits for a late read receipt. It only
  /// costs time on the failure path; a clean paste never reaches it.
  static const failedPasteReceiptWait = Duration(milliseconds: 400);

  /// Whether the target read the transcript although the native side reported
  /// [result] as a failure. Only statuses that can follow a sent keystroke
  /// count (a missing target or a refused paste sent nothing). macOS only
  /// (the platform with the proven false alarm, same switch as the typing
  /// retry): on Windows a failed send really injected nothing, and on Linux
  /// no receipt exists before the key went out.
  Future<bool> _landedDespiteFailure(
    ClipboardReceiptBridge? receipts,
    NativePasteResult result,
  ) async {
    if (receipts == null || !_typingFallback) return false;
    if (result.status != NativePasteStatus.permissionMissing &&
        result.status != NativePasteStatus.postFailed) {
      return false;
    }
    final receipt = await _awaitReceipt(receipts, failedPasteReceiptWait);
    return receipt == ClipboardReadReceipt.read;
  }

  /// The outcome when no receipt could be armed. A platform without any
  /// bridge (Linux) is silent by design. A bridge that refused the write
  /// (macOS/Windows) is a gap the user is told about.
  PasteOutcome _unarmedReceiptOutcome() {
    if (_receipts != null) {
      _log.warning(
        'Paste unconfirmed: receipt write refused — transcript kept',
      );
      return PasteOutcome.unconfirmedReceiptRefused;
    }
    _log.info('Paste unconfirmed: no read receipt — transcript kept');
    return PasteOutcome.unconfirmedNoBridge;
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
    Duration restoreBuffer, {
    Duration lateGrace = Duration.zero,
    void Function(int msAfterPaste)? onLateRead,
  }) async {
    // The fixed buffer doubles as the timeout and as the floor for every
    // "no usable signal" answer (superseded receipt, channel error).
    final fallback = Future<void>.delayed(
      restoreBuffer,
    ).then((_) => ClipboardReadReceipt.unknown);
    final raw = receipts.waitForClipboardRead();
    final signal = raw.then<ClipboardReadReceipt>(
      (r) => r == ClipboardReadReceipt.unknown ? fallback : r,
      onError: (Object e) {
        _log.debug('Waiting for the clipboard read receipt failed', e);
        return fallback;
      },
    );
    var receipt = await Future.any<ClipboardReadReceipt>([signal, fallback]);
    if (receipt == ClipboardReadReceipt.unknown && lateGrace > Duration.zero) {
      // The read can come after the wait window although the text arrived
      // (a slow Electron or terminal target, #1147). The native wait is still
      // pending, so a late read still counts; a takeover or silence does not.
      final started = DateTime.now();
      final late = await Future.any<ClipboardReadReceipt>([
        raw.catchError((Object _) => ClipboardReadReceipt.unknown),
        Future<ClipboardReadReceipt>.delayed(
          lateGrace,
          () => ClipboardReadReceipt.unknown,
        ),
      ]);
      if (late == ClipboardReadReceipt.read) {
        receipt = late;
        onLateRead?.call(
          restoreBuffer.inMilliseconds +
              DateTime.now().difference(started).inMilliseconds,
        );
      }
    }
    if (receipt == ClipboardReadReceipt.read) {
      await Future<void>.delayed(receiptSafetyMargin);
    }
    return receipt;
  }

  /// Saves the clipboard before the paste: natively with every format where
  /// the platform supports it, otherwise as plain text.
  Future<_SavedClipboard> _saveClipboard() async {
    final snapshots = _snapshots;
    if (snapshots != null) {
      final stopwatch = Stopwatch()..start();
      ClipboardSnapshot snapshot;
      try {
        snapshot = await snapshots.snapshotClipboard().timeout(
          const Duration(seconds: 2),
        );
      } on Exception catch (e) {
        _log.debug('Native clipboard snapshot failed: ${errorKind(e)}');
        snapshot = const ClipboardSnapshot(ClipboardSnapshotStatus.failed);
        // A timed-out host may still finish the snapshot; drop it so it does
        // not linger until the next paste.
        _discardSnapshot();
      }
      // Counts only, never the content.
      _log.info(
        'Clipboard snapshot: status=${snapshot.status.name} '
        'formats=${snapshot.formats} bytes=${snapshot.bytes} '
        'after=${stopwatch.elapsedMilliseconds}ms',
      );
      switch (snapshot.status) {
        case ClipboardSnapshotStatus.saved:
          return _SavedClipboard.native(snapshot.text);
        case ClipboardSnapshotStatus.empty:
        case ClipboardSnapshotStatus.denied:
          // Nothing readable: the text read would find nothing either.
          return _SavedClipboard.text(null);
        case ClipboardSnapshotStatus.failed:
          break;
      }
    }
    try {
      final data = await Clipboard.getData(
        Clipboard.kTextPlain,
      ).timeout(const Duration(seconds: 2));
      return _SavedClipboard.text(data?.text);
    } on Exception catch (e) {
      // Best-effort snapshot; failure here is non-fatal.
      _log.debug(
        'Clipboard read before paste failed — proceeding without restore',
        e,
      );
      return _SavedClipboard.text(null);
    }
  }

  void _discardSnapshot() {
    final snapshots = _snapshots;
    if (snapshots == null) return;
    unawaited(
      snapshots.discardClipboardSnapshot().catchError((Object e) {
        _log.debug('Discarding the clipboard snapshot failed', e);
      }),
    );
  }

  /// An unreadable or empty snapshot is unknown content, so it is never
  /// restored: writing it back would erase whatever the clipboard holds.
  void _noteUnavailableSnapshot(_SavedClipboard saved) {
    if (saved.available) return;
    _log.info('Previous clipboard unreadable — not restored');
    onSnapshotUnavailable?.call();
  }

  /// Restores the saved clipboard, but only while WhisPaste still owns the
  /// clipboard, so a copy the user made meanwhile is never overwritten.
  /// True when the previous content is back on the clipboard.
  Future<bool> _restoreOwnedClipboard(
    ClipboardReceiptBridge receipts,
    _SavedClipboard saved,
  ) async {
    final stopwatch = Stopwatch()..start();
    if (!saved.available) {
      _log.info(
        'No snapshot before paste — leaving the transcript on the clipboard',
      );
      return false;
    }
    final text = saved.text;
    if (text != null && text.isNotEmpty) AppClipboard.markTransientWrite(text);
    ClipboardRestoreOutcome outcome;
    try {
      final snapshots = _snapshots;
      if (saved.native && snapshots != null) {
        saved.consumed = true;
        outcome = await snapshots.restoreClipboardSnapshotIfOwner().timeout(
          const Duration(seconds: 5),
        );
      } else {
        outcome = await receipts
            .restoreClipboardTextIfOwner(text!)
            .timeout(const Duration(seconds: 5));
      }
    } on Exception catch (e) {
      // Non-fatal — clipboard restore is best-effort.
      _log.debug('Clipboard restore after paste failed: ${errorKind(e)}');
      outcome = ClipboardRestoreOutcome.failed;
    }
    _log.info(
      'Receipt restore: restore=${outcome.name} '
      'native=${saved.native} after=${stopwatch.elapsedMilliseconds}ms',
    );
    return outcome == ClipboardRestoreOutcome.restored;
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
          _expectsHistoryExclusion ??
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS);
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
      _serialized(() => _typeTextUnlocked(text, options)).then(_reportPasted);

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
    // Password or PIN field (#948): no typing either.
    final passwordField = await _checkFieldType(text);
    if (passwordField != null) return passwordField;
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

/// Whether a failed native paste may be retried once via typing on
/// [platform] (read from the platform seam, #198). Only macOS has a
/// real direct-typing primitive (CGEvent Unicode strings). Windows' typeText
/// is clipboard + Ctrl+V, because KEYEVENTF_UNICODE bursts corrupt text in
/// Notepad's TSF control (desktop_paste_host.cpp), and Linux' is clipboard +
/// uinput Ctrl+V: a retry there is a second paste of the same text. A failed
/// status can still follow injected keys (a partial SendInput burst), so the
/// retry could insert the transcript twice.
bool typingFallbackAfterFailedPaste(TargetPlatform platform) =>
    platform == TargetPlatform.macOS;

final pasterProvider = Provider<Paster?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  if (controller == null) return null;
  return DesktopPaster(
    controller,
    // Every desktop controller has one (GR-015); test fakes may not.
    receipts: controller is ClipboardReceiptBridge
        ? controller as ClipboardReceiptBridge
        : null,
    snapshots: controller is ClipboardSnapshotBridge
        ? controller as ClipboardSnapshotBridge
        : null,
    // The paste runs asynchronously; the provider may already be disposed
    // when the snapshot turns out unreadable, so check before touching ref.
    onSnapshotUnavailable: defaultTargetPlatform == TargetPlatform.macOS
        ? () {
            if (!ref.mounted) return;
            ref.read(clipboardUnsavedNotifierProvider.notifier).report();
          }
        : null,
    // The paste cue on every platform; the sound service checks the switch,
    // the volume and whether the profile has the cue.
    onPasted: () {
      if (!ref.mounted) return;
      unawaited(ref.read(soundFeedbackProvider.notifier).playPaste());
    },
  );
});

/// What step 2 of a paste saved of the user's clipboard: a native snapshot of
/// every format (with its plain-text form, if any), or plain text only.
class _SavedClipboard {
  _SavedClipboard.native(this.text) : native = true;
  _SavedClipboard.text(this.text) : native = false;

  final bool native;
  final String? text;

  /// Set once the native snapshot was handed to the restore.
  bool consumed = false;

  bool get available => native || (text != null && text!.isNotEmpty);
}
