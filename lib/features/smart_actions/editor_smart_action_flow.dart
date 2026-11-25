/// Smart Mode on the selection (#650), the part both editors share: what to
/// work on, which language or instruction, the lock, the replacement as one
/// undo step and the notices. Recordings and Notes only add what they keep
/// as a version before the text changes ([beforeApply]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/announce.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/text/text_undo.dart';
import '../../services/smart_mode/editor_smart_action.dart';
import '../../services/smart_mode/smart_mode_presets.dart';
import '../../services/smart_mode/smart_mode_retroactive_service.dart'
    show SmartModeRetroactiveFailureReason;
import '../../widgets/dialog.dart';
import '../../widgets/smart_mode_language_picker.dart';
import '../../widgets/wp_notice_bar.dart';
import '../../widgets/wp_text_field.dart';
import '../history/data/history_detail_provider.dart'
    show smartModeBusyProvider;

/// Name of [action] in what is read out and shown after a run.
String _modeLabel(
  L10n l10n,
  EditorSmartAction action,
  SmartModeTargetLanguage? language,
) => switch (action) {
  EditorSmartAction.cleanUp => l10n.smartModePresetCleanup,
  EditorSmartAction.shorten => l10n.smartModePresetConcise,
  EditorSmartAction.translate =>
    language == null
        ? l10n.smartModePresetTranslate
        : '${l10n.smartModePresetTranslate} '
              '(${smartModeTargetLanguageLabel(l10n, language)})',
  EditorSmartAction.custom => l10n.editorSmartActionCustomTitle,
};

/// The message for a run that replaced nothing.
String editorSmartActionFailureMessage(
  L10n l10n,
  SmartModeRetroactiveFailureReason reason,
) => switch (reason) {
  SmartModeRetroactiveFailureReason.modelMissing =>
    l10n.historySmartModeFailedModelMissing,
  SmartModeRetroactiveFailureReason.timeout =>
    l10n.historySmartModeFailedTimeout,
  SmartModeRetroactiveFailureReason.checkTimedOut =>
    l10n.smartModeCheckTimedOut,
  SmartModeRetroactiveFailureReason.engineError ||
  SmartModeRetroactiveFailureReason.blankResult ||
  SmartModeRetroactiveFailureReason.factsChanged =>
    l10n.historySmartModeFailedGeneric,
};

/// Runs [action] on the selection of [controller], or on the paragraph at
/// the caret when nothing is selected. The result replaces that text as one
/// undo step and stays selected; the notice offers to undo it.
///
/// [lockKey] is the key of the text in [smartModeBusyProvider], so a
/// retroactive preset and an action on the selection never run on the same
/// recording at once. [beforeApply] keeps the text before the change as a
/// version. [languageCode] is the text's language where known.
Future<void> runEditorSmartAction(
  BuildContext context,
  WidgetRef ref, {
  required TextEditingController controller,
  required EditorSmartAction action,
  required String lockKey,
  Future<void> Function()? beforeApply,
  String? languageCode,
}) async {
  final l10n = L10n.of(context);
  final range = editorSmartActionRange(controller.value);
  if (range == null) {
    showWpNotice(
      context,
      WpNotice(
        id: 'editor-smart-action-nothing',
        message: l10n.editorSmartActionNothing,
      ),
    );
    return;
  }
  final original = range.textInside(controller.text);

  SmartModeTargetLanguage? language;
  String? instruction;
  switch (action) {
    case EditorSmartAction.translate:
      language = await showWpSmartModeTargetLanguagePicker(context);
      if (language == null) return;
    case EditorSmartAction.custom:
      instruction = await showEditorSmartInstructionDialog(context);
      if (instruction == null) return;
    case EditorSmartAction.cleanUp || EditorSmartAction.shorten:
      break;
  }
  if (!context.mounted) return;

  final busy = ref.read(smartModeBusyProvider.notifier);
  if (!busy.tryAcquire(lockKey)) {
    showWpNotice(
      context,
      WpNotice(id: 'smart-mode-busy', message: l10n.smartModeBusyRetry),
    );
    return;
  }
  final mode = _modeLabel(l10n, action, language);
  try {
    announce(
      View.of(context),
      l10n.historyReprocessRunning(mode),
      Directionality.of(context),
    );
    final result = await ref
        .read(editorSmartActionServiceProvider)
        .run(
          action: action,
          text: original,
          instruction: instruction,
          targetLanguage: language,
          languageCode: languageCode,
        );
    if (!context.mounted) return;
    switch (result) {
      case EditorSmartActionFailure(:final reason):
        showWpNotice(
          context,
          WpNotice(
            id: 'editor-smart-action-failed',
            kind: WpNoticeKind.error,
            message: editorSmartActionFailureMessage(l10n, reason),
          ),
        );
      case EditorSmartActionSuccess(:final text):
        // Typing while the model ran wins; the result is not forced over it.
        final current = controller.text;
        if (range.end > current.length ||
            range.textInside(current) != original) {
          showWpNotice(
            context,
            WpNotice(
              id: 'editor-smart-action-changed',
              message: l10n.editorSmartActionChanged,
            ),
          );
          return;
        }
        await beforeApply?.call();
        if (!context.mounted) return;
        final replaced = applyEditorSmartActionResult(
          controller.value,
          range,
          text,
        );
        if (replaced == null) return;
        TextUndoController.command(controller, () {
          controller.value = replaced;
        });
        showWpNotice(
          context,
          WpNotice(
            id: 'editor-smart-action-done',
            kind: WpNoticeKind.undo,
            message: l10n.editorSmartActionDone(mode),
            actionLabel: l10n.smartModeUndoAction,
            actionTestId: 'editor-smart-action-undo',
            onAction: () => _undo(controller, replaced.text),
          ),
        );
    }
  } finally {
    busy.release(lockKey);
  }
}

/// [value] with [range] replaced by [result], the result selected; null
/// when [range] no longer fits the text.
TextEditingValue? applyEditorSmartActionResult(
  TextEditingValue value,
  TextRange range,
  String result,
) {
  if (!range.isValid || range.end > value.text.length) return null;
  return TextEditingValue(
    text: range.textBefore(value.text) + result + range.textAfter(value.text),
    selection: TextSelection(
      baseOffset: range.start,
      extentOffset: range.start + result.length,
    ),
  );
}

/// Steps back over the replacement, but only while the text is still the
/// one it produced: an undo from the notice never throws away later typing.
void _undo(TextEditingController controller, String replacedText) {
  if (controller.text != replacedText) return;
  final undo = TextUndoController.of(controller);
  if (undo != null && undo.canUndo) undo.undo();
}

/// Asks for the user's own instruction. Returns it trimmed, or null when
/// cancelled.
Future<String?> showEditorSmartInstructionDialog(BuildContext context) =>
    showWpFormDialog<String>(
      context: context,
      builder: (context, animation) => _InstructionDialog(animation: animation),
    );

class _InstructionDialog extends StatefulWidget {
  const _InstructionDialog({required this.animation});

  final Animation<double> animation;

  @override
  State<_InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<_InstructionDialog> {
  final _instruction = TextEditingController();

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  String get _value => _instruction.text.trim();

  void _confirm() {
    if (_value.isNotEmpty) Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final valid = _value.isNotEmpty;
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.editorSmartActionCustomTitle,
      subtitle: l10n.editorSmartActionCustomSubtitle,
      fields: [
        WpTextField(
          testId: 'editor-smart-instruction-field',
          key: const ValueKey('editor-smart-instruction-field'),
          controller: _instruction,
          variant: WpTextFieldVariant.form,
          hintText: l10n.editorSmartActionCustomHint,
          semanticsLabel: l10n.editorSmartActionCustomField,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
        ),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'editor-smart-instruction-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: l10n.editorSmartActionCustomConfirm,
          testId: 'editor-smart-instruction-confirm',
          role: WpDialogActionRole.primary,
          enabled: valid,
          onPressed: valid ? _confirm : null,
        ),
      ],
    );
  }
}
