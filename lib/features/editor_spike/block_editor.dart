/// EXPERIMENTAL (#642 editor spike). Not wired into navigation or any
/// production path; exists to measure whether a block-per-paragraph editor
/// keeps typing and jumping independent of the text length.
///
/// Inactive blocks render as styled text with Markdown markers hidden; exactly
/// one display row is active and shows its raw Markdown in an [EditableText].
/// Blocks longer than [BlockDocument.softSplitChars] are shown as several rows
/// (display only); the active unit is one such row.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:whispaste/features/notes/blocks/block_document.dart';

/// One display row: a block, or a soft-split segment `[start, end)` of it.
class _Row {
  _Row(this.block, this.start, this.end);
  int block;
  int start;
  int end;
}

/// Imperative handle for tests, benchmarks and a future host page.
class BlockEditorController {
  _BlockEditorState? _state;

  /// Scrolls block [index] to the top of the viewport via the height index.
  Future<void> jumpToBlock(int index) async => _state?._jumpToBlock(index);

  /// Makes the first row of block [index] the active row.
  void activateBlock(int index, {int caret = 0}) =>
      _state?._activateBlockRow(index, caret: caret);

  /// The text controller of the active row, or null when none is active.
  TextEditingController? get activeText => _state?._text;

  /// Index of the block that holds the active row, or -1.
  int get activeBlock => _state?._activeBlockIndex ?? -1;

  /// Number of display rows (blocks plus soft-split segments).
  int get rowCount => _state?._rows.length ?? 0;

  /// Commits the active row into the document (re-parses its block).
  void commit() => _state?._commit();

  /// Inserts dictated [text] at the caret of the active row, replacing a
  /// selection and ending an IME composition. The caret lands after [text].
  /// No-op when no row is active (ADR 0035: dictation goes where the caret is).
  void insertAtCaret(String text) => _state?._insertAtCaret(text);
}

class BlockEditor extends StatefulWidget {
  const BlockEditor({super.key, required this.document, this.controller});

  final BlockDocument document;
  final BlockEditorController? controller;

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'editor-spike-active');
  final _editableKey = GlobalKey<EditableTextState>();
  final List<_Row> _rows = [];

  /// Height index: one entry per row, estimated first, measured after layout.
  final List<double> _heights = [];
  final Map<int, BuildContext> _builtRows = {};

  TextEditingController? _text;
  int _active = -1;
  bool _dirty = false;
  double _width = 600;

  BlockDocument get _doc => widget.document;
  int get _activeBlockIndex => _active < 0 ? -1 : _rows[_active].block;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _focus.onKeyEvent = _onKey;
    _rebuildRows();
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _text?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Rows and height index
  // ---------------------------------------------------------------------------

  List<_Row> _rowsFor(int block) {
    final b = BlockDocument.segmentBounds(_doc.blocks[block].content);
    return [for (var k = 0; k + 1 < b.length; k++) _Row(block, b[k], b[k + 1])];
  }

  void _rebuildRows() {
    _rows.clear();
    _heights.clear();
    for (var i = 0; i < _doc.blocks.length; i++) {
      for (final r in _rowsFor(i)) {
        _rows.add(r);
        _heights.add(_estimate(r));
      }
    }
  }

  double _estimate(_Row r) {
    final block = _doc.blocks[r.block];
    final size = switch (block.headingLevel) {
      1 => 22.0,
      2 => 17.0,
      3 => 14.0,
      _ => 15.0,
    };
    final charsPerLine = math.max(1, (_width / (size * 0.52)).floor());
    final lines = ((r.end - r.start) / charsPerLine).ceil().clamp(1, 1 << 30);
    return lines * size * 1.5 + 12;
  }

  /// First row index of [block] (rows are sorted by block).
  int _firstRowOf(int block) {
    var lo = 0;
    var hi = _rows.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_rows[mid].block < block) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Replaces the rows of blocks `[first, first + oldCount)` with rows for
  /// `[first, first + newCount)`; later rows keep their measured heights.
  /// Returns the new row range start and end.
  (int, int) _splice(int first, int oldCount, int newCount) {
    final from = _firstRowOf(first);
    final to = _firstRowOf(first + oldCount);
    final fresh = <_Row>[
      for (var b = first; b < first + newCount; b++) ..._rowsFor(b),
    ];
    final shift = newCount - oldCount;
    if (shift != 0) {
      for (var k = to; k < _rows.length; k++) {
        _rows[k].block += shift;
      }
    }
    _rows.replaceRange(from, to, fresh);
    _heights.replaceRange(from, to, fresh.map(_estimate));
    return (from, from + fresh.length);
  }

  double _offsetOfRow(int row) {
    var sum = 0.0;
    for (var k = 0; k < row; k++) {
      sum += _heights[k];
    }
    return sum;
  }

  // ---------------------------------------------------------------------------
  // Active row
  // ---------------------------------------------------------------------------

  String _rowText(_Row r) =>
      _doc.blocks[r.block].content.substring(r.start, r.end);

  void _onTextChanged() {
    final r = _rows[_active];
    final block = _doc.blocks[r.block];
    final next = _text!.text;
    final oldLen = r.end - r.start;
    if (next.length == oldLen && block.content.startsWith(next, r.start)) {
      return; // selection-only change
    }
    block.content = block.content.replaceRange(r.start, r.end, next);
    final delta = next.length - oldLen;
    r.end += delta;
    for (var k = _active + 1; k < _rows.length; k++) {
      if (_rows[k].block != r.block) break;
      _rows[k]
        ..start += delta
        ..end += delta;
    }
    _dirty = true;
  }

  /// Re-parses the block of the active row. Returns how the row count of that
  /// block changed, so callers can map row indices after it.
  int _commit() {
    if (_active < 0 || !_dirty) return 0;
    final block = _rows[_active].block;
    final oldRows = _firstRowOf(block + 1) - _firstRowOf(block);
    final count = _doc.updateBlock(block, _doc.blocks[block].content);
    final (from, to) = _splice(block, 1, count);
    _dirty = false;
    return (to - from) - oldRows;
  }

  void _insertAtCaret(String insert) {
    final t = _text;
    if (t == null) return;
    final sel = t.selection.isValid
        ? t.selection
        : TextSelection.collapsed(offset: t.text.length);
    t.value = TextEditingValue(
      text: sel.textBefore(t.text) + insert + sel.textAfter(t.text),
      selection: TextSelection.collapsed(offset: sel.start + insert.length),
    );
  }

  void _setActive(int row, {required int caret}) {
    final old = _text?..removeListener(_onTextChanged);
    // The old EditableText still holds the controller until the next build.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _text = null;
    _active = row;
    if (row >= 0) {
      final text = _rowText(_rows[row]);
      _text = TextEditingController(text: text)
        ..selection = TextSelection.collapsed(
          offset: caret < 0 ? text.length : math.min(caret, text.length),
        )
        ..addListener(_onTextChanged);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active >= 0) _focus.requestFocus();
    });
  }

  /// Activates [row] (index before any commit). Commits when the block changes.
  void _activate(int row, {required int caret}) {
    if (row < 0 || row >= _rows.length) return;
    if (_active >= 0 && _rows[row].block != _rows[_active].block) {
      final activeBlock = _rows[_active].block;
      final lastOfActive = _firstRowOf(activeBlock + 1);
      final change = _commit();
      if (row >= lastOfActive) row += change;
    }
    _setActive(row, caret: caret);
  }

  void _activateBlockRow(int block, {int caret = 0}) {
    _activate(_firstRowOf(block), caret: caret);
  }

  bool _caretOnFirstLine() {
    final re = _editableKey.currentState?.renderEditable;
    final sel = _text?.selection;
    if (re == null || sel == null || !sel.isValid) return true;
    final top = re.getLocalRectForCaret(TextPosition(offset: sel.extentOffset));
    final first = re.getLocalRectForCaret(const TextPosition(offset: 0));
    return top.top <= first.top + 1;
  }

  bool _caretOnLastLine() {
    final re = _editableKey.currentState?.renderEditable;
    final sel = _text?.selection;
    if (re == null || sel == null || !sel.isValid) return true;
    final top = re.getLocalRectForCaret(TextPosition(offset: sel.extentOffset));
    final last = re.getLocalRectForCaret(
      TextPosition(offset: _text!.text.length),
    );
    return top.top >= last.top - 1;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    final sel = _text?.selection;
    if (sel == null || !sel.isCollapsed) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp &&
        _active > 0 &&
        _caretOnFirstLine()) {
      _activate(_active - 1, caret: -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown &&
        _active < _rows.length - 1 &&
        _caretOnLastLine()) {
      _activate(_active + 1, caret: 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace &&
        sel.baseOffset == 0 &&
        _rows[_active].start == 0 &&
        _rows[_active].block > 0) {
      _mergeIntoPrevious();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _mergeIntoPrevious() {
    _commit();
    final block = _rows[_active].block;
    final before = _doc.blocks.length;
    final caret = _doc.mergeWithPrevious(block);
    final newCount = 2 - (before - _doc.blocks.length);
    _splice(block - 1, 2, newCount);
    // Put the caret into the row that holds the join point.
    var row = _firstRowOf(block - 1);
    while (row + 1 < _rows.length &&
        _rows[row + 1].block == block - 1 &&
        _rows[row + 1].start <= caret) {
      row++;
    }
    _active = -1;
    _setActive(row, caret: caret - _rows[row].start);
  }

  // ---------------------------------------------------------------------------
  // Jump
  // ---------------------------------------------------------------------------

  bool _relayoutScheduled = false;

  /// Measured heights differ from the index: lay the list out again with the
  /// corrected extents after this frame (one rebuild per frame at most).
  void _scheduleRelayout() {
    if (_relayoutScheduled) return;
    _relayoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _relayoutScheduled = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _jumpToBlock(int block) async {
    if (!_scroll.hasClients) return;
    final row = _firstRowOf(block);
    _scroll.jumpTo(_offsetOfRow(row));
    // The list lays out with the indexed extents, so the target row is
    // built in this frame. Rows measured on the way may change the index;
    // re-align until it is stable.
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final target = _offsetOfRow(row);
      if ((target - _scroll.offset).abs() < 0.5) return;
      _scroll.jumpTo(target);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
        if ((w - 32 - _width).abs() > 1) {
          // Width changed: estimates are stale. Measured heights are
          // replaced as rows are laid out again.
          _width = math.max(100, w - 32);
          for (var k = 0; k < _rows.length; k++) {
            _heights[k] = _estimate(_rows[k]);
          }
        }
        return Semantics(
          identifier: 'editor-spike-document',
          container: true,
          child: ListView.builder(
            key: const ValueKey('editor-spike-list'),
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _rows.length,
            // Extents come from the height index, so a far jump lays out
            // only the rows at the target, not every row in between.
            itemExtentBuilder: (i, _) =>
                i < _heights.length ? _heights[i] : null,
            itemBuilder: _buildRow,
          ),
        );
      },
    );
  }

  TextStyle _styleFor(BuildContext context, MarkdownBlock block) {
    final t = Theme.of(context).textTheme;
    return switch (block.kind) {
          BlockKind.heading => switch (block.headingLevel) {
            1 => t.headlineLarge,
            2 => t.titleLarge,
            _ => t.titleMedium,
          },
          BlockKind.codeFence => t.bodyMedium?.copyWith(
            fontFamily: 'monospace',
          ),
          _ => t.bodyLarge,
        } ??
        const TextStyle();
  }

  Widget _buildRow(BuildContext context, int index) {
    final r = _rows[index];
    final block = _doc.blocks[r.block];
    final style = _styleFor(context, block);
    final Widget child;
    if (index == _active) {
      final cs = Theme.of(context).colorScheme;
      child = Semantics(
        identifier: 'editor-spike-active-block',
        child: EditableText(
          key: _editableKey,
          controller: _text!,
          focusNode: _focus,
          style: style.copyWith(color: cs.onSurface),
          cursorColor: cs.primary,
          backgroundCursorColor: cs.outline,
          selectionColor: cs.primary.withValues(alpha: 0.3),
          maxLines: null,
          keyboardType: TextInputType.multiline,
        ),
      );
    } else {
      final level = block.kind == BlockKind.heading ? block.headingLevel : 0;
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activate(index, caret: -1),
        // The tap action lets screen readers and switch access open a block
        // for editing; without it only pointer users could reach the editor.
        child: Semantics(
          identifier: 'editor-spike-block-$index',
          onTap: () => _activate(index, caret: -1),
          header: level > 0,
          headingLevel: level > 0 ? level : null,
          child: Text(_display(block, r), style: style),
        ),
      );
    }
    return _MeasuredRow(
      key: ValueKey('editor-spike-row-$index'),
      onLayout: (h, ctx) {
        _builtRows[index] = ctx;
        if (index < _heights.length && (_heights[index] - h).abs() > 0.5) {
          _heights[index] = h;
          _scheduleRelayout();
        }
      },
      onDispose: () => _builtRows.remove(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: child,
      ),
    );
  }

  static final _inlineMarkers = RegExp(r'\*\*|__|`|~~|==');
  static final _headingMarker = RegExp(r'^ {0,3}#{1,6}[ \t]*');
  static final _listMarker = RegExp(r'^([ \t]*)[-*+][ \t]');

  /// Rendered text of a row: Markdown markers hidden (spike-level rules).
  String _display(MarkdownBlock block, _Row r) {
    var s = block.content.substring(r.start, r.end);
    switch (block.kind) {
      case BlockKind.heading:
        s = s.replaceFirst(_headingMarker, '');
      case BlockKind.listItem:
        s = s.replaceFirstMapped(_listMarker, (m) => '${m[1]}• ');
      case BlockKind.codeFence:
        final lines = s.split('\n');
        if (lines.length > 1) lines.removeAt(0);
        if (lines.length > 1 &&
            lines.last.trimLeft().startsWith(RegExp('[`~]{3}'))) {
          lines.removeLast();
        }
        return lines.join('\n');
      case BlockKind.paragraph:
        break;
    }
    return s.replaceAll(_inlineMarkers, '');
  }
}

/// Reports its laid-out height to the height index without a rebuild.
class _MeasuredRow extends SingleChildRenderObjectWidget {
  const _MeasuredRow({
    super.key,
    required this.onLayout,
    required this.onDispose,
    super.child,
  });

  final void Function(double height, BuildContext context) onLayout;
  final VoidCallback onDispose;

  @override
  SingleChildRenderObjectElement createElement() => _MeasuredElement(this);

  @override
  _RenderMeasured createRenderObject(BuildContext context) =>
      _RenderMeasured(() => (onLayout, context));

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.read = () => (onLayout, context);
  }
}

class _MeasuredElement extends SingleChildRenderObjectElement {
  _MeasuredElement(_MeasuredRow super.widget);

  @override
  void unmount() {
    (widget as _MeasuredRow).onDispose();
    super.unmount();
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.read);

  (void Function(double, BuildContext), BuildContext) Function() read;

  bool _overflows = false;

  /// Lays the child out at its natural height (the list may force the indexed
  /// extent on us) and reports that height; clips until the index catches up.
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
    final (cb, ctx) = read();
    cb(natural, ctx);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_overflows) return super.paint(context, offset);
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (ctx, o) => super.paint(ctx, o),
    );
  }
}
