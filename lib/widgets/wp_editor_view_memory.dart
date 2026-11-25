/// Brings someone back to where they were in an entry (#678): caret or
/// selection, the paragraph at the top of the view and, in the long-note
/// editor, the folded sections (#1344). The text size is no
/// longer per entry: it is the editors' shared text view (#648,
/// `WpEditorText`). Shared by recordings, notes and snippets; the state lives in
/// [EditorViewStateStore], apart from the text, which this widget never
/// writes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accessibility/announce.dart';
import '../core/data/database.dart';
import '../core/data/editor_view_state.dart';
import '../core/l10n/generated/app_localizations.dart';

/// An editor that scrolls by itself in blocks (the long-note editor) reports
/// and takes its scroll anchor through this; anything else is measured from
/// its text render object.
abstract interface class WpEditorViewAnchor {
  /// The paragraph (not the editor's own row or block) at the top of the
  /// view and the pixels of it above the top, so a note keeps its place
  /// across the switch between the plain field and the block editor.
  ({int block, double offset})? captureViewAnchor();

  void restoreViewAnchor(int block, double offset);

  /// Notifies when the view scrolls or the folds change.
  Listenable get viewAnchorChanges;

  /// Ordinals of the folded heading sections (#1344).
  List<int> captureFolds();

  /// Folds the sections [folded] names; a section holding the caret stays
  /// open.
  void restoreFolds(List<int> folded);
}

class WpEditorViewMemory extends ConsumerStatefulWidget {
  const WpEditorViewMemory({
    super.key,
    required this.entry,
    required this.text,
    required this.focusNode,
    required this.child,
    this.controller,
    this.takeFocus = true,
  });

  /// Whose state this is. Key the widget by it as well, so a switch to
  /// another entry starts a fresh restore instead of carrying this one over.
  final ContentKey entry;

  /// The entry's text as shown now.
  final String Function() text;

  /// Holds the caret when the entry is editable; read-only text has none.
  final TextEditingController? controller;

  /// The focus that "lands in the text" on restore.
  final FocusNode focusNode;

  /// False where moving the focus would take it from somewhere it is
  /// needed (a list the arrow keys walk through).
  final bool takeFocus;

  final Widget child;

  /// Selections put in on purpose, by controller, until a restore saw them.
  static final _placed = Expando<TextSelection>();

  /// Puts [selection] into [controller] on purpose (a search hit opened at
  /// its match, #628). The next restore of a remembered place, which may
  /// only start once the entry is on screen, then keeps this selection and
  /// the view instead of moving back to where the entry was left; unless
  /// the selection moved in the meantime.
  static void place(TextEditingController controller, TextSelection selection) {
    _placed[controller] = selection;
    controller.selection = selection;
  }

  @override
  ConsumerState<WpEditorViewMemory> createState() => _WpEditorViewMemoryState();
}

class _WpEditorViewMemoryState extends ConsumerState<WpEditorViewMemory> {
  static const _saveDelay = Duration(milliseconds: 400);

  late final EditorViewStateStore _store;
  EditorViewState _state = const EditorViewState();
  EditorViewState? _saved;
  bool _ready = false;
  bool _captureScheduled = false;
  Timer? _saveTimer;
  Listenable? _scrollSource;

  /// The block editor seen last; folds are captured from it even while the
  /// focus is elsewhere (the editor menu folds all sections).
  WpEditorViewAnchor? _lastEditor;

  @override
  void initState() {
    super.initState();
    _store = ref.read(historyDatabaseProvider).viewStates;
    widget.controller?.addListener(_scheduleCapture);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(WpEditorViewMemory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_scheduleCapture);
      widget.controller?.addListener(_scheduleCapture);
      // A read view turned editable (a recording's edit mode): the caret
      // goes back where it was left.
      final controller = widget.controller;
      if (_ready && oldWidget.controller == null && controller != null) {
        final state = _state.clampedTo(controller.text);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.controller != controller) return;
          controller.selection = TextSelection(
            baseOffset: state.selectionBase,
            extentOffset: state.selectionExtent,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_scheduleCapture);
    _scrollSource?.removeListener(_scheduleCapture);
    _saveTimer?.cancel();
    // Only what was captured while this entry was on screen: by now the
    // shared controller may already hold the next entry's text.
    if (_ready && _state != _saved) unawaited(_save());
    super.dispose();
  }

  Future<void> _load() async {
    final stored = await _store.read(widget.entry);
    if (!mounted) return;
    final controller = widget.controller;
    final placed = controller == null
        ? null
        : WpEditorViewMemory._placed[controller];
    if (controller != null) WpEditorViewMemory._placed[controller] = null;
    if (stored == null || (placed != null && controller!.selection == placed)) {
      _ready = true;
      _watchScroll();
      return;
    }
    final state = stored.clampedTo(widget.text());
    setState(() => _state = state);
    _saved = state;
    if (controller != null && widget.text().isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: state.selectionBase,
        extentOffset: state.selectionExtent,
      );
    }
    // Twice: the first jump lands on estimated heights (long notes) or before
    // the field took the new text size; the second corrects it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreAnchor(state);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoreAnchor(state);
        _ready = true;
        _watchScroll();
        if (widget.takeFocus) widget.focusNode.requestFocus();
        _announcePosition(state);
      });
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  // ---------------------------------------------------------------------------
  // Capture and save
  // ---------------------------------------------------------------------------

  /// Captured after the frame, never inside the change: when the shared
  /// controller switches to the next entry this widget is gone by then, so
  /// that entry's caret is never written under this one.
  void _scheduleCapture() {
    if (!_ready || _captureScheduled) return;
    _captureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _captureScheduled = false;
      if (!mounted) return;
      _capture();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _capture() {
    final selection = widget.controller?.selection;
    final anchor = _measureAnchor();
    final folds = _foldingEditor()?.captureFolds();
    final next = _state.copyWith(
      selectionBase: selection != null && selection.isValid
          ? selection.baseOffset
          : null,
      selectionExtent: selection != null && selection.isValid
          ? selection.extentOffset
          : null,
      anchorBlock: anchor?.block,
      anchorOffset: anchor?.offset,
      folded: folds,
    );
    if (next == _state) return;
    _state = next;
    _queueSave();
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  Future<void> _save() async {
    final state = _state;
    if (state == _saved) return;
    _saved = state;
    await _store.save(widget.entry, state);
  }

  void _watchScroll() {
    final source = _anchorEditor()?.viewAnchorChanges ?? _scrollPosition();
    if (identical(source, _scrollSource)) return;
    _scrollSource?.removeListener(_scheduleCapture);
    _scrollSource = source?..addListener(_scheduleCapture);
  }

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  WpEditorViewAnchor? _foldingEditor() {
    final last = _lastEditor;
    if (last is State && !(last as State).mounted) _lastEditor = null;
    return _anchorEditor() ?? _lastEditor;
  }

  WpEditorViewAnchor? _anchorEditor() {
    WpEditorViewAnchor? found;
    final focusContext = _activeFocusContext();
    focusContext?.visitAncestorElements((element) {
      if (element == context) return false;
      if (element is StatefulElement && element.state is WpEditorViewAnchor) {
        found = element.state as WpEditorViewAnchor;
        return false;
      }
      return true;
    });
    if (found != null) _lastEditor = found;
    return found;
  }

  /// The shared focus node can still point at the element of an editor that
  /// has left the tree or was just replaced; ancestor lookups through it
  /// assert, so only a mounted, active one counts.
  BuildContext? _activeFocusContext() {
    final focusContext = widget.focusNode.context;
    if (focusContext == null || !focusContext.mounted) return null;
    if (!kReleaseMode &&
        focusContext is Element &&
        !focusContext.debugIsActive) {
      return null;
    }
    return focusContext;
  }

  RenderEditable? _editable() => _activeFocusContext()
      ?.findAncestorStateOfType<EditableTextState>()
      ?.renderEditable;

  /// A read-only text: the first paragraph under this widget, which is the
  /// entry's text.
  RenderParagraph? _paragraph() {
    final box = context.findRenderObject();
    RenderParagraph? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderParagraph) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    if (box != null) visit(box);
    return found;
  }

  /// The field's own scroll when it scrolls, else the page's around it.
  ScrollPosition? _scrollPosition() {
    final inner = _editable()?.offset;
    if (inner is ScrollPosition &&
        inner.hasContentDimensions &&
        inner.maxScrollExtent > 0) {
      return inner;
    }
    return Scrollable.maybeOf(context)?.position;
  }

  ({int block, double offset})? _measureAnchor() {
    final editor = _anchorEditor();
    if (editor != null) return editor.captureViewAnchor();
    final position = _scrollPosition();
    if (position == null || !position.hasPixels) return null;
    if (position.pixels <= 0) return (block: 0, offset: 0);
    final geometry = _geometry(position);
    if (geometry == null) return null;
    final text = widget.text();
    final top = geometry.viewTop;
    final atTop = geometry.positionAt(math.max(0, top));
    final block = EditorViewState.paragraphAt(text, atTop);
    final blockTop = geometry.caretTop(
      EditorViewState.paragraphStart(text, block),
    );
    return (block: block, offset: math.max(0, top - blockTop));
  }

  void _restoreAnchor(EditorViewState state) {
    final editor = _anchorEditor();
    if (editor != null) {
      // Folds first: they change the heights the anchor is measured in.
      editor
        ..restoreFolds(state.folded)
        ..restoreViewAnchor(state.anchorBlock, state.anchorOffset);
      return;
    }
    final position = _scrollPosition();
    if (position == null || !position.hasContentDimensions) return;
    if (state.anchorBlock == 0 && state.anchorOffset == 0) {
      position.jumpTo(position.minScrollExtent);
      return;
    }
    final geometry = _geometry(position);
    if (geometry == null) return;
    final start = EditorViewState.paragraphStart(
      widget.text(),
      state.anchorBlock,
    );
    final delta =
        geometry.caretTop(start) + state.anchorOffset - geometry.viewTop;
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Text coordinates of the editable or read-only text, against the top of
  /// [position]'s viewport.
  _TextGeometry? _geometry(ScrollPosition position) {
    final viewport = position.context.notificationContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return null;
    final editable = _editable();
    if (editable != null && editable.attached) {
      final top = editable
          .globalToLocal(viewport.localToGlobal(Offset.zero))
          .dy;
      return _TextGeometry(
        viewTop: top,
        positionAt: (y) => editable
            .getPositionForPoint(editable.localToGlobal(Offset(1, y)))
            .offset,
        caretTop: (offset) =>
            editable.getLocalRectForCaret(TextPosition(offset: offset)).top,
      );
    }
    final paragraph = _paragraph();
    if (paragraph != null && paragraph.attached) {
      final top = paragraph
          .globalToLocal(viewport.localToGlobal(Offset.zero))
          .dy;
      return _TextGeometry(
        viewTop: top,
        positionAt: (y) => paragraph.getPositionForOffset(Offset(1, y)).offset,
        caretTop: (offset) => paragraph
            .getOffsetForCaret(TextPosition(offset: offset), Rect.zero)
            .dy,
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Announcements
  // ---------------------------------------------------------------------------

  void _announcePosition(EditorViewState state) {
    final text = widget.text();
    final paragraph =
        EditorViewState.paragraphAt(text, state.selectionExtent) + 1;
    final total = EditorViewState.paragraphCount(text);
    _say(L10n.of(context).editorPositionRestored(paragraph, total));
  }

  void _say(String message) =>
      announce(View.of(context), message, Directionality.of(context));

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TextGeometry {
  const _TextGeometry({
    required this.viewTop,
    required this.positionAt,
    required this.caretTop,
  });

  /// The viewport's top edge in the text's coordinates.
  final double viewTop;
  final int Function(double y) positionAt;
  final double Function(int offset) caretTop;
}
