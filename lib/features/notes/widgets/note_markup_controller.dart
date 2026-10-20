/// Editor controller that paints `==marks==` of a note (WP-31a).
///
/// The marks stay plain text in the body, so the stored note and its export
/// are unchanged; only the painting differs. While a find query has matches
/// the find highlight takes precedence, because it answers the question the
/// user is asking right now.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../widgets/find_replace.dart';
import '../data/note_highlight_markup.dart';

class NoteMarkupController extends WpFindHighlightController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = withComposing && value.isComposingRangeValid;
    final spans = findMatches.isNotEmpty || composing
        ? const <NoteHighlightSpan>[]
        : noteHighlightSpans(value.text);
    if (spans.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final text = value.text;
    final markerStyle = TextStyle(color: WpColors.textMuted);
    final markedStyle = TextStyle(
      backgroundColor: WpColors.highlightSoft,
      color: WpColors.highlightText,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final span in spans) {
      if (span.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, span.start)));
      }
      children
        ..add(
          TextSpan(
            text: text.substring(span.start, span.innerStart),
            style: markerStyle,
          ),
        )
        ..add(
          TextSpan(
            text: text.substring(span.innerStart, span.innerEnd),
            style: markedStyle,
          ),
        )
        ..add(
          TextSpan(
            text: text.substring(span.innerEnd, span.end),
            style: markerStyle,
          ),
        );
      cursor = span.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }
}

/// Wraps the selected text of [controller] in `==` marks.
///
/// Returns `false` and changes nothing when the selection is empty, spans a
/// line break, or already contains `=`, since any of those would not form a
/// mark the painter can read back.
bool wrapSelectionInHighlight(TextEditingController controller) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return false;
  final inner = selection.textInside(value.text);
  if (inner.contains('\n') || inner.contains('=')) return false;

  final before = value.text.substring(0, selection.start);
  final after = value.text.substring(selection.end);
  final wrapped = '$before==$inner==$after';
  controller.value = TextEditingValue(
    text: wrapped,
    selection: TextSelection.collapsed(offset: selection.end + 4),
  );
  return true;
}
