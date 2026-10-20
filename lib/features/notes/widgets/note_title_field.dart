/// Editable title of the open note (WP-31a).
///
/// Saves after a short pause, on Enter, and when the field goes away — the
/// last one matters when the user switches notes straight after typing. The
/// field is keyed per note by the panel, so its text never leaks across notes.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/wp_text_field.dart';

const Duration _titleSaveDelay = Duration(milliseconds: 600);

class NoteTitleField extends StatefulWidget {
  const NoteTitleField({
    super.key,
    required this.noteId,
    required this.initialTitle,
    required this.hintText,
    required this.onSave,
  });

  final String noteId;
  final String? initialTitle;

  /// Shown while the title is empty: the first content line the list would
  /// use as the title instead.
  final String hintText;

  /// Persists the trimmed-or-raw text for [noteId]. Blank text clears the
  /// explicit title, so the derived one is used again.
  final void Function(String noteId, String title) onSave;

  @override
  State<NoteTitleField> createState() => _NoteTitleFieldState();
}

class _NoteTitleFieldState extends State<NoteTitleField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle ?? '',
  );
  Timer? _timer;
  bool _dirty = false;

  void _onChanged(String _) {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(_titleSaveDelay, _save);
  }

  void _save() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    _dirty = false;
    widget.onSave(widget.noteId, _controller.text);
  }

  @override
  void dispose() {
    if (_dirty) {
      _timer?.cancel();
      widget.onSave(widget.noteId, _controller.text);
    }
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.notesTitleLabel,
      textField: true,
      identifier: 'notes-editor-title',
      child: WpTextField(
        key: const ValueKey('notes-editor-title'),
        controller: _controller,
        variant: WpTextFieldVariant.heading,
        semanticsLabel: l10n.notesTitleLabel,
        hintText: widget.hintText,
        onChanged: _onChanged,
        onSubmitted: (_) => _save(),
      ),
    );
  }
}
