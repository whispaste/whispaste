import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_text_field.dart';

/// Asks for the tag to add to [count] selected notes (multi-select, #655).
/// Returns the trimmed tag name, or null when cancelled.
Future<String?> showNotesBulkTagDialog(
  BuildContext context, {
  required int count,
}) => showWpFormDialog<String>(
  context: context,
  builder: (context, animation) =>
      _NotesBulkTagDialog(animation: animation, count: count),
);

class _NotesBulkTagDialog extends StatefulWidget {
  const _NotesBulkTagDialog({required this.animation, required this.count});

  final Animation<double> animation;
  final int count;

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
      title: l10n.notesBulkTagTitle(widget.count),
      subtitle: l10n.notesAddTag,
      fields: [
        Semantics(
          identifier: 'notes-bulk-tag-field',
          child: WpTextField(
            key: const ValueKey('notes-bulk-tag-field'),
            controller: _name,
            variant: WpTextFieldVariant.form,
            hintText: l10n.notesTagPlaceholder,
            semanticsLabel: l10n.notesAddTag,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'notes-bulk-tag-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: l10n.notesAddTag,
          testId: 'notes-bulk-tag-confirm',
          role: WpDialogActionRole.primary,
          enabled: valid,
          onPressed: valid ? _confirm : null,
        ),
      ],
    );
  }
}
