/// Editable title of the open note (ticket).
///
/// Saves after a short pause, on Enter, and when the field goes away — the
/// last one matters when the user switches notes straight after typing. The
/// field is keyed per note by the panel, so its text never leaks across notes.
///
/// At rest the title is plain heading text that takes the row's free width
/// and ends in an ellipsis, the way History's entry title reads (#1498). One
/// click or Enter on it opens the edit field in the same style and place, so
/// the words never move; leaving the field returns to the plain title.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';
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
  final FocusNode _restFocus = FocusNode(debugLabel: 'notes-title-rest');
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'notes-title-field');
  Timer? _timer;
  bool _dirty = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _fieldFocus.addListener(_onFieldFocus);
  }

  void _startEditing() {
    if (_editing) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldFocus.requestFocus();
      // Caret at the end, like a click behind the last word.
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _onFieldFocus() {
    if (_fieldFocus.hasFocus || !_editing) return;
    _save();
    setState(() => _editing = false);
  }

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
    _fieldFocus.removeListener(_onFieldFocus);
    _fieldFocus.dispose();
    _restFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (_editing) {
      return Semantics(
        label: l10n.notesTitleLabel,
        textField: true,
        identifier: 'notes-editor-title',
        child: WpTextField(
          key: const ValueKey('notes-editor-title'),
          controller: _controller,
          focusNode: _fieldFocus,
          variant: WpTextFieldVariant.heading,
          semanticsLabel: l10n.notesTitleLabel,
          hintText: widget.hintText,
          onChanged: _onChanged,
          onSubmitted: (_) {
            _save();
            _restFocus.requestFocus();
          },
        ),
      );
    }
    final empty = _controller.text.trim().isEmpty;
    // Same style and inset as the edit field, so opening it never shifts or
    // resizes the title.
    final style = WpTextField.styleFor(
      WpTextFieldVariant.heading,
      color: empty ? WpColors.textMuted : WpColors.textPrimary,
    );
    return Semantics(
      label: l10n.notesTitleLabel,
      value: empty ? null : _controller.text,
      button: true,
      identifier: 'notes-editor-title',
      excludeSemantics: true,
      onTap: _startEditing,
      child: WpFocusRing(
        focusNode: _restFocus,
        radius: WpRadius.sm,
        child: InkWell(
          key: const ValueKey('notes-editor-title'),
          focusNode: _restFocus,
          onTap: _startEditing,
          borderRadius: WpRadius.borderSm,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          mouseCursor: SystemMouseCursors.text,
          child: Padding(
            padding: WpTextField.headingContentPadding,
            child: Text(
              empty ? widget.hintText : _controller.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}
