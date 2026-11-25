/// The body editor for very long notes (#641, ADR 0035).
///
/// A single text field lays out the whole note on every keystroke, which
/// stops being usable somewhere past 50,000 words. This editor shows the note
/// as a list of rows ([NoteRows]) and builds only the rows near the viewport;
/// exactly one row at a time is a real text field, the others are plain text
/// in the same style, so switching rows does not move a single line.
///
/// The page's controller stays the one source of the text. Every edit in the
/// active row is written straight back into it, so autosave, dictation at the
/// caret, find-and-replace, formatting and export work on the full text the
/// same way they do with the single field. Selections that span rows live
/// only in that controller and are painted into the plain rows.
///
/// Heading sections fold (#1344): a fold only hides rows (height 0, out of
/// the semantics tree), the text and every operation on it stay whole. The
/// caret, the active find hit and a jump never rest in a hidden row: the
/// sections around it open.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/config/command_shortcut.dart';
import '../../../core/l10n/generated/app_localizations.dart';

import '../../../core/data/editor_view_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/editor_smart_action_scope.dart';
import '../../../widgets/editor_spell_check.dart';
import '../../../widgets/editor_text_view_scope.dart';
import '../../../widgets/find_replace.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_editor_view_memory.dart';
import '../../../widgets/wp_text_field.dart';
import '../blocks/long_note_layout.dart';
import '../../../core/text/text_undo.dart';
import '../data/note_highlight_markup.dart';
import '../blocks/block_document.dart';
import '../blocks/note_folds.dart';
import 'note_fold_controller.dart';
import 'note_markup_controller.dart';

class LongNoteEditor extends StatefulWidget {
  const LongNoteEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.scrollToEnd,
    this.semanticsLabel,
    this.readOnly = false,
    this.folds,
  });

  /// The page's controller holding the full note text.
  final WpFindHighlightController controller;

  /// Focus of the editor as a whole: requesting it puts the caret into the
  /// active row, and it reports focus while that row has it.
  final FocusNode focusNode;

  /// Fires when the page wants the end of the note in view (after appending).
  final Listenable? scrollToEnd;

  final String? semanticsLabel;

  final bool readOnly;

  /// The page's handle for folding all sections from the editor menu.
  final NoteFoldController? folds;

  /// Width of the column of fold buttons left of the text, shown while the
  /// note has a section to fold.
  static const double foldGutter = WpIconButton.compactExtent;

  /// Folds or unfolds the section at the caret.
  static SingleActivator get foldSectionActivator =>
      commandActivator(LogicalKeyboardKey.keyK, shift: true);

  /// Folds all sections, or unfolds them when any is folded.
  static SingleActivator get foldAllActivator =>
      commandActivator(LogicalKeyboardKey.keyO, shift: true);

  /// Rows built beyond the viewport, above and below. They stay in the
  /// semantics tree (hidden), so a screen reader reads on across the edge of
  /// the window without waiting for a scroll.
  static const double bufferExtent = 1500;

  @override
  State<LongNoteEditor> createState() => LongNoteEditorState();
}

class LongNoteEditorState extends State<LongNoteEditor>
    implements WpEditorViewAnchor, NoteFoldTarget {
  late NoteRows _rows;

  /// Heading sections of [_rows], the folded ones by ordinal, and which rows
  /// they hide (#1344).
  late NoteSections _sections;
  Set<int> _folded = {};
  List<bool> _hidden = const [];
  final ValueNotifier<int> _foldChanges = ValueNotifier(0);

  /// Start of the active find hit last opened, so it opens only once.
  int? _revealedHit;
  late final Listenable _viewChanges = Listenable.merge([
    _scroll,
    _foldChanges,
  ]);
  final HeightIndex _heights = HeightIndex();
  final ScrollController _scroll = ScrollController();

  int _active = 0;
  late NoteMarkupController _local;
  late UndoHistoryController _undo;
  late FocusNode _fieldFocus;

  /// Whether the editor or one of its paragraphs has the keyboard focus.
  bool _hasFocus = false;
  GlobalKey _fieldKey = GlobalKey();

  /// Text of the active row as last written to or read from [_local].
  String _segment = '';

  /// Text of the page controller the rows were taken from.
  String _text = '';

  /// A selection spanning more than one row, or null.
  TextSelection? _cross;

  bool _applyingLocal = false;
  bool _syncingLocal = false;
  bool _relayoutScheduled = false;
  bool _deferredReparse = false;

  /// Only when the page brought no shared history (#651).
  TextUndoController? _ownHistory;
  final Map<int, GlobalKey> _rowKeys = {};
  final GlobalKey _viewportKey = GlobalKey();
  Offset? _pointerStart;
  Offset? _pointerPosition;
  int? _dragAnchor;
  bool _dragging = false;
  Timer? _dragTimer;
  HeightAnchor? _pendingAnchor;

  static const double _fontSize = WpTypography.heading;

  WpFindHighlightController get _master => widget.controller;

  @visibleForTesting
  NoteRows get rows => _rows;

  @visibleForTesting
  int get activeRow => _active;

  @visibleForTesting
  HeightIndex get heights => _heights;

  @visibleForTesting
  ScrollController get scrollController => _scroll;

  @visibleForTesting
  Set<int> get folded => Set.unmodifiable(_folded);

  @visibleForTesting
  bool isRowHidden(int row) => row < _hidden.length && _hidden[row];

  @override
  void initState() {
    super.initState();
    _text = _master.text;
    _adoptHistory();
    _rows = NoteRows.of(_text);
    _sections = NoteSections.of(_rows);
    _hidden = List.filled(_rows.length, false);
    widget.folds?.attach(this);
    _master.addListener(_onMaster);
    widget.scrollToEnd?.addListener(_onScrollToEnd);
    widget.focusNode.addListener(_onOuterFocus);
    final sel = _master.selection;
    final row = sel.isValid ? _rows.segmentOf(_clamp(sel.extentOffset)) : 0;
    _install(row, sel.isValid ? sel : null);
    _cross = _spansRows(sel) ? sel : null;
  }

  @override
  void didUpdateWidget(LongNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onMaster);
      _ownHistory?.dispose();
      _ownHistory = null;
      _adoptHistory();
      _master.addListener(_onMaster);
      _onMaster();
    }
    if (oldWidget.scrollToEnd != widget.scrollToEnd) {
      oldWidget.scrollToEnd?.removeListener(_onScrollToEnd);
      widget.scrollToEnd?.addListener(_onScrollToEnd);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onOuterFocus);
      widget.focusNode.addListener(_onOuterFocus);
    }
    if (oldWidget.folds != widget.folds) {
      oldWidget.folds?.detach(this);
      widget.folds?.attach(this);
    }
  }

  @override
  void dispose() {
    _dragTimer?.cancel();
    widget.folds?.detach(this);
    _foldChanges.dispose();
    _master.removeListener(_onMaster);
    widget.scrollToEnd?.removeListener(_onScrollToEnd);
    widget.focusNode.removeListener(_onOuterFocus);
    _local
      ..removeListener(_onLocal)
      ..clearFindHighlight(notify: false)
      ..dispose();
    _undo.dispose();
    _ownHistory?.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // A paragraph may span several rows; the remembered place counts
  // paragraphs and the pixels from the paragraph's first row (#678).
  @override
  Listenable get viewAnchorChanges => _viewChanges;

  @override
  ({int block, double offset})? captureViewAnchor() {
    if (!_scroll.hasClients || _heights.length == 0) return null;
    final pixels = _scroll.position.pixels;
    if (pixels <= 0) return (block: 0, offset: 0);
    final row = _heights.anchorAt(pixels).row;
    final block = EditorViewState.paragraphAt(_text, _rows.segmentStart(row));
    final first = _rows.segmentOf(EditorViewState.paragraphStart(_text, block));
    return (
      block: block,
      offset: math.max(0, pixels - _heights.offsetOf(first)),
    );
  }

  @override
  void restoreViewAnchor(int block, double offset) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final first = _rows.segmentOf(EditorViewState.paragraphStart(_text, block));
    final target = block <= 0 && offset <= 0
        ? 0.0
        : _heights.offsetOf(first.clamp(0, math.max(0, _heights.length - 1))) +
              offset;
    _pendingAnchor = null;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  // ---------------------------------------------------------------------------
  // Folding (#1344)
  // ---------------------------------------------------------------------------

  @override
  List<int> captureFolds() => _folded.toList()..sort();

  @override
  void restoreFolds(List<int> folded) {
    final next = _sections.valid(folded);
    final caret = _caretRow();
    if (caret != null) {
      next.removeAll(_sections.foldedAround(caret, next));
    }
    _setFolds(next);
    _parkCaretOutsideFolds();
  }

  @override
  bool get hasFoldableSections => _sections.hasFoldable;

  @override
  bool get hasFoldedSections => _folded.isNotEmpty;

  @override
  void foldAllSections() {
    final all = _sections.foldable;
    if (all.isEmpty) return;
    _setFolds(all);
    _parkCaretOutsideFolds();
    _say(L10n.of(context).notesFoldAllAnnounce);
  }

  @override
  void unfoldAllSections() {
    if (_sections.count == 0) return;
    _setFolds({});
    _say(L10n.of(context).notesUnfoldAllAnnounce);
  }

  /// Folds or unfolds [section] and says which way it went.
  void toggleSection(int section) {
    if (section >= _sections.count || !_sections.isFoldable(section)) return;
    final next = Set.of(_folded);
    final fold = !next.remove(section);
    if (fold) next.add(section);
    _setFolds(next);
    if (fold) _parkCaretOutsideFolds();
    final title = _headingTitle(section);
    final l10n = L10n.of(context);
    _say(
      fold
          ? l10n.notesFoldCollapsedAnnounce(title)
          : l10n.notesFoldExpandedAnnounce(title),
    );
  }

  /// The shortcut: the innermost section around the caret.
  void _toggleAtCaret() {
    final row = _caretRow() ?? _active;
    final section = _sections.innermostAt(row);
    if (section == null) {
      _say(L10n.of(context).notesFoldNothing);
      return;
    }
    toggleSection(section);
  }

  void _toggleAll() =>
      _folded.isEmpty ? foldAllSections() : unfoldAllSections();

  int? _caretRow() {
    final sel = _master.selection;
    if (!sel.isValid) return null;
    return _rows.segmentOf(_clamp(sel.extentOffset));
  }

  /// The heading's text without its `#` marks, for announcements.
  String _headingTitle(int section) {
    final row = _sections.headingRow(section);
    final text = _text.substring(_rows.startOf(row), _rows.endOf(row));
    return text.replaceFirst(RegExp(r'^ {0,3}#{1,6}[ \t]*'), '').trim();
  }

  void _setFolds(Set<int> folded) {
    final same = folded.length == _folded.length && folded.containsAll(_folded);
    _folded = folded;
    _applyFolds();
    if (same) return;
    _foldChanges.value++;
    widget.folds?.changed();
    if (mounted) setState(() {});
  }

  /// Recomputes the hidden rows from [_sections] and [_folded].
  void _applyFolds() {
    _hidden = _sections.hiddenRows(_folded, _rows.length);
    _heights.setHidden(_hidden);
  }

  /// A fold that swallowed the caret puts it at the end of the visible
  /// heading that now holds it.
  void _parkCaretOutsideFolds() {
    final caret = _caretRow();
    final row = caret ?? _active;
    if (!isRowHidden(row)) return;
    final section = _sections.outermostAround(row);
    if (section == null) return;
    var heading = _sections.headingRow(section);
    while (heading + 1 < _rows.length &&
        _rows.blockOf(heading + 1) == _rows.blockOf(heading)) {
      heading++;
    }
    if (caret == null) {
      _activate(heading);
      setState(() {});
      return;
    }
    _select(TextSelection.collapsed(offset: _rows.endOf(heading)));
  }

  /// Opens every folded section that hides [row]. Returns whether it did.
  bool _revealRow(int row) {
    if (!isRowHidden(row)) return false;
    final around = _sections.foldedAround(row, _folded);
    if (around.isEmpty) return false;
    _setFolds(Set.of(_folded)..removeAll(around));
    return true;
  }

  /// Nearest row before (or after) [row] that is not hidden, or null.
  int? _visibleRow(int row, {required bool forward}) {
    for (
      var r = row;
      forward ? r < _rows.length : r >= 0;
      forward ? r++ : r--
    ) {
      if (!isRowHidden(r)) return r;
    }
    return null;
  }

  void _say(String message) {
    if (!mounted) return;
    announce(View.of(context), message, Directionality.of(context));
  }

  int _clamp(int offset) => offset.clamp(0, _text.length);

  int get _segStart => _rows.segmentStart(_active);

  int get _segEnd => _rows.segmentEnd(_active, _text.length);

  bool _spansRows(TextSelection sel) {
    if (!sel.isValid || sel.isCollapsed) return false;
    final row = _rows.segmentOf(_clamp(sel.start));
    return _clamp(sel.end) > _rows.segmentEnd(row, _text.length);
  }

  // ---------------------------------------------------------------------------
  // Active row
  // ---------------------------------------------------------------------------

  /// Makes [row] the text field, with the part of [global] that falls into
  /// it as its selection.
  void _install(int row, TextSelection? global) {
    _active = row;
    final start = _segStart;
    final end = _segEnd;
    _segment = _text.substring(start, end);
    _local = NoteMarkupController()
      ..value = TextEditingValue(
        text: _segment,
        selection: _localSelection(global, start, end),
      )
      ..addListener(_onLocal);
    _undo = UndoHistoryController();
    _fieldFocus = FocusNode(debugLabel: 'long-note-row');
    _fieldKey = GlobalKey();
    _syncLocalFind();
  }

  TextSelection _localSelection(TextSelection? global, int start, int end) {
    if (global == null || !global.isValid) {
      return const TextSelection.collapsed(offset: 0);
    }
    int local(int offset) => (offset - start).clamp(0, end - start);
    return TextSelection(
      baseOffset: local(global.baseOffset),
      extentOffset: local(global.extentOffset),
      affinity: global.affinity,
    );
  }

  /// Switches the field to [row]. The old controllers go after this frame:
  /// the field still holding them unmounts only then.
  void _activate(int row, {TextSelection? global, bool focus = false}) {
    final hadFocus = _fieldFocus.hasFocus;
    final oldLocal = _local..removeListener(_onLocal);
    final oldUndo = _undo;
    final oldFocus = _fieldFocus;
    _install(row, global);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldLocal
        ..clearFindHighlight(notify: false)
        ..dispose();
      oldUndo.dispose();
      oldFocus.dispose();
      if (mounted && (hadFocus || focus)) _fieldFocus.requestFocus();
    });
  }

  /// Edits in the active row go straight into the page's controller.
  void _onLocal() {
    if (_syncingLocal) return;
    final value = _local.value;
    final start = _segStart;
    TextSelection shift(TextSelection s) => s.isValid
        ? s.copyWith(
            baseOffset: s.baseOffset + start,
            extentOffset: s.extentOffset + start,
          )
        : s;

    if (value.text == _segment && !_deferredReparse) {
      if (_dragging) return;
      final selection = shift(value.selection);
      final hadCross = _cross != null;
      _cross = null;
      final composing = _globalComposing(value.composing, start);
      if (selection != _master.selection ||
          composing != _master.value.composing) {
        _applyingLocal = true;
        _master.value = _master.value.copyWith(
          selection: selection,
          composing: composing,
        );
        _applyingLocal = false;
      }
      if (hadCross) setState(() {});
      return;
    }

    final old = _segment;
    final end = _segEnd;
    final oldText = _text;
    final text = _text.replaceRange(start, end, value.text);
    final composing = _globalComposing(value.composing, start);
    _segment = value.text;
    _text = text;
    _cross = null;
    _applyingLocal = true;
    _master.value = TextEditingValue(
      text: text,
      selection: shift(value.selection),
      composing: composing,
    );
    _applyingLocal = false;

    final composingNow = composing.isValid && !composing.isCollapsed;
    final changesShape = _deferredReparse || _changesShape(old, value.text);
    if (changesShape && !composingNow) {
      _deferredReparse = false;
      _reparse(oldText);
      final caret = _master.selection.isValid
          ? _clamp(_master.selection.extentOffset)
          : start;
      final row = _rows.segmentOf(caret);
      if (row != _active ||
          _rows.segmentStart(row) != start ||
          _rows.segmentEnd(row, _text.length) != start + _segment.length) {
        _activate(row, global: _master.selection);
      } else {
        _syncLocalFind();
      }
    } else {
      _deferredReparse = changesShape;
      final grown = _rows.lengthOf(_active) + value.text.length - old.length;
      _rows.resize(_active, grown);
      _heights.reestimate(_rows, _active, _fontSize);
      _syncLocalFind();
    }
    setState(() {});
  }

  TextRange _globalComposing(TextRange range, int start) => range.isValid
      ? TextRange(start: range.start + start, end: range.end + start)
      : TextRange.empty;

  /// Undo spans the whole document and lives on the page's controller, so
  /// it survives switching between the short and the long editor.
  void _adoptHistory() {
    if (TextUndoController.of(_master) == null) {
      _ownHistory = TextUndoController(_master);
    }
  }

  void _restoreEdit({required bool redo}) {
    final history = TextUndoController.of(_master);
    if (widget.readOnly || history == null) return;
    redo ? history.redo() : history.undo();
    _focusSoon();
  }

  /// Whether an edit from [old] to [now] in the active segment can change
  /// the rows: a line break added or removed, typing at the start of the row
  /// (heading and list marks), outside the row's own text, or a row grown far
  /// past the display split.
  bool _changesShape(String old, String now) {
    var prefix = 0;
    final common = math.min(old.length, now.length);
    while (prefix < common &&
        old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < common - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            now.codeUnitAt(now.length - 1 - suffix)) {
      suffix++;
    }
    final removed = old.substring(prefix, old.length - suffix);
    final inserted = now.substring(prefix, now.length - suffix);
    if (removed.contains('\n') || inserted.contains('\n')) return true;
    final rowStart = _rows.startOf(_active) - _segStart;
    final rowEnd = rowStart + _rows.lengthOf(_active);
    if (prefix < rowStart + 7) return true;
    if (old.length - suffix > rowEnd) return true;
    final grown = _rows.lengthOf(_active) + now.length - old.length;
    return grown > 2 * BlockDocument.softSplitChars;
  }

  void _reparse(String oldText) {
    final old = _rows;
    _rows = NoteRows.of(_text);
    _heights.rebase(old, _rows, _fontSize);
    final hadSections = _sections.count > 0 || _folded.isNotEmpty;
    _sections = NoteSections.of(_rows);
    final before = _folded;
    _folded = carryFolds(
      folded: _folded,
      oldText: oldText,
      oldRows: old,
      newText: _text,
      newRows: _rows,
    ).toSet();
    _applyFolds();
    if (hadSections || _sections.count > 0) widget.folds?.changed();
    if (before.length != _folded.length || !before.containsAll(_folded)) {
      _foldChanges.value++;
    }
  }

  /// Changes made on the page's controller from outside: dictation, find,
  /// formatting, switching notes, "Go to paragraph".
  /// Whether the paragraph focus of focus mode dims all rows but the
  /// active one (#669); the flag lives on the page's controller.
  bool get _wantsDim =>
      _master is NoteMarkupController &&
      (_master as NoteMarkupController).paragraphFocus;
  late bool _dimmed = _wantsDim;

  void _onMaster() {
    if (_applyingLocal) return;
    if (_wantsDim != _dimmed) setState(() => _dimmed = _wantsDim);
    final text = _master.text;
    final textChanged = !identical(text, _text) && text != _text;
    if (textChanged) {
      _deferredReparse = false;
      final oldText = _text;
      _text = text;
      _reparse(oldText);
    }
    final sel = _master.selection;
    // A caret (dictation, a jump, a replace) or the active find hit in a
    // folded section opens it (#1344).
    final matches = _master.findMatches;
    final hit = _master.activeFindIndex;
    final hitStart = hit >= 0 && hit < matches.count
        ? matches.starts[hit]
        : null;
    if (_folded.isNotEmpty) {
      // A selection across rows (Select all, say) keeps the folds: copying
      // it takes the folded text along anyway.
      if (sel.isValid && !_spansRows(sel)) {
        _revealRow(_rows.segmentOf(_clamp(sel.extentOffset)));
      }
      // Only a hit that just became active: folding its section again
      // while the find bar stays open is the user's choice.
      if (hitStart != null && hitStart != _revealedHit) {
        _revealRow(_rows.segmentOf(_clamp(hitStart)));
      }
    }
    _revealedHit = hitStart;
    final cross = _spansRows(sel) ? sel : null;
    final caret = sel.isValid ? _clamp(sel.extentOffset) : null;
    var row = caret == null
        ? math.min(_active, _rows.length - 1)
        : _rows.segmentOf(caret);
    if (row > 0 &&
        sel.affinity == TextAffinity.upstream &&
        caret == _rows.segmentEnd(row - 1, _text.length)) {
      row--;
    }
    final crossChanged = cross != _cross;
    final rowChanged = row != _active;
    _cross = cross;
    if (textChanged || rowChanged) {
      _activate(row, global: sel.isValid ? sel : null);
    } else {
      final local = _localSelection(sel, _segStart, _segEnd);
      if (sel.isValid && local != _local.selection) {
        _syncingLocal = true;
        _local.selection = local;
        _syncingLocal = false;
      }
      _syncLocalFind();
    }
    if (caret != null && (textChanged || crossChanged || rowChanged)) {
      _reveal(row);
    } else if (caret != null && !_fieldFocus.hasFocus) {
      _reveal(row);
    }
    setState(() {});
  }

  /// Hands the page's find highlight and spell-check underline to the
  /// active row, shifted into it.
  void _syncLocalFind() {
    final matches = _master.findMatches;
    _syncingLocal = true;
    if (matches.isEmpty) {
      _local.clearFindHighlight();
    } else {
      final start = _segStart;
      final end = _segEnd;
      final first = _lowerBound(matches.starts, start);
      final starts = <int>[];
      var active = -1;
      for (var i = first; i < matches.count; i++) {
        if (matches.endOf(i) > end) break;
        if (i == _master.activeFindIndex) active = starts.length;
        starts.add(matches.starts[i] - start);
      }
      _local.setFindHighlight(
        WpFindMatches(starts: starts, length: matches.length),
        active,
      );
    }
    // The spell-check underline (#670) only reaches the active row; the
    // plain rows around it paint without it.
    final start = _segStart;
    final end = _segEnd;
    _local.setSpellErrors([
      for (final r in _master.spellErrors)
        if (r.start >= start && r.end <= end)
          TextRange(start: r.start - start, end: r.end - start),
    ]);
    _syncingLocal = false;
  }

  static int _lowerBound(List<int> values, int target) {
    var lo = 0;
    var hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (values[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _onOuterFocus() {
    if (widget.focusNode.hasPrimaryFocus) _fieldFocus.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Selection and keys across rows
  // ---------------------------------------------------------------------------

  void _select(TextSelection selection) {
    final len = _text.length;
    _master.selection = selection.copyWith(
      baseOffset: selection.baseOffset.clamp(0, len),
      extentOffset: selection.extentOffset.clamp(0, len),
    );
  }

  void _replace(TextSelection range, String with_) {
    final start = _clamp(range.start);
    final end = _clamp(range.end);
    _master.value = TextEditingValue(
      text: _text.replaceRange(start, end, with_),
      selection: TextSelection.collapsed(offset: start + with_.length),
    );
  }

  RenderEditable? _editable() {
    final root = _fieldKey.currentContext?.findRenderObject();
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    if (root != null) visit(root);
    return found;
  }

  /// Whether the caret sits on the first (or last) visual line of the field.
  bool _caretOnEdgeLine({required bool first}) {
    final editable = _editable();
    final sel = _local.selection;
    if (editable == null || !sel.isValid) return true;
    Rect rect(int offset) =>
        editable.getLocalRectForCaret(TextPosition(offset: offset));
    final caret = rect(sel.extentOffset);
    final edge = rect(first ? 0 : _segment.length);
    return (caret.center.dy - edge.center.dy).abs() <
        editable.preferredLineHeight / 2;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final mod = defaultTargetPlatform == TargetPlatform.macOS
        ? keys.isMetaPressed
        : keys.isControlPressed;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    final len = _text.length;
    final last = _rows.length - 1;
    final master = _master.selection;
    final anchor = master.isValid ? master.baseOffset : 0;

    // Candidate navigation belongs to the IME. Delay splitting until commit
    // so a line break never destroys its active input client.
    if (_local.value.composing.isValid && !_local.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (mod &&
        (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyY)) {
      _restoreEdit(redo: key == LogicalKeyboardKey.keyY || shift);
      return KeyEventResult.handled;
    }

    if (LongNoteEditor.foldSectionActivator.accepts(event, keys)) {
      _toggleAtCaret();
      return KeyEventResult.handled;
    }
    if (LongNoteEditor.foldAllActivator.accepts(event, keys)) {
      _toggleAll();
      return KeyEventResult.handled;
    }

    if (mod && key == LogicalKeyboardKey.keyA) {
      _select(TextSelection(baseOffset: 0, extentOffset: len));
      return KeyEventResult.handled;
    }
    if (mod &&
        (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end)) {
      final to = key == LogicalKeyboardKey.home ? 0 : len;
      _select(
        shift
            ? TextSelection(baseOffset: anchor, extentOffset: to)
            : TextSelection.collapsed(offset: to),
      );
      return KeyEventResult.handled;
    }

    final cross = _cross;
    if (cross != null) return _onCrossKey(event, cross, mod: mod, shift: shift);

    if (mod || keys.isAltPressed) return KeyEventResult.ignored;
    final sel = _local.selection;
    if (!sel.isValid) return KeyEventResult.ignored;
    final extent = sel.extentOffset;
    final atStart = extent == 0;
    final atEnd = extent == _segment.length;
    final start = _segStart;
    final end = _segEnd;

    // Rows of a folded section are skipped (#1344): the row before or after
    // is the nearest visible one.
    final prev = _active > 0 ? _visibleRow(_active - 1, forward: false) : null;
    final next = _active < last
        ? _visibleRow(_active + 1, forward: true)
        : null;

    if (shift) {
      int? to;
      if (key == LogicalKeyboardKey.arrowLeft && atStart && prev != null) {
        to = prev == _active - 1
            ? _previousCharacter(start)
            : _rows.segmentEnd(prev, len);
      } else if (key == LogicalKeyboardKey.arrowRight &&
          atEnd &&
          next != null) {
        to = next == _active + 1
            ? _nextCharacter(end)
            : _rows.segmentStart(next);
      } else if (key == LogicalKeyboardKey.arrowUp &&
          _caretOnEdgeLine(first: true) &&
          prev != null) {
        to = _rows.segmentStart(prev);
      } else if (key == LogicalKeyboardKey.arrowDown &&
          _caretOnEdgeLine(first: false) &&
          next != null) {
        to = _rows.segmentEnd(next, len);
      }
      if (to == null) return KeyEventResult.ignored;
      _select(TextSelection(baseOffset: anchor, extentOffset: to));
      return KeyEventResult.handled;
    }

    if (!sel.isCollapsed) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft && atStart && prev != null) {
      _select(
        TextSelection.collapsed(
          offset: prev == _active - 1
              ? _previousCharacter(start)
              : _rows.segmentEnd(prev, len),
        ),
      );
    } else if (key == LogicalKeyboardKey.arrowRight && atEnd && next != null) {
      _select(
        TextSelection.collapsed(
          offset: next == _active + 1
              ? _nextCharacter(end)
              : _rows.segmentStart(next),
        ),
      );
    } else if (key == LogicalKeyboardKey.arrowUp &&
        prev != null &&
        _caretOnEdgeLine(first: true)) {
      _moveToRow(prev, atEnd: true);
    } else if (key == LogicalKeyboardKey.arrowDown &&
        next != null &&
        _caretOnEdgeLine(first: false)) {
      _moveToRow(next, atEnd: false);
    } else if (key == LogicalKeyboardKey.backspace &&
        atStart &&
        _active > 0 &&
        !widget.readOnly) {
      _replace(
        TextSelection(
          baseOffset: _previousCharacter(start),
          extentOffset: start,
        ),
        '',
      );
    } else if (key == LogicalKeyboardKey.delete &&
        atEnd &&
        _active < last &&
        !widget.readOnly) {
      _replace(
        TextSelection(baseOffset: end, extentOffset: _nextCharacter(end)),
        '',
      );
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// [offset] moved out of a folded section: to the end of the visible row
  /// before it, or the start of the one after it when moving [forward].
  int _outsideFolds(int offset, {required bool forward}) {
    final row = _rows.segmentOf(offset);
    if (!isRowHidden(row)) return offset;
    final visible = _visibleRow(row, forward: forward);
    if (visible == null) return offset;
    return forward
        ? _rows.segmentStart(visible)
        : _rows.segmentEnd(visible, _text.length);
  }

  int _previousCharacter(int offset) =>
      CharacterBoundary(_text).getLeadingTextBoundaryAt(offset - 1) ?? 0;

  int _nextCharacter(int offset) =>
      CharacterBoundary(_text).getTrailingTextBoundaryAt(offset) ??
      _text.length;

  void _moveToRow(int row, {required bool atEnd}) {
    final offset = atEnd
        ? _rows.segmentEnd(row, _text.length)
        : _rows.segmentStart(row);
    _select(
      TextSelection.collapsed(
        offset: offset,
        affinity: atEnd ? TextAffinity.upstream : TextAffinity.downstream,
      ),
    );
  }

  KeyEventResult _onCrossKey(
    KeyEvent event,
    TextSelection cross, {
    required bool mod,
    required bool shift,
  }) {
    final key = event.logicalKey;
    final len = _text.length;
    if (mod) {
      if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX) {
        final copied = _text.substring(_clamp(cross.start), _clamp(cross.end));
        unawaited(Clipboard.setData(ClipboardData(text: copied)));
        if (key == LogicalKeyboardKey.keyX && !widget.readOnly) {
          _replace(cross, '');
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV && !widget.readOnly) {
        unawaited(_pasteOver(cross));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final extent = cross.extentOffset;
    final row = _rows.segmentOf(extent);
    if (shift) {
      int? to;
      if (key == LogicalKeyboardKey.arrowLeft) {
        to = _outsideFolds(_previousCharacter(extent), forward: false);
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        to = _outsideFolds(_nextCharacter(extent), forward: true);
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        final top = _rows.segmentStart(row);
        final prev = row == 0 ? null : _visibleRow(row - 1, forward: false);
        to = extent > top || prev == null ? top : _rows.segmentStart(prev);
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        final bottom = _rows.segmentEnd(row, len);
        final next = row == _rows.length - 1
            ? null
            : _visibleRow(row + 1, forward: true);
        to = extent < bottom || next == null
            ? bottom
            : _rows.segmentEnd(next, len);
      }
      if (key == LogicalKeyboardKey.home) to = _rows.segmentStart(row);
      if (key == LogicalKeyboardKey.end) to = _rows.segmentEnd(row, len);
      if (to != null) {
        _select(TextSelection(baseOffset: cross.baseOffset, extentOffset: to));
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _select(TextSelection.collapsed(offset: cross.start));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _select(TextSelection.collapsed(offset: cross.end));
      return KeyEventResult.handled;
    }
    if (widget.readOnly) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _replace(cross, '');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _replace(cross, '\n');
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        !HardwareKeyboard.instance.isAltPressed &&
        character.codeUnitAt(0) >= 0x20 &&
        character.codeUnitAt(0) != 0x7f) {
      _replace(cross, character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pasteOver(TextSelection cross) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || _cross != cross) return;
    _replace(cross, text.replaceAll('\r\n', '\n'));
  }

  /// A click into a plain row puts the caret there (with Shift: extends the
  /// selection to it).
  void _tapRow(int row, int localOffset) {
    final offset = _rows.segmentStart(row) + localOffset;
    final sel = _master.selection;
    if (HardwareKeyboard.instance.isShiftPressed && sel.isValid) {
      _select(TextSelection(baseOffset: sel.baseOffset, extentOffset: offset));
    } else {
      _select(TextSelection.collapsed(offset: offset));
    }
    _focusSoon();
  }

  void _focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
  }

  // Track mouse selection in document offsets. Keep the input row mounted
  // throughout the gesture; otherwise replacing it cancels its drag recognizer.
  int? _offsetAt(Offset position) {
    int? nearest;
    var distance = double.infinity;
    for (final entry in _rowKeys.entries) {
      final context = entry.value.currentContext;
      final box = context?.findRenderObject();
      if (context == null || box is! RenderBox || !box.hasSize) continue;
      final local = box.globalToLocal(position);
      final dy = local.dy < 0
          ? -local.dy
          : math.max(0.0, local.dy - box.size.height);
      if (dy >= distance) continue;
      distance = dy;
      final row = entry.key;
      final paragraph = _PlainRow._paragraphOf(context);
      final editable = row == _active ? _editable() : null;
      final offset = editable != null
          ? editable.getPositionForPoint(position).offset
          : paragraph
                    ?.getPositionForOffset(paragraph.globalToLocal(position))
                    .offset ??
                0;
      nearest = (_rows.segmentStart(row) + offset).clamp(
        _rows.segmentStart(row),
        _rows.segmentEnd(row, _text.length),
      );
    }
    return nearest;
  }

  void _pointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _pointerStart = _pointerPosition = event.position;
    _dragAnchor =
        HardwareKeyboard.instance.isShiftPressed && _master.selection.isValid
        ? _master.selection.baseOffset
        : _offsetAt(event.position);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_pointerStart == null || _dragAnchor == null) return;
    _pointerPosition = event.position;
    if (!_dragging && (event.position - _pointerStart!).distance < kTouchSlop) {
      return;
    }
    _dragging = true;
    _updateDrag();
    _dragTimer ??= Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _scrollDrag(),
    );
  }

  void _updateDrag() {
    final offset = _offsetAt(_pointerPosition!);
    if (offset == null) return;
    final selection = TextSelection(
      baseOffset: _dragAnchor!,
      extentOffset: offset,
    );
    _applyingLocal = true;
    _master.selection = selection;
    _applyingLocal = false;
    _cross = selection;
    _syncingLocal = true;
    _local.selection = _localSelection(selection, _segStart, _segEnd);
    _syncingLocal = false;
    setState(() {});
  }

  void _scrollDrag() {
    if (!_dragging || !_scroll.hasClients) return;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.globalToLocal(_pointerPosition!).dy;
    final delta = y < 24
        ? y - 24
        : (y > box.size.height - 24 ? y - box.size.height + 24 : 0.0);
    if (delta == 0) return;
    final position = _scroll.position;
    _scroll.jumpTo(
      (_scroll.offset + delta.clamp(-60.0, 60.0)).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dragging) _updateDrag();
    });
  }

  void _pointerEnd(PointerEvent event) {
    _dragTimer?.cancel();
    _dragTimer = null;
    _pointerStart = _pointerPosition = null;
    _dragAnchor = null;
    if (!_dragging) return;
    _dragging = false;
    _onMaster();
    _focusSoon();
  }

  // ---------------------------------------------------------------------------
  // Scrolling
  // ---------------------------------------------------------------------------

  void _onScrollToEnd() => _reveal(_rows.length - 1, alignEnd: true);

  /// Brings [row] into view. Heights near the target are estimates until the
  /// rows are laid out, so the jump is corrected over the next frames.
  void _reveal(int row, {bool alignEnd = false, int attempts = 3}) {
    if (!_scroll.hasClients) {
      if (attempts > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? _reveal(row, alignEnd: alignEnd, attempts: 0) : null,
        );
      }
      return;
    }
    final position = _scroll.position;
    final target = row.clamp(0, _heights.length - 1);
    final top = _heights.offsetOf(target);
    final height = _heights.heightOf(target);
    final view = position.viewportDimension;
    final visible =
        top >= position.pixels && top + height <= position.pixels + view;
    if (!visible || alignEnd) {
      final to = alignEnd || (top > position.pixels && height < view)
          ? top + height - view
          : top;
      position.jumpTo(math.max(0, to));
    }
    if (attempts > 1) {
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (mounted) {
          _reveal(row, alignEnd: alignEnd, attempts: attempts - 1);
        }
      });
    }
  }

  void _onMeasured(int row, double height) {
    if (row >= _heights.length) return;
    if (_scroll.hasClients) {
      _pendingAnchor ??= _heights.anchorAt(_scroll.position.pixels);
    }
    if (_heights.measure(row, height)) _scheduleRelayout();
  }

  void _scheduleRelayout() {
    if (_relayoutScheduled) return;
    _relayoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _relayoutScheduled = false;
      final anchor = _pendingAnchor;
      _pendingAnchor = null;
      if (!mounted) return;
      setState(() {});
      if (anchor == null || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.isScrollingNotifier.value) return;
      final to = _heights.offsetFor(anchor);
      if ((to - position.pixels).abs() > 0.5) position.jumpTo(to);
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Line height chosen in the editor text view (#648), refreshed each
  /// build; rows and their estimates both read it.
  double _lineHeight = LayoutKey.defaultLineHeight;

  TextStyle get _style => WpTextField.styleFor(
    WpTextFieldVariant.bare,
    color: WpColors.textPrimary,
  ).copyWith(height: _lineHeight);

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    _lineHeight =
        WpEditorText.maybeOf(context)?.lineSpacing.factor ??
        LayoutKey.defaultLineHeight;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _pendingAnchor = null;
    return WpTextFieldSurface(
      variant: WpTextFieldVariant.bare,
      liftsOnHover: false,
      // The whole surface carries the focus contour while any paragraph is
      // edited, like the short note's field; the paragraph's own field draws
      // none (#1498).
      focused: _hasFocus,
      child: Actions(
        actions: {
          UndoTextIntent: CallbackAction<UndoTextIntent>(
            onInvoke: (_) => _restoreEdit(redo: false),
          ),
          RedoTextIntent: CallbackAction<RedoTextIntent>(
            onInvoke: (_) => _restoreEdit(redo: true),
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          skipTraversal: true,
          onKeyEvent: _onKey,
          onFocusChange: (focused) {
            if (mounted && focused != _hasFocus) {
              setState(() => _hasFocus = focused);
            }
          },
          child: Listener(
            key: _viewportKey,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerEnd,
            onPointerCancel: _pointerEnd,
            child: Semantics(
              identifier: 'notes-editor-long-list',
              label: widget.semanticsLabel,
              container: true,
              explicitChildNodes: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _gutter = _sections.hasFoldable
                      ? LongNoteEditor.foldGutter
                      : 0;
                  _linePx = scaler.scale(_fontSize) * _lineHeight;
                  final key = LayoutKey(
                    width: math.max(0, constraints.maxWidth - _gutter),
                    textScale: scaler.scale(_fontSize) / _fontSize,
                    devicePixelRatio: dpr,
                    lineHeight: _lineHeight,
                  );
                  final anchor = _scroll.hasClients && _heights.length > 0
                      ? _heights.anchorAt(_scroll.position.pixels)
                      : null;
                  if (_heights.ensureLayout(key, _rows, _fontSize) &&
                      anchor != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _scroll.hasClients) {
                        _scroll.jumpTo(_heights.offsetFor(anchor));
                      }
                    });
                  }
                  return ListView.builder(
                    key: const ValueKey('notes-editor-long-list'),
                    controller: _scroll,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(
                      LongNoteEditor.bufferExtent,
                    ),
                    itemCount: _rows.length,
                    itemExtentBuilder: (index, _) => index < _heights.length
                        ? _heights.heightOf(index)
                        : null,
                    itemBuilder: _buildRow,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Width of the fold buttons' column in this build, 0 without sections.
  double _gutter = 0;

  /// Height of one text line in this build, to centre a fold button on it.
  double _linePx = 0;

  Widget _buildRow(BuildContext context, int row) {
    // A row of a folded section takes no room and stays out of the
    // semantics tree; the caret never rests in one.
    final hidden = isRowHidden(row);
    if (hidden && row != _active) return const SizedBox.shrink();
    final section = _gutter > 0 ? _sections.sectionOfHeadingRow(row) : null;
    final foldable = section != null && _sections.isFoldable(section);
    final Widget child = row == _active
        ? _buildField()
        : _PlainRow(
            text: _text.substring(
              _rows.segmentStart(row),
              _rows.segmentEnd(row, _text.length),
            ),
            row: row,
            headingLevel: _rows.headingLevelOf(row),
            expanded: foldable ? !_folded.contains(section) : null,
            style: _style,
            spans: _spansFor(row),
            onTap: (offset) => _tapRow(row, offset),
            onAccessibilityFocus: () => _reveal(row),
          );
    final dimmed = _dimmed && row != _active
        ? Opacity(opacity: NoteMarkupController.dimmedAlpha, child: child)
        : child;
    final shown = _gutter == 0
        ? dimmed
        : Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(start: _gutter),
                child: dimmed,
              ),
              if (foldable)
                PositionedDirectional(
                  start: 0,
                  top: (_linePx - WpIconButton.compactExtent) / 2,
                  child: _foldButton(section),
                ),
            ],
          );
    final measured = _MeasuredRow(
      key: _rowKeys.putIfAbsent(row, GlobalKey.new),
      onLayout: (height) => _onMeasured(row, height),
      child: shown,
    );
    return _KeepAliveRow(
      keepAlive: row == _active,
      // The text field of a selection that ends in a folded section (Select
      // all) stays mounted for its keys, unseen.
      child: Offstage(offstage: hidden, child: measured),
    );
  }

  /// The chevron left of a heading: folds or unfolds its section. It takes
  /// no keyboard focus (Tab would walk through every heading of the note);
  /// the keyboard way is the shortcut, a screen reader activates it.
  Widget _foldButton(int section) {
    final l10n = L10n.of(context);
    final folded = _folded.contains(section);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final shortcut = commandShortcutLabel('K', shift: true, l10n: l10n);
    return ExcludeFocus(
      child: WpIconButton.ghost(
        compact: true,
        icon: folded
            ? (rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight)
            : LucideIcons.chevronDown,
        tooltip:
            '${folded ? l10n.notesUnfoldSection : l10n.notesFoldSection} '
            '($shortcut)',
        semanticsLabel: l10n.notesFoldSectionLabel(_headingTitle(section)),
        expanded: !folded,
        testId: 'notes-editor-fold-$section',
        onPressed: () => toggleSection(section),
      ),
    );
  }

  Widget _buildField() => Semantics(
    identifier: 'notes-editor-active-block',
    child: TextField(
      key: _fieldKey,
      controller: _local,
      undoController: _undo,
      focusNode: _fieldFocus,
      readOnly: widget.readOnly,
      // The surface around all rows draws the one focus contour (#1498).
      decoration: WpTextField.surfaceRowDecoration,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: _style,
      cursorColor: WpColors.accent,
      // Suggestions for the word at the caret; the check runs on the whole
      // note, so the row's offsets are moved into it (#670). The Smart Mode
      // actions follow (#650): the row's selection is mirrored into the
      // note's controller, which they read.
      contextMenuBuilder: (context, editable) => spellCheckContextMenu(
        context,
        editable,
        WpEditorSpellCheck.maybeOf(this.context),
        offsetShift: _segStart,
        menu: editorContextMenuFor(this.context, readOnly: widget.readOnly),
      ),
    ),
  );

  /// Selection and find tints of a plain row, in row offsets.
  _RowTint _spansFor(int row) {
    final start = _rows.segmentStart(row);
    final end = _rows.segmentEnd(row, _text.length);
    final cross = _cross;
    final selection = cross != null && cross.start < end && cross.end > start
        ? TextRange(
            start: math.max(cross.start, start) - start,
            end: math.min(cross.end, end) - start,
          )
        : null;
    final matches = _master.findMatches;
    final hits = <(int, int, bool)>[];
    if (matches.isNotEmpty) {
      for (
        var i = _lowerBound(matches.starts, start - matches.length + 1);
        i < matches.count && matches.starts[i] < end;
        i++
      ) {
        hits.add((
          math.max(matches.starts[i], start) - start,
          math.min(matches.endOf(i), end) - start,
          i == _master.activeFindIndex,
        ));
      }
    }
    return _RowTint(selection: selection, hits: hits);
  }
}

/// Selection and find hits to paint into a plain row.
class _RowTint {
  const _RowTint({required this.selection, required this.hits});

  final TextRange? selection;

  /// Start, end, and whether it is the active hit.
  final List<(int, int, bool)> hits;

  bool get isEmpty => selection == null && hits.isEmpty;
}

/// A row that is not being edited: the same text in the same style, so the
/// switch to the field moves nothing.
class _PlainRow extends StatelessWidget {
  const _PlainRow({
    required this.text,
    required this.row,
    required this.headingLevel,
    this.expanded,
    required this.style,
    required this.spans,
    required this.onTap,
    required this.onAccessibilityFocus,
  });

  final String text;
  final int row;
  final int headingLevel;

  /// Open/closed state of the section a heading starts (#1344), null for
  /// rows that start none.
  final bool? expanded;
  final TextStyle style;
  final _RowTint spans;
  final void Function(int offset) onTap;
  final VoidCallback onAccessibilityFocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'notes-editor-row-$row',
      header: headingLevel > 0,
      headingLevel: headingLevel > 0 ? headingLevel : null,
      expanded: expanded,
      onTap: () => onTap(0),
      onDidGainAccessibilityFocus: onAccessibilityFocus,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final paragraph = _paragraphOf(context);
          if (paragraph == null) return onTap(0);
          final local = paragraph.globalToLocal(details.globalPosition);
          onTap(paragraph.getPositionForOffset(local).offset);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Text.rich(
            TextSpan(style: style, children: _children(context)),
            textAlign: TextAlign.start,
          ),
        ),
      ),
    );
  }

  static RenderParagraph? _paragraphOf(BuildContext context) {
    RenderParagraph? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderParagraph) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  List<InlineSpan> _children(BuildContext context) {
    if (spans.isEmpty) return _markup();
    final selectionColor =
        DefaultSelectionStyle.of(context).selectionColor ??
        WpColors.accent.withValues(alpha: 0.3);
    final cuts = <int>{0, text.length};
    final selection = spans.selection;
    if (selection != null) cuts.addAll([selection.start, selection.end]);
    for (final hit in spans.hits) {
      cuts.addAll([hit.$1, hit.$2]);
    }
    final points = cuts.where((c) => c >= 0 && c <= text.length).toList()
      ..sort();
    final children = <InlineSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a == b) continue;
      Color? background;
      if (selection != null && a >= selection.start && b <= selection.end) {
        background = selectionColor;
      } else {
        for (final hit in spans.hits) {
          if (a >= hit.$1 && b <= hit.$2) {
            background = WpColors.accent.withValues(
              alpha: hit.$3
                  ? WpFindHighlightController.activeHighlightAlpha
                  : WpFindHighlightController.inactiveHighlightAlpha,
            );
            break;
          }
        }
      }
      children.add(
        TextSpan(
          text: text.substring(a, b),
          style: background == null
              ? null
              : TextStyle(backgroundColor: background),
        ),
      );
    }
    return children;
  }

  /// The `==mark==` highlight, drawn the way the field draws it.
  List<InlineSpan> _markup() {
    final marks = noteHighlightSpans(text);
    if (marks.isEmpty) return [TextSpan(text: text)];
    final marker = TextStyle(color: WpColors.textMuted);
    final marked = TextStyle(
      backgroundColor: WpColors.highlightSoft,
      color: WpColors.highlightText,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final mark in marks) {
      if (mark.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, mark.start)));
      }
      children
        ..add(
          TextSpan(
            text: text.substring(mark.start, mark.innerStart),
            style: marker,
          ),
        )
        ..add(
          TextSpan(
            text: text.substring(mark.innerStart, mark.innerEnd),
            style: marked,
          ),
        )
        ..add(
          TextSpan(
            text: text.substring(mark.innerEnd, mark.end),
            style: marker,
          ),
        );
      cursor = mark.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return children;
  }
}

/// Keeps the row with the text field alive while it scrolls out of the
/// buffer, so caret, focus and IME state survive.
class _KeepAliveRow extends StatefulWidget {
  const _KeepAliveRow({required this.keepAlive, required this.child});

  final bool keepAlive;
  final Widget child;

  @override
  State<_KeepAliveRow> createState() => _KeepAliveRowState();
}

class _KeepAliveRowState extends State<_KeepAliveRow>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(_KeepAliveRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Lays its child out at its natural height and reports it, inside the
/// extent the list gave the row (clipped when the estimate was too small
/// until the next frame takes the measurement).
class _MeasuredRow extends SingleChildRenderObjectWidget {
  const _MeasuredRow({super.key, required this.onLayout, super.child});

  final void Function(double height) onLayout;

  @override
  _RenderMeasured createRenderObject(BuildContext context) =>
      _RenderMeasured(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onLayout);

  void Function(double height) onLayout;
  bool _overflows = false;

  @override
  void performLayout() {
    final c = constraints;
    final child = this.child;
    if (child == null) {
      size = c.smallest;
      return;
    }
    child.layout(
      BoxConstraints(minWidth: c.minWidth, maxWidth: c.maxWidth),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    size = c.constrain(Size(child.size.width, natural));
    _overflows = natural > size.height + 0.5;
    onLayout(natural);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_overflows) return super.paint(context, offset);
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => super.paint(context, offset),
    );
  }
}
