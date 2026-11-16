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
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/data/editor_view_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/find_replace.dart';
import '../../../widgets/wp_editor_view_memory.dart';
import '../../../widgets/wp_text_field.dart';
import '../blocks/long_note_layout.dart';
import '../../../core/text/text_undo.dart';
import '../data/note_highlight_markup.dart';
import '../blocks/block_document.dart';
import 'note_markup_controller.dart';

class LongNoteEditor extends StatefulWidget {
  const LongNoteEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.scrollToEnd,
    this.semanticsLabel,
    this.readOnly = false,
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

  /// Rows built beyond the viewport, above and below. They stay in the
  /// semantics tree (hidden), so a screen reader reads on across the edge of
  /// the window without waiting for a scroll.
  static const double bufferExtent = 1500;

  @override
  State<LongNoteEditor> createState() => LongNoteEditorState();
}

class LongNoteEditorState extends State<LongNoteEditor>
    implements WpEditorViewAnchor {
  late NoteRows _rows;
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

  @override
  void initState() {
    super.initState();
    _text = _master.text;
    _adoptHistory();
    _rows = NoteRows.of(_text);
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
  }

  @override
  void dispose() {
    _dragTimer?.cancel();
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
  Listenable get viewAnchorChanges => _scroll;

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
      _reparse();
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

  void _reparse() {
    final old = _rows;
    _rows = NoteRows.of(_text);
    _heights.rebase(old, _rows, _fontSize);
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
      _text = text;
      _reparse();
    }
    final sel = _master.selection;
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

  /// Hands the page's find highlight to the active row, shifted into it.
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

    if (shift) {
      int? to;
      if (key == LogicalKeyboardKey.arrowLeft && atStart && _active > 0) {
        to = _previousCharacter(start);
      } else if (key == LogicalKeyboardKey.arrowRight &&
          atEnd &&
          _active < last) {
        to = _nextCharacter(end);
      } else if (key == LogicalKeyboardKey.arrowUp &&
          _caretOnEdgeLine(first: true) &&
          _active > 0) {
        to = _rows.segmentStart(_active - 1);
      } else if (key == LogicalKeyboardKey.arrowDown &&
          _caretOnEdgeLine(first: false) &&
          _active < last) {
        to = _rows.segmentEnd(_active + 1, len);
      }
      if (to == null) return KeyEventResult.ignored;
      _select(TextSelection(baseOffset: anchor, extentOffset: to));
      return KeyEventResult.handled;
    }

    if (!sel.isCollapsed) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft && atStart && _active > 0) {
      _select(TextSelection.collapsed(offset: _previousCharacter(start)));
    } else if (key == LogicalKeyboardKey.arrowRight &&
        atEnd &&
        _active < last) {
      _select(TextSelection.collapsed(offset: _nextCharacter(end)));
    } else if (key == LogicalKeyboardKey.arrowUp &&
        _active > 0 &&
        _caretOnEdgeLine(first: true)) {
      _moveToRow(_active - 1, atEnd: true);
    } else if (key == LogicalKeyboardKey.arrowDown &&
        _active < last &&
        _caretOnEdgeLine(first: false)) {
      _moveToRow(_active + 1, atEnd: false);
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
      if (key == LogicalKeyboardKey.arrowLeft) to = _previousCharacter(extent);
      if (key == LogicalKeyboardKey.arrowRight) to = _nextCharacter(extent);
      if (key == LogicalKeyboardKey.arrowUp) {
        final top = _rows.segmentStart(row);
        to = extent > top || row == 0 ? top : _rows.segmentStart(row - 1);
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        final bottom = _rows.segmentEnd(row, len);
        to = extent < bottom || row == _rows.length - 1
            ? bottom
            : _rows.segmentEnd(row + 1, len);
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

  TextStyle get _style => WpTextField.styleFor(
    WpTextFieldVariant.bare,
    color: WpColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
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
                  final key = LayoutKey(
                    width: constraints.maxWidth,
                    textScale: scaler.scale(_fontSize) / _fontSize,
                    devicePixelRatio: dpr,
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

  Widget _buildRow(BuildContext context, int row) {
    final Widget child = row == _active
        ? _buildField()
        : _PlainRow(
            text: _text.substring(
              _rows.segmentStart(row),
              _rows.segmentEnd(row, _text.length),
            ),
            row: row,
            headingLevel: _rows.headingLevelOf(row),
            style: _style,
            spans: _spansFor(row),
            onTap: (offset) => _tapRow(row, offset),
            onAccessibilityFocus: () => _reveal(row),
          );
    final shown = _dimmed && row != _active
        ? Opacity(opacity: NoteMarkupController.dimmedAlpha, child: child)
        : child;
    return _KeepAliveRow(
      keepAlive: row == _active,
      child: _MeasuredRow(
        key: _rowKeys.putIfAbsent(row, GlobalKey.new),
        onLayout: (height) => _onMeasured(row, height),
        child: shown,
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
    required this.style,
    required this.spans,
    required this.onTap,
    required this.onAccessibilityFocus,
  });

  final String text;
  final int row;
  final int headingLevel;
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
