import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Undo/redo for one text document, shared by every editor (#651).
///
/// Stores changed ranges, never copies of the whole text, so a long note
/// stays cheap at full depth. Grouping rules:
/// * typing (up to two code units inserted, or deleted, per change) joins
///   the previous step while the next key follows within [groupWindow], at
///   the same place and in the same direction;
/// * a pause, a caret jump, or any command (toolbar, replace, dictation,
///   smart action) ends the group; a command is always a step of its own;
/// * an IME composition is held until it commits and lands as one step.
class TextUndoHistory {
  TextUndoHistory({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Keys typed closer together than this undo together.
  static const Duration groupWindow = Duration(milliseconds: 500);

  /// Steps kept per document; the oldest falls off first.
  static const int maxDepth = 1000;

  final DateTime Function() _clock;
  final List<_Step> _undo = [];
  final List<_Step> _redo = [];
  TextEditingValue? _compositionStart;
  bool _sealed = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void clear() {
    _undo.clear();
    _redo.clear();
    _compositionStart = null;
    _sealed = false;
  }

  /// Ends the current typing group: the next change starts a new step.
  void seal() => _sealed = true;

  void record(
    TextEditingValue before,
    TextEditingValue after, {
    bool command = false,
  }) {
    if (after.composing.isValid && !after.composing.isCollapsed) {
      _compositionStart ??= before;
      return;
    }
    final composed = _compositionStart != null;
    before = _compositionStart ?? before;
    _compositionStart = null;
    if (before.text == after.text) {
      // Moving the caret away from where the last step left it ends the
      // group; it keeps redo, since the text is unchanged.
      if (_undo.isNotEmpty && after.selection != _undo.last.after) seal();
      return;
    }
    final now = _clock();
    final step = _Step.diff(before, after, now);
    final kind = command || composed ? _Kind.command : step.typingKind();
    _redo.clear();
    final last = _undo.isEmpty ? null : _undo.last;
    if (!_sealed &&
        last != null &&
        kind != _Kind.command &&
        last.kind == kind &&
        now.difference(last.at) <= groupWindow &&
        before.selection == last.after &&
        last.absorb(step)) {
      return;
    }
    _undo.add(step..kind = kind);
    if (_undo.length > maxDepth) _undo.removeAt(0);
    _sealed = kind == _Kind.command;
  }

  TextEditingValue? undo(TextEditingValue value) =>
      _restore(value, redo: false);

  TextEditingValue? redo(TextEditingValue value) => _restore(value, redo: true);

  TextEditingValue? _restore(TextEditingValue value, {required bool redo}) {
    final source = redo ? _redo : _undo;
    if (source.isEmpty) return null;
    final step = source.last;
    final removed = redo ? step.removed : step.inserted;
    final inserted = redo ? step.inserted : step.removed;
    final end = step.start + removed.length;
    // A change nobody recorded would make the stored ranges point at the
    // wrong text; drop the history rather than corrupt the document.
    if (end > value.text.length ||
        value.text.substring(step.start, end) != removed) {
      clear();
      return null;
    }
    source.removeLast();
    (redo ? _undo : _redo).add(step);
    _compositionStart = null;
    _sealed = true;
    final text = value.text.replaceRange(step.start, end, inserted);
    return TextEditingValue(
      text: text,
      selection: _clampSelection(redo ? step.after : step.before, text.length),
    );
  }

  static TextSelection _clampSelection(TextSelection s, int length) => s.isValid
      ? TextSelection(
          baseOffset: math.min(s.baseOffset, length),
          extentOffset: math.min(s.extentOffset, length),
        )
      : TextSelection.collapsed(offset: length);
}

enum _Kind { insert, deleteBackward, deleteForward, command }

class _Step {
  _Step(
    this.start,
    this.removed,
    this.inserted,
    this.before,
    this.after,
    this.at,
  );

  factory _Step.diff(
    TextEditingValue before,
    TextEditingValue after,
    DateTime at,
  ) {
    final a = before.text;
    final b = after.text;
    var start = 0;
    final common = math.min(a.length, b.length);
    while (start < common && a.codeUnitAt(start) == b.codeUnitAt(start)) {
      start++;
    }
    var suffix = 0;
    while (suffix < common - start &&
        a.codeUnitAt(a.length - suffix - 1) ==
            b.codeUnitAt(b.length - suffix - 1)) {
      suffix++;
    }
    return _Step(
      start,
      a.substring(start, a.length - suffix),
      b.substring(start, b.length - suffix),
      before.selection,
      after.selection,
      at,
    );
  }

  int start;
  String removed;
  String inserted;
  final TextSelection before;
  TextSelection after;
  DateTime at;
  _Kind kind = _Kind.command;

  /// What a single keystroke looks like; anything bigger is a command.
  _Kind typingKind() {
    if (removed.isEmpty && inserted.isNotEmpty && inserted.length <= 2) {
      return _Kind.insert;
    }
    if (inserted.isEmpty && removed.isNotEmpty && removed.length <= 2) {
      final caret = before.isValid && before.isCollapsed
          ? before.extentOffset
          : -1;
      return caret == start ? _Kind.deleteForward : _Kind.deleteBackward;
    }
    // Typing over a selection opens a group the following keys can join.
    if (removed.isNotEmpty && inserted.isNotEmpty && inserted.length <= 2) {
      return _Kind.insert;
    }
    return _Kind.command;
  }

  /// Folds the adjacent keystroke [next] into this step.
  bool absorb(_Step next) {
    switch (kind) {
      case _Kind.insert:
        if (next.removed.isNotEmpty || next.start != start + inserted.length) {
          return false;
        }
        inserted += next.inserted;
      case _Kind.deleteBackward:
        if (inserted.isNotEmpty || next.start + next.removed.length != start) {
          return false;
        }
        start = next.start;
        removed = next.removed + removed;
      case _Kind.deleteForward:
        if (inserted.isNotEmpty || next.start != start) return false;
        removed += next.removed;
      case _Kind.command:
        return false;
    }
    after = next.after;
    at = next.at;
    return true;
  }
}

/// Keeps a [TextUndoHistory] in step with one [TextEditingController].
///
/// Registered on the controller, so the shared toolbar, the find bar and
/// the pages reach it through [of] without wiring; without one, [command]
/// just applies the change.
class TextUndoController extends ChangeNotifier {
  TextUndoController(this.text, {DateTime Function()? clock})
    : _clock = clock,
      _history = TextUndoHistory(clock: clock),
      _previous = text.value {
    text.addListener(_onChanged);
    _registry[text] = this;
  }

  /// Histories of documents the user left, so coming back can still undo.
  static const int parkedDocuments = 20;

  static final Expando<TextUndoController> _registry = Expando(
    'TextUndoController',
  );

  static TextUndoController? of(TextEditingController controller) =>
      _registry[controller];

  /// Applies a programmatic change to [controller] as one undo step.
  static void command(TextEditingController controller, VoidCallback apply) {
    final undo = of(controller);
    if (undo == null) {
      apply();
    } else {
      undo.runCommand(apply);
    }
  }

  final TextEditingController text;
  final DateTime Function()? _clock;
  TextUndoHistory _history;
  TextEditingValue _previous;
  bool _muted = false;
  Object? _key;
  final LinkedHashMap<Object, _Parked> _parked = LinkedHashMap();
  bool _canUndo = false;
  bool _canRedo = false;

  bool get canUndo => _canUndo;
  bool get canRedo => _canRedo;

  void _onChanged() {
    final value = text.value;
    if (!_muted) _history.record(_previous, value);
    _previous = value;
    _sync();
  }

  void runCommand(VoidCallback apply) {
    final before = text.value;
    _muted = true;
    try {
      apply();
    } finally {
      _muted = false;
    }
    _history.record(before, text.value, command: true);
    _previous = text.value;
    _sync();
  }

  void undo() => _restore(redo: false);

  void redo() => _restore(redo: true);

  void _restore({required bool redo}) {
    // Never cut through an open IME composition.
    if (!text.value.composing.isCollapsed) return;
    final value = redo ? _history.redo(text.value) : _history.undo(text.value);
    if (value != null) {
      _muted = true;
      try {
        text.value = value;
      } finally {
        _muted = false;
      }
    }
    _sync();
  }

  /// Shows the document [key] through [apply]. Leaving a document parks its
  /// history; coming back to it, with the text unchanged, restores it.
  /// Reloading the same document (a restored version) is an undoable step.
  void open(Object key, VoidCallback apply) {
    if (key == _key) {
      runCommand(apply);
      return;
    }
    final left = _key;
    if (left != null && (_history.canUndo || _history.canRedo)) {
      _parked.remove(left);
      _parked[left] = _Parked(_history, _Fingerprint(text.text));
      if (_parked.length > parkedDocuments) _parked.remove(_parked.keys.first);
    }
    _apply(apply);
    final parked = _parked.remove(key);
    _history = parked != null && parked.text == _Fingerprint(text.text)
        ? parked.history
        : TextUndoHistory(clock: _clock);
    _history.seal();
    _key = key;
    _sync();
  }

  /// Replaces the text through [apply] and forgets the history of the open
  /// document, e.g. when an edit is discarded.
  void reset(VoidCallback apply) {
    _apply(apply);
    _history.clear();
    final key = _key;
    if (key != null) _parked.remove(key);
    _sync();
  }

  void _apply(VoidCallback apply) {
    _muted = true;
    try {
      apply();
    } finally {
      _muted = false;
    }
    _previous = text.value;
  }

  void _sync() {
    if (_canUndo == _history.canUndo && _canRedo == _history.canRedo) return;
    _canUndo = _history.canUndo;
    _canRedo = _history.canRedo;
    notifyListeners();
  }

  @override
  void dispose() {
    text.removeListener(_onChanged);
    if (identical(_registry[text], this)) _registry[text] = null;
    super.dispose();
  }
}

class _Parked {
  const _Parked(this.history, this.text);

  final TextUndoHistory history;
  final _Fingerprint text;
}

/// Identifies a parked text without keeping a second copy of it.
class _Fingerprint {
  _Fingerprint(String text) : length = text.length, hash = text.hashCode;

  final int length;
  final int hash;

  @override
  bool operator ==(Object other) =>
      other is _Fingerprint && other.length == length && other.hash == hash;

  @override
  int get hashCode => Object.hash(length, hash);
}

/// Routes the platform undo/redo shortcuts and menu items inside [child] to
/// the [TextUndoController] of [controller], replacing the text field's own
/// per-widget history. Windows and Linux also redo with Ctrl+Y.
class TextUndoActions extends StatelessWidget {
  const TextUndoActions({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Widget child;
  final bool enabled;

  static const _ctrlY = SingleActivator(LogicalKeyboardKey.keyY, control: true);

  @override
  Widget build(BuildContext context) {
    final actions = Actions(
      actions: {
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            if (enabled) TextUndoController.of(controller)?.undo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            if (enabled) TextUndoController.of(controller)?.redo();
            return null;
          },
        ),
      },
      child: child,
    );
    if (defaultTargetPlatform == TargetPlatform.macOS) return actions;
    return Shortcuts(
      shortcuts: const {_ctrlY: RedoTextIntent(SelectionChangedCause.keyboard)},
      child: actions,
    );
  }
}
