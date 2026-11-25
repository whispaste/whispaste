/// Editor controller that paints `==marks==` of a note (ticket).
///
/// The marks stay plain text in the body, so the stored note and its export
/// are unchanged; only the painting differs. While a find query has matches
/// the find highlight takes precedence, because it answers the question the
/// user is asking right now.
///
/// In focus mode with paragraph focus on (#669) every paragraph but the one
/// holding the caret is painted dimmed, on top of marks and find tints.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../widgets/find_replace.dart';
import '../data/note_highlight_markup.dart';
import '../data/writing_focus.dart';

class NoteMarkupController extends WpFindHighlightController {
  // buildTextSpan runs on every caret move and frame; the marks only change
  // with the text, so they are scanned once per text (#640, interim measure
  // until the block architecture of #627).
  String? _spansText;
  List<NoteHighlightSpan> _spans = const [];

  List<NoteHighlightSpan> _spansFor(String text) {
    if (!identical(text, _spansText) && text != _spansText) {
      _spansText = text;
      _spans = noteHighlightSpans(text);
    }
    return _spans;
  }

  bool _paragraphFocus = false;

  /// Whether every paragraph but the caret's is painted dimmed (#669).
  bool get paragraphFocus => _paragraphFocus;
  set paragraphFocus(bool value) {
    if (value == _paragraphFocus) return;
    _paragraphFocus = value;
    // Repaint only; listeners that react to edits compare the text.
    notifyListeners();
  }

  @override
  TextSpan buildDecoratedTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = _buildMarked(
      context: context,
      style: style,
      withComposing: withComposing,
    );
    final selection = value.selection;
    // Mid-composition the composing underline matters more than the dimming.
    if (!_paragraphFocus ||
        !selection.isValid ||
        (withComposing && value.isComposingRangeValid)) {
      return span;
    }
    final text = value.text;
    final lit = focusParagraphRange(text, selection.extentOffset);
    if (lit.start <= 0 && lit.end >= text.length) return span;
    return dimOutsideRange(
      span,
      lit,
      TextStyle(color: WpColors.textMuted.withValues(alpha: dimmedAlpha)),
    );
  }

  /// Opacity of the dimmed paragraphs' muted text colour.
  static const double dimmedAlpha = 0.55;

  TextSpan _buildMarked({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = withComposing && value.isComposingRangeValid;
    final spans = findMatches.isNotEmpty || composing
        ? const <NoteHighlightSpan>[]
        : _spansFor(value.text);
    if (spans.isEmpty) {
      return super.buildDecoratedTextSpan(
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

/// [span] (a root span with plain text children, as the painters of this
/// controller build it) with [dim] merged into every part outside [lit].
/// Any other shape is returned unchanged.
TextSpan dimOutsideRange(TextSpan span, TextRange lit, TextStyle dim) {
  final root = span.text;
  final pieces = <(String, TextStyle?)>[?(root == null ? null : (root, null))];
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is! TextSpan || child.children != null || child.text == null) {
      return span;
    }
    pieces.add((child.text!, child.style));
  }
  final out = <InlineSpan>[];
  var offset = 0;
  for (final (text, style) in pieces) {
    final cuts = <int>{
      0,
      (lit.start - offset).clamp(0, text.length),
      (lit.end - offset).clamp(0, text.length),
      text.length,
    }.toList()..sort();
    for (var i = 0; i + 1 < cuts.length; i++) {
      final from = cuts[i];
      final to = cuts[i + 1];
      final inside = offset + from >= lit.start && offset + to <= lit.end;
      out.add(
        TextSpan(
          text: text.substring(from, to),
          style: inside ? style : (style?.merge(dim) ?? dim),
        ),
      );
    }
    offset += text.length;
  }
  return TextSpan(style: span.style, children: out);
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
