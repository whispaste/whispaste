/// "Edit selection by voice" (`.scratch/voice-selection-edit/`): reads the
/// foreground app's selection via a simulated copy, runs the spoken
/// instruction over it with the configured Smart Mode engine, and replaces
/// the selection through the regular paste path. Undo in the target app
/// (Cmd/Ctrl+Z) restores the original, because the replacement is a normal
/// paste over a still-active selection.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../clipboard_history/app_clipboard.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import '../paste/paster.dart';
import '../recording/pipeline_step_runner.dart';
import '../smart_mode/smart_mode_engine.dart';
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
}

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
  Future<void> writeTransient(String text) async {
    AppClipboard.markSelfWrite(text);
    final excluded = await _controller.writeClipboardTextExcludingHistory(text);
    if (!excluded) await Clipboard.setData(ClipboardData(text: text));
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
    String Function()? sentinelFactory,
  }) : _sentinelFactory = sentinelFactory ?? _defaultSentinel;

  final SelectionCopier _copy;
  final SelectionClipboard _clipboard;
  final Duration pollInterval;
  final Duration pollTimeout;
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

    try {
      final sentinel = _sentinelFactory();
      await _clipboard.writeTransient(sentinel);
      final result = await _copy(delay);
      if (!result.isSuccess) {
        _log.info(
          'Copy shortcut failed: status=${result.status.name} '
          'detail=${result.detail ?? "<none>"}',
        );
        return SelectionReadFailed(result.status);
      }
      final copied = await _waitForChange(sentinel);
      if (copied == null || copied.trim().isEmpty) {
        return const SelectionReadEmpty();
      }
      return SelectionReadOk(copied);
    } on Exception catch (e) {
      _log.warning('Selection read failed', e);
      return const SelectionReadFailed(NativePasteStatus.unknown);
    } finally {
      try {
        await _clipboard.writeTransient(snapshot ?? '');
      } on Exception catch (e) {
        _log.warning('Clipboard restore after selection read failed', e);
      }
    }
  }

  /// The target app copies asynchronously after the key event — poll until
  /// the clipboard no longer holds [sentinel], or give up (= no selection).
  Future<String?> _waitForChange(String sentinel) async {
    final watch = Stopwatch()..start();
    while (true) {
      await Future<void>.delayed(pollInterval);
      final text = await _clipboard.readText();
      if (text != null && text != sentinel) return text;
      if (watch.elapsed >= pollTimeout) return null;
    }
  }
}

/// Why a selection edit did not replace anything. In every case the
/// original selection is left untouched and the clipboard restored.
enum SelectionEditFailure {
  noSelection,
  copyFailed,
  engineFailed,
  pasteFailed;

  /// Error code shown via `localizeRecordingError` in the overlay.
  String get errorCode => switch (this) {
    noSelection => 'selection_edit_no_selection',
    copyFailed => 'selection_edit_copy_failed',
    engineFailed => 'selection_edit_failed',
    pasteFailed => 'selection_edit_paste_failed',
  };
}

class SelectionEditOutcome {
  const SelectionEditOutcome.success(String this.result) : failure = null;
  const SelectionEditOutcome.failed(SelectionEditFailure this.failure)
    : result = null;

  final String? result;
  final SelectionEditFailure? failure;
}

class SelectionEditService {
  SelectionEditService({
    required this._reader,
    required this._engine,
    required this._paster,
    this.engineTimeout = const Duration(seconds: 20),
  });

  final SelectionReader _reader;
  final SmartModeEngine _engine;
  final Paster _paster;
  final Duration engineTimeout;

  /// Reads the selection, applies [instruction] to it and pastes the result
  /// over it. Nothing is pasted unless the engine returned a non-blank
  /// result.
  Future<SelectionEditOutcome> run({
    required String instruction,
    required PasteOptions pasteOptions,
    SmartModeTargetLanguage translateTarget = SmartModeTargetLanguage.english,
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

    final pasted = await _paster.paste(edited, pasteOptions);
    if (pasted != PasteOutcome.success) {
      _log.warning('Selection edit paste failed: ${pasted.name}');
      return const SelectionEditOutcome.failed(
        SelectionEditFailure.pasteFailed,
      );
    }
    return SelectionEditOutcome.success(edited);
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
  );
});
