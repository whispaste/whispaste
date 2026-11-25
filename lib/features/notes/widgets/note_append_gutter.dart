/// The margin marks beside a quick note's text (#803): one small mark at the
/// first line of every dictation the quick-note hotkey appended, with the
/// moment it was appended as tooltip. The note text itself stays clean.
///
/// The gutter lies over the editor's left inset (the bare field's 24 dp
/// padding), so a note with marks keeps exactly the text layout of a note
/// without: nothing shifts when the first dictation arrives. Positions come
/// from the field's own text layout ([RenderEditable.getLocalRectForCaret]),
/// so they follow wrapping, resizing and scrolling instead of guessing line
/// heights.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, ViewportOffset;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/note_append_marks.dart';
import '../data/notes_actions.dart';

/// Width of the mark itself; the hit area spans the whole gutter.
const double _markWidth = 3;

class NoteAppendGutter extends ConsumerStatefulWidget {
  const NoteAppendGutter({
    super.key,
    required this.noteId,
    required this.controller,
    required this.focusNode,
  });

  final String noteId;
  final TextEditingController controller;

  /// The editor's focus node: its context sits inside the field's
  /// [EditableText], which is how the gutter reaches the text layout.
  final FocusNode focusNode;

  @override
  ConsumerState<NoteAppendGutter> createState() => _NoteAppendGutterState();
}

class _NoteAppendGutterState extends ConsumerState<NoteAppendGutter> {
  List<PlacedAppendMark> _placed = const [];
  List<({DateTime appendedAt, double top, double height})> _laidOut = const [];
  ViewportOffset? _listenedOffset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleLayout);
  }

  @override
  void didUpdateWidget(NoteAppendGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleLayout);
      widget.controller.addListener(_scheduleLayout);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleLayout);
    _listenedOffset?.removeListener(_scheduleLayout);
    super.dispose();
  }

  void _scheduleLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _layoutMarks());
  }

  RenderEditable? _editable() {
    final focusContext = widget.focusNode.context;
    if (focusContext == null || !focusContext.mounted) return null;
    return focusContext
        .findAncestorStateOfType<EditableTextState>()
        ?.renderEditable;
  }

  void _layoutMarks() {
    if (!mounted) return;
    final editable = _editable();
    final gutterBox = context.findRenderObject() as RenderBox?;
    if (editable == null ||
        !editable.attached ||
        !editable.hasSize ||
        gutterBox == null ||
        !gutterBox.hasSize) {
      return;
    }
    if (_listenedOffset != editable.offset) {
      _listenedOffset?.removeListener(_scheduleLayout);
      _listenedOffset = editable.offset..addListener(_scheduleLayout);
    }
    final textLength = widget.controller.text.length;
    final scroll = editable.offset.hasPixels ? editable.offset.pixels : 0.0;
    final next = <({DateTime appendedAt, double top, double height})>[];
    for (final mark in _placed) {
      if (mark.offset > textLength) continue;
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: mark.offset),
      );
      final top = gutterBox
          .globalToLocal(editable.localToGlobal(Offset(0, caret.top - scroll)))
          .dy;
      next.add((appendedAt: mark.appendedAt, top: top, height: caret.height));
    }
    if (!_sameLayout(next, _laidOut)) setState(() => _laidOut = next);
  }

  static bool _sameLayout(
    List<({DateTime appendedAt, double top, double height})> a,
    List<({DateTime appendedAt, double top, double height})> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // #661: append rows are kept for every style (they mark a note as one
    // with quick-note dictations); the margin shows them only when the
    // timestamp style asks for margin marks.
    final showMarks = ref.watch(
      settingsProvider.select(
        (s) => (s.value ?? AppSettings.defaults)
            .quickNoteHotkey
            .timestampStyle
            .recordsMarginMark,
      ),
    );
    final appends = showMarks
        ? ref.watch(noteAppendsProvider(widget.noteId)).value ?? const []
        : const <NoteAppend>[];
    final placed = placeAppendMarks(widget.controller.text, [
      for (final a in appends) (anchor: a.anchor, appendedAt: a.appendedAt),
    ]);
    _placed = placed;
    // Every build may follow a resize or a new mark: measure again after it.
    _scheduleLayout();
    if (_laidOut.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Semantics(
      identifier: 'notes-editor-append-gutter',
      container: true,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final (i, mark) in _laidOut.indexed)
              Positioned(
                left: 0,
                right: 0,
                top: mark.top,
                height: mark.height,
                child: _AppendMark(
                  index: i,
                  label: l10n.notesEditorAppendMarkLabel(
                    _formatMoment(mark.appendedAt, locale),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatMoment(DateTime at, String locale) {
    try {
      return DateFormat.MMMd(locale).add_Hm().format(at.toLocal());
    } on Object {
      // Locale data not loaded: an unambiguous fallback beats no tooltip.
      return DateFormat('yyyy-MM-dd HH:mm').format(at.toLocal());
    }
  }
}

class _AppendMark extends StatelessWidget {
  const _AppendMark({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'notes-editor-append-mark-$index',
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Center(
          child: Container(
            key: ValueKey('notes-editor-append-mark-$index'),
            width: _markWidth,
            margin: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
            decoration: BoxDecoration(
              color: WpColors.accent,
              borderRadius: BorderRadius.circular(_markWidth),
            ),
          ),
        ),
      ),
    );
  }
}
