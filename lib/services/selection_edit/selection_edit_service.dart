/// "Edit selection by voice" (`.scratch/voice-selection-edit/`): reads the
/// foreground app's selection via a simulated copy, runs the spoken
/// instruction over it with the configured Smart Mode engine, and replaces
/// the selection through the regular paste path. Undo in the target app
/// (Cmd/Ctrl+Z) restores the original, because the replacement is a normal
/// paste over a still-active selection.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../clipboard_history/app_clipboard.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import '../drift_recording_store.dart' show factKnownTermsProvider;
import '../paste/paster.dart';
import 'selection_undo.dart';
import '../recording/pipeline_step_runner.dart';
import '../smart_mode/smart_mode_engine.dart';
import '../smart_mode/smart_mode_fact_guard.dart';
import '../smart_mode/smart_mode_name_changes.dart';
import '../smart_mode/smart_mode_ffi_engine.dart' show smartModeEngineProvider;
import '../smart_mode/smart_mode_presets.dart';
import 'selection_edit_prompt.dart';

final _log = AppLogger('SelectionEdit');

/// The clipboard operations the selection read needs — a seam so tests can
/// run without the Flutter clipboard plugin.
abstract class SelectionClipboard {
  Future<String?> readText();

  /// Writes [text] as WhisPaste's own transient housekeeping write (kept
  /// out of the in-app and, where supported, the OS clipboard history).
  Future<void> writeTransient(String text);

  /// Whether the OS currently denies WhisPaste programmatic access to the
  /// clipboard (macOS pasteboard privacy). A denied read returns nothing, so
  /// a snapshot taken then must never be written back.
  Future<bool> readAccessDenied();
}

/// Same channel as the desktop paste controller, for the one probe the
/// selection read needs beyond the controller interface.
const _clipboardAccessChannel = MethodChannel('com.whispaste.desktop_paste');

/// Production [SelectionClipboard], using the same transient write as
/// [DesktopPaster] so neither the probe nor the restore shows up as a
/// clipboard-history entry.
class SystemSelectionClipboard implements SelectionClipboard {
  const SystemSelectionClipboard(this._controller);

  final DesktopPasteController _controller;

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(
      Clipboard.kTextPlain,
    ).timeout(const Duration(seconds: 2));
    return data?.text;
  }

  @override
  Future<bool> readAccessDenied() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _clipboardAccessChannel.invokeMethod<bool>(
            'clipboardReadDenied',
          ) ??
          false;
    } on Exception catch (e) {
      // No native handler (old build) means no privacy restriction is known.
      _log.debug('clipboardReadDenied unavailable', e);
      return false;
    }
  }

  @override
  Future<void> writeTransient(String text) async {
    AppClipboard.markSelfWrite(text);
    final excluded = await _controller.writeClipboardTextExcludingHistory(text);
    if (!excluded) {
      // Method and platform only, never the text (GS-114).
      _log.info(
        'writeClipboardText not excluded from history '
        '(platform=${Platform.operatingSystem}); plain write used',
      );
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}

/// Sends the native copy shortcut to the captured target.
typedef SelectionCopier = Future<NativePasteResult> Function(Duration delay);

sealed class SelectionReadResult {
  const SelectionReadResult();
}

final class SelectionReadOk extends SelectionReadResult {
  const SelectionReadOk(this.text);
  final String text;
}

/// The copy shortcut landed but the clipboard did not change — nothing was
/// selected (or only whitespace).
final class SelectionReadEmpty extends SelectionReadResult {
  const SelectionReadEmpty();
}

/// The copy shortcut itself could not be delivered.
final class SelectionReadFailed extends SelectionReadResult {
  const SelectionReadFailed(this.status);
  final NativePasteStatus status;
}

/// Reads the current selection: snapshot clipboard → write a unique
/// sentinel → simulate copy → poll until the clipboard differs from the
/// sentinel → always restore the snapshot.
///
/// The sentinel (instead of comparing against the snapshot) is what makes
/// "nothing selected" detectable even when the selection happens to equal
/// the current clipboard content. Only plain text is round-tripped — the
/// same limitation as the existing paste path.
class SelectionReader {
  SelectionReader({
    required this._copy,
    required this._clipboard,
    this.pollInterval = const Duration(milliseconds: 40),
    this.pollTimeout = const Duration(milliseconds: 600),
    this.lateCopyGrace = const Duration(milliseconds: 300),
    String Function()? sentinelFactory,
  }) : _sentinelFactory = sentinelFactory ?? _defaultSentinel;

  final SelectionCopier _copy;
  final SelectionClipboard _clipboard;
  final Duration pollInterval;
  final Duration pollTimeout;

  /// Extra window after [pollTimeout] for a busy target app that copies late.
  /// A copy that lands after this window is not read and is overwritten by
  /// the snapshot restore — a residual risk, since restoring is immediate.
  final Duration lateCopyGrace;
  final String Function() _sentinelFactory;

  static final _random = math.Random();

  static String _defaultSentinel() =>
      'whispaste-selection-probe-'
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<SelectionReadResult> read({Duration delay = Duration.zero}) async {
    String? snapshot;
    try {
      snapshot = await _clipboard.readText();
    } on Exception catch (e) {
      _log.debug('Clipboard snapshot before copy failed', e);
    }

    // A denied pasteboard reads as nothing, so the snapshot cannot be trusted
    // and writing anything back would erase the user's clipboard. Stop first.
    if (await _clipboard.readAccessDenied()) {
      _log.info('Clipboard access denied — selection read skipped');
      return const SelectionReadFailed(NativePasteStatus.clipboardAccessDenied);
    }

    // No readable text snapshot (image/file, or unreadable) means there is
    // nothing to restore, so the probe writes no sentinel. A sentinel left
    // behind or an empty-string restore would damage the clipboard; the copy
    // is detected by any text appearing instead.
    final sentinel = snapshot == null ? null : _sentinelFactory();
    try {
      if (sentinel != null) await _clipboard.writeTransient(sentinel);
      final result = await _copy(delay);
      if (!result.isSuccess) {
        _log.info(
          'Copy shortcut failed: status=${result.status.name} '
          'detail=${result.detail ?? "<none>"}',
        );
        return SelectionReadFailed(result.status);
      }
      final copied = await _waitForChange(sentinel ?? snapshot);
      if (copied == null || copied.trim().isEmpty) {
        return const SelectionReadEmpty();
      }
      return SelectionReadOk(copied);
    } on Exception catch (e) {
      _log.warning('Selection read failed', e);
      return const SelectionReadFailed(NativePasteStatus.unknown);
    } finally {
      if (sentinel != null && snapshot != null) {
        try {
          await _clipboard.writeTransient(snapshot);
        } on Exception catch (e) {
          _log.warning('Clipboard restore after selection read failed', e);
        }
      }
    }
  }

  /// The target app copies asynchronously after the key event — poll until
  /// the clipboard no longer holds [previous], or give up (= no selection).
  /// [previous] is the sentinel, or the snapshot when there is none (then any
  /// text counts as the copy). The window is [pollTimeout] plus
  /// [lateCopyGrace], so an app that answers a little late is still read.
  Future<String?> _waitForChange(String? previous) async {
    final watch = Stopwatch()..start();
    final deadline = pollTimeout + lateCopyGrace;
    while (true) {
      await Future<void>.delayed(pollInterval);
      final text = await _clipboard.readText();
      if (text != null && text != previous) return text;
      if (watch.elapsed >= deadline) return null;
    }
  }
}

/// Why a selection edit did not replace anything. In every case the
/// original selection is left untouched and the clipboard restored.
enum SelectionEditFailure {
  noSelection,
  copyFailed,
  engineFailed,

  /// A free instruction changed a protected fact the instruction does not
  /// name (GS-030). Its own message, so the user learns why nothing happened.
  factsChanged,

  /// The fact check ran out of time (GS-045). The text stays unchanged; this
  /// is not a changed fact (DEV-151).
  checkTimedOut,
  pasteFailed;

  /// Error code shown via `localizeRecordingError` in the overlay.
  String get errorCode => switch (this) {
    noSelection => 'selection_edit_no_selection',
    copyFailed => 'selection_edit_copy_failed',
    engineFailed => 'selection_edit_failed',
    factsChanged => 'selection_edit_facts_changed',
    checkTimedOut => 'selection_edit_check_timed_out',
    pasteFailed => 'selection_edit_paste_failed',
  };
}

class SelectionEditOutcome {
  const SelectionEditOutcome.success(
    String this.result, {
    this.nameChanges = const [],
    this.undo,
  }) : failure = null,
       offendingValue = null;
  const SelectionEditOutcome.failed(
    SelectionEditFailure this.failure, {
    this.offendingValue,
  }) : result = null,
       nameChanges = const [],
       undo = null;

  final String? result;
  final SelectionEditFailure? failure;

  /// Names a free instruction changed, for the name-change summary (2c). Empty
  /// for quick actions, translations and failures.
  final List<SmartModeNameChange> nameChanges;

  /// Lets the name toast revert the edit (DEV-165). Only set with
  /// [nameChanges].
  final SelectionUndoTicket? undo;

  /// The protected value a free instruction changed without naming (BIZ-32),
  /// shortened for display. Only set for [SelectionEditFailure.factsChanged].
  final String? offendingValue;

  /// Error key for the overlay: the failure's code, plus the offending value
  /// after a colon when there is one.
  String? get failureCode {
    final failed = failure;
    if (failed == null) return null;
    final value = offendingValue;
    return value == null ? failed.errorCode : '${failed.errorCode}:$value';
  }
}

/// Keeps a rejection message readable when the offending value is a long
/// link or similar token (BIZ-32).
String _shortenOffendingValue(String value, {int maxLength = 40}) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}…';
}

class SelectionEditService {
  SelectionEditService({
    required this._reader,
    required this._engine,
    required this._paster,
    this.engineTimeout = const Duration(seconds: 20),
    this.factTerms,
  });

  final SelectionReader _reader;
  final SmartModeEngine _engine;
  final Paster _paster;
  final Duration engineTimeout;

  /// Dictionary name terms for the fact guard (matrix 2.5); none when null.
  final Future<List<String>> Function()? factTerms;

  /// Reads the selection, applies [instruction] to it and pastes the result
  /// over it. Nothing is pasted unless the engine returned a non-blank
  /// result.
  ///
  /// [factLanguageCode] decides the fact guard's name rule (DEV-83, DEV-107):
  /// the caller passes the configured language, else the detected one.
  Future<SelectionEditOutcome> run({
    required String instruction,
    required PasteOptions pasteOptions,
    SmartModeTargetLanguage translateTarget = SmartModeTargetLanguage.english,
    required String factLanguageCode,
  }) async {
    final read = await _reader.read();
    final String selection;
    switch (read) {
      case SelectionReadOk(:final text):
        selection = text;
      case SelectionReadEmpty():
        return const SelectionEditOutcome.failed(
          SelectionEditFailure.noSelection,
        );
      case SelectionReadFailed(:final status):
        _log.info('Selection could not be read (copy status=${status.name})');
        return const SelectionEditOutcome.failed(
          SelectionEditFailure.copyFailed,
        );
    }

    final prompt = buildSelectionEditPrompt(
      instruction: instruction,
      selection: selection,
      translateTarget: translateTarget,
    );
    _log.info(
      'Running selection edit '
      '(quickAction=${prompt.quickAction?.name ?? "none"}, '
      'selectionChars=${selection.length})',
    );

    final step = await PipelineStepRunner(timeout: engineTimeout).run<String>(
      'selection_edit',
      () => _engine.run(
        systemPrompt: prompt.systemPrompt,
        userText: prompt.userText,
      ),
    );
    final String edited;
    switch (step) {
      case Ok(:final value) when value.trim().isNotEmpty:
        edited = value.trim();
      case Ok():
        _log.warning('Selection edit returned a blank result');
        return const SelectionEditOutcome.failed(
          SelectionEditFailure.engineFailed,
        );
      case StepTimeout():
        _log.warning('Selection edit timed out after $engineTimeout');
        // Stop the generation we gave up on instead of letting it burn
        // CPU/GPU in the background (SmartModeEngine.cancel contract).
        unawaited(_engine.cancel());
        return const SelectionEditOutcome.failed(
          SelectionEditFailure.engineFailed,
        );
      case FailedWith(:final error):
        _log.warning('Selection edit engine failed: $error');
        return const SelectionEditOutcome.failed(
          SelectionEditFailure.engineFailed,
        );
    }

    // Fact guard (matrix 2.5). The selection is untrusted text (web, mail): a
    // prompt injection inside it can make the engine change a number, a link
    // or a name. Predefined quick actions keep their rules: translations
    // leave names unchecked, the others check everything, and any violation
    // blocks. A free instruction ("ändere 3 zu 5") changes facts on purpose,
    // so it is checked too, but a missing token is allowed when the
    // instruction names it or the result adds a token the instruction names
    // (GS-030).
    final quickAction = prompt.quickAction;
    final terms = factTerms == null ? const <String>[] : await factTerms!();
    final namesOfLanguage = singleWordsAreNamesFor(factLanguageCode);
    final missingCheck = await checkSmartModeFacts(
      input: selection,
      output: edited,
      checkNames:
          quickAction != null &&
          quickAction != SelectionEditQuickAction.translate,
      knownTerms: terms,
      singleCapitalisedWordsAreNames: namesOfLanguage,
    );
    final missing = missingCheck.violations;
    if (missing == null) {
      // No answer: fail closed, the selection stays untouched (DEV-141).
      return _guardFailed(missingCheck.failure);
    }
    if (quickAction != null) {
      if (missing.isNotEmpty) {
        _log.warning(
          'Selection edit changed protected facts (${missing.length})',
        );
        return const SelectionEditOutcome.failed(
          SelectionEditFailure.engineFailed,
        );
      }
    } else {
      // Both directions on every free instruction: a token the result drops
      // and a token it adds must each be named by the instruction (BIZ-31).
      // Free instructions protect only dictionary names: capitalisation
      // heuristics misfire on translations and rewrites (DEV-135, BIZ-33).
      final addedCheck = await checkSmartModeFacts(
        input: edited,
        output: selection,
        checkNames: false,
        knownTerms: terms,
        singleCapitalisedWordsAreNames: namesOfLanguage,
      );
      final added = addedCheck.violations;
      if (added == null) {
        return _guardFailed(addedCheck.failure);
      }
      final unexplained = smartModeUnexplainedViolations(
        missing: missing,
        added: added,
        instruction: instruction,
      );
      if (unexplained.isNotEmpty) {
        _log.warning(
          'Free selection edit changed ${unexplained.length} protected fact(s) '
          'the instruction does not name',
        );
        return SelectionEditOutcome.failed(
          SelectionEditFailure.factsChanged,
          offendingValue: _shortenOffendingValue(unexplained.first.token),
        );
      }
    }
    final nameChanges = await _nameChangesFor(
      instruction: instruction,
      quickAction: quickAction,
      before: selection,
      after: edited,
      namesOfLanguage: namesOfLanguage,
    );
    final sinceInsert = Stopwatch()..start();
    final pasted = await _paster.paste(edited, pasteOptions);
    if (pasted != PasteOutcome.success) {
      _log.warning('Selection edit paste failed: ${pasted.name}');
      return const SelectionEditOutcome.failed(
        SelectionEditFailure.pasteFailed,
      );
    }
    final insertSerial = cleanInsertSerial(_paster);
    return SelectionEditOutcome.success(
      edited,
      nameChanges: nameChanges,
      undo: nameChanges.isEmpty
          ? null
          : SelectionUndoTicket(
              originalText: selection,
              targetBundleId: await _paster.getTargetBundleId(),
              insertSerial: insertSerial,
              sinceInsert: sinceInsert,
            ),
    );
  }

  /// The guard gave no answer. A timeout has its own message (DEV-151); a
  /// throw keeps the factsChanged wording, as before.
  static SelectionEditOutcome _guardFailed(SmartModeGuardFailure? reason) {
    return SelectionEditOutcome.failed(
      reason == SmartModeGuardFailure.timedOut
          ? SelectionEditFailure.checkTimedOut
          : SelectionEditFailure.factsChanged,
    );
  }

  /// Name changes for the 2c toast, computed before the insert (DEV-163). A
  /// failure only drops the summary: it never turns a replaced selection into
  /// an error. Quick actions and translations change names on purpose.
  Future<List<SmartModeNameChange>> _nameChangesFor({
    required String instruction,
    required SelectionEditQuickAction? quickAction,
    required String before,
    required String after,
    required bool namesOfLanguage,
  }) async {
    // Everything sits inside the try, so no step here can fail the insert.
    try {
      if (quickAction != null || isTranslationInstruction(instruction)) {
        return const [];
      }
      return await checkSmartModeNameChanges(
            before: before,
            after: after,
            singleCapitalisedWordsAreNames: namesOfLanguage,
          ) ??
          const [];
    } on Object catch (error) {
      _log.warning('Name-change summary skipped (${error.runtimeType})');
      return const [];
    }
  }
}

/// `null` when the platform has no paste path (then the feature is
/// unavailable, same as auto-paste). Tests override this provider.
final selectionEditServiceProvider = Provider<SelectionEditService?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  final paster = ref.watch(pasterProvider);
  if (controller == null || paster == null) return null;
  return SelectionEditService(
    reader: SelectionReader(
      copy: (delay) => controller.copySelection(delay: delay),
      clipboard: SystemSelectionClipboard(controller),
    ),
    engine: ref.watch(smartModeEngineProvider),
    paster: paster,
    factTerms: ref.read(factKnownTermsProvider),
  );
});
