/// Smart Mode on the selection of an editor (#650): clean up, shorten,
/// translate or a custom instruction, applied to the marked text of a
/// recording or a note.
///
/// The text goes through the same engine (local model or the cloud provider
/// the user already chose, ADR 0010), the same built-in prompts and the same
/// fact guard as the retroactive presets; only the scope differs. The
/// dictation hotkey path never calls into this file.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../drift_recording_store.dart' show factKnownTermsProvider;
import '../recording/pipeline_step_runner.dart';
import '../selection_edit/selection_edit_prompt.dart'
    show selectionEditInstructionSystemPrompt;
import '../user_models/user_model_use.dart'
    show smartModeLocalModelReadyProvider;
import 'smart_mode_fact_guard.dart';
import 'smart_mode_ffi_engine.dart' show smartModeEngineProvider;
import 'smart_mode_presets.dart';
import 'smart_mode_retroactive_service.dart'
    show SmartModeRetroactiveFailureReason;

/// The four actions on the selection, in menu order.
enum EditorSmartAction { cleanUp, shorten, translate, custom }

/// The text an action works on: the selection when there is one, else the
/// paragraph (line) the caret stands in, with surrounding white space left
/// out. Never the whole text unless it is a single paragraph. Null when there
/// is nothing to work on: no caret, a blank selection or a blank line.
TextRange? editorSmartActionRange(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid) return null;
  int start;
  int end;
  if (!selection.isCollapsed) {
    start = selection.start;
    end = selection.end;
  } else {
    final caret = selection.baseOffset.clamp(0, text.length);
    start = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final lineEnd = text.indexOf('\n', caret);
    end = lineEnd < 0 ? text.length : lineEnd;
  }
  while (start < end && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  if (start >= end) return null;
  return TextRange(start: start, end: end);
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// Outcome of [EditorSmartActionService.run].
sealed class EditorSmartActionResult {
  const EditorSmartActionResult();
}

/// The engine's text, checked by the fact guard, ready to replace the range.
final class EditorSmartActionSuccess extends EditorSmartActionResult {
  const EditorSmartActionSuccess(this.text);

  final String text;
}

/// Nothing to replace; the text stays as it is.
final class EditorSmartActionFailure extends EditorSmartActionResult {
  const EditorSmartActionFailure(this.reason);

  final SmartModeRetroactiveFailureReason reason;
}

class EditorSmartActionService {
  EditorSmartActionService(this._ref);

  final Ref _ref;

  static const _timeout = Duration(seconds: 15);

  @visibleForTesting
  static Duration? timeoutOverride;

  /// Runs [action] over [text]. [instruction] is the user's own wording for
  /// [EditorSmartAction.custom]; [targetLanguage] the language for
  /// [EditorSmartAction.translate]. [languageCode] is the language of the
  /// text where known (a recording's), deciding the fact guard's name rule.
  Future<EditorSmartActionResult> run({
    required EditorSmartAction action,
    required String text,
    String? instruction,
    SmartModeTargetLanguage? targetLanguage,
    String? languageCode,
  }) async {
    final settings = _ref.read(settingsProvider).value;
    final provider = SmartModeProviderType.fromValue(
      settings?.smartMode.provider,
    );
    if (provider.isLocal && !_ref.read(smartModeLocalModelReadyProvider)) {
      return const EditorSmartActionFailure(
        SmartModeRetroactiveFailureReason.modelMissing,
      );
    }
    final vocabulary = settings?.stt.customVocabulary ?? '';
    final (systemPrompt, userText) = switch (action) {
      EditorSmartAction.cleanUp => (
        smartModeSystemPromptFor(
          SmartModePreset.cleanup,
          vocabulary: vocabulary,
        ),
        text,
      ),
      EditorSmartAction.shorten => (
        smartModeSystemPromptFor(
          SmartModePreset.concise,
          vocabulary: vocabulary,
        ),
        text,
      ),
      EditorSmartAction.translate => (
        smartModeSystemPromptFor(
          SmartModePreset.translate,
          targetLanguage: targetLanguage,
          vocabulary: vocabulary,
        ),
        text,
      ),
      EditorSmartAction.custom => (
        selectionEditInstructionSystemPrompt,
        editorSmartActionInstructionText(instruction ?? '', text),
      ),
    };

    final runner = PipelineStepRunner(timeout: timeoutOverride ?? _timeout);
    final engine = _ref.read(smartModeEngineProvider);
    final result = await runner.run<String>(
      'editor_smart_action',
      () => engine.run(systemPrompt: systemPrompt, userText: userText),
    );
    switch (result) {
      case Ok(:final value):
        final edited = value.trim();
        if (edited.isEmpty) {
          return const EditorSmartActionFailure(
            SmartModeRetroactiveFailureReason.blankResult,
          );
        }
        final language = factGuardLanguage(
          configured: languageCode?.isNotEmpty ?? false
              ? languageCode!
              : settings?.sttLanguageCode ?? 'auto',
        );
        final check = await checkSmartModeFacts(
          input: text,
          output: edited,
          checkNames: action != EditorSmartAction.translate,
          knownTerms: await _ref.read(factKnownTermsProvider)(),
          singleCapitalisedWordsAreNames: singleWordsAreNamesFor(language),
        );
        final violations = check.violations;
        if (violations == null) {
          return EditorSmartActionFailure(
            check.failure == SmartModeGuardFailure.timedOut
                ? SmartModeRetroactiveFailureReason.checkTimedOut
                : SmartModeRetroactiveFailureReason.factsChanged,
          );
        }
        if (violations.isNotEmpty) {
          return const EditorSmartActionFailure(
            SmartModeRetroactiveFailureReason.factsChanged,
          );
        }
        return EditorSmartActionSuccess(edited);
      case StepTimeout():
        unawaited(engine.cancel());
        return const EditorSmartActionFailure(
          SmartModeRetroactiveFailureReason.timeout,
        );
      case FailedWith():
        return const EditorSmartActionFailure(
          SmartModeRetroactiveFailureReason.engineError,
        );
    }
  }
}

/// The user text for a custom instruction: the instruction, then the text
/// clearly delimited, so the model never edits the instruction itself.
String editorSmartActionInstructionText(String instruction, String text) =>
    'Instruction: ${instruction.trim()}\n\n<text>\n$text\n</text>';

final editorSmartActionServiceProvider = Provider<EditorSmartActionService>(
  EditorSmartActionService.new,
);
