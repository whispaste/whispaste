import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_text_field.dart';

/// Asks for a paragraph number between 1 and [count] (#641). Returns the
/// 1-based number, or null when cancelled.
Future<int?> showGoToParagraphDialog(
  BuildContext context, {
  required int count,
}) => showWpFormDialog<int>(
  context: context,
  builder: (context, animation) =>
      _GoToParagraphDialog(animation: animation, count: count),
);

class _GoToParagraphDialog extends StatefulWidget {
  const _GoToParagraphDialog({required this.animation, required this.count});

  final Animation<double> animation;
  final int count;

  @override
  State<_GoToParagraphDialog> createState() => _GoToParagraphDialogState();
}

class _GoToParagraphDialogState extends State<_GoToParagraphDialog> {
  final _number = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  int? get _value {
    final n = int.tryParse(_number.text.trim());
    if (n == null || n < 1 || n > widget.count) return null;
    return n;
  }

  void _confirm() {
    final n = _value;
    if (n != null) Navigator.of(context).pop(n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = l10n.notesGoToParagraphField(widget.count);
    final valid = _value != null;
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.notesGoToParagraphTitle,
      subtitle: label,
      fields: [
        // Digits read left to right in every language.
        Directionality(
          textDirection: TextDirection.ltr,
          child: WpTextField(
            testId: 'notes-goto-field',
            key: const ValueKey('notes-goto-field'),
            controller: _number,
            variant: WpTextFieldVariant.form,
            hintText: '1',
            semanticsLabel: label,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'notes-goto-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: l10n.notesGoToParagraphConfirm,
          testId: 'notes-goto-confirm',
          role: WpDialogActionRole.primary,
          enabled: valid,
          onPressed: valid ? _confirm : null,
        ),
      ],
    );
  }
}
