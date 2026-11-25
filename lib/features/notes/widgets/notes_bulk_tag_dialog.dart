import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_text_field.dart';

/// Asks for the tag to add to [count] selected notes (multi-select, #655).
/// Returns the trimmed tag name, or null when cancelled. The Textbausteine
/// page asks the same question (#662) with its own [title] and [idPrefix]
/// (`<idPrefix>-field`, `-cancel`, `-confirm`).
Future<String?> showNotesBulkTagDialog(
  BuildContext context, {
  required int count,
  String? title,
  String idPrefix = 'notes-bulk-tag',
}) => showWpFormDialog<String>(
  context: context,
  builder: (context, animation) => _NotesBulkTagDialog(
    animation: animation,
    count: count,
    title: title,
    idPrefix: idPrefix,
  ),
);

class _NotesBulkTagDialog extends StatefulWidget {
  const _NotesBulkTagDialog({
    required this.animation,
    required this.count,
    required this.title,
    required this.idPrefix,
  });

  final Animation<double> animation;
  final int count;
  final String? title;
  final String idPrefix;

  @override
  State<_NotesBulkTagDialog> createState() => _NotesBulkTagDialogState();
}

class _NotesBulkTagDialogState extends State<_NotesBulkTagDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final valid = _name.text.trim().isNotEmpty;
    return WpFormDialogShell(
      animation: widget.animation,
      title: widget.title ?? l10n.notesBulkTagTitle(widget.count),
      subtitle: l10n.notesAddTag,
      fields: [
        WpTextField(
          testId: '${widget.idPrefix}-field',
          key: ValueKey('${widget.idPrefix}-field'),
          controller: _name,
          variant: WpTextFieldVariant.form,
          hintText: l10n.notesTagPlaceholder,
          semanticsLabel: l10n.notesAddTag,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
        ),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: '${widget.idPrefix}-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: l10n.notesAddTag,
          testId: '${widget.idPrefix}-confirm',
          role: WpDialogActionRole.primary,
          enabled: valid,
          onPressed: valid ? _confirm : null,
        ),
      ],
    );
  }
}
