import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/command_shortcut.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/text/text_undo.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'find_replace.dart';
import 'find_replace_bar.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

/// The markdown formatting actions themselves — the one place that knows how
/// bold, italic, a heading, a list, a quote or code are applied to a
/// [TextEditingController].
///
/// Both halves of the feature go through here: the buttons in
/// [WpMarkdownToolbar] and the keyboard shortcuts on every surface that offers
/// them (History's transcript editor, the Notes editor). The panels used to
/// carry a second, subtly different copy of the same three operations — bold
/// that could wrap but never unwrap, a list toggle that dropped the selection
/// — so the same keystroke and the same button did not do the same thing. One
/// implementation, reached from both, is the point of this class.
@immutable
class WpMarkdownFormatting {
  const WpMarkdownFormatting({
    required this.controller,
    required this.focusNode,
  });

  /// The field being edited, and the node that gets focus back afterwards —
  /// formatting is only ever a detour from typing.
  final TextEditingController controller;
  final FocusNode focusNode;

  // ── The eight actions ────────────────────────────────────────────────────

  void bold() => _wrapSelection('**');
  void italic() => _wrapSelection('_');
  void code() => _wrapSelection('`');
  void heading() => _toggleLinePrefix('## ');
  void bulletList() => _toggleLinePrefix('- ');
  void numberedList() => _toggleLinePrefix('1. ');
  void checklist() => _toggleLinePrefix('- [ ] ');
  void quote() => _toggleLinePrefix('> ');

  /// Puts [text] where the caret is: a selection is replaced, the caret lands
  /// right after the inserted text, and without a valid selection (the field
  /// was never focused) the text goes to the end. Used for inserting a
  /// Textbaustein (#664) — typing continues where the snippet ends.
  void insertText(String text) {
    final value = controller.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    focusNode.requestFocus();
  }

  /// The selected text, or `null` when nothing (or only whitespace) is
  /// selected — the source for "save selection as Textbaustein".
  String? get selectedText {
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed) return null;
    final text = sel.textInside(controller.text);
    return text.trim().isEmpty ? null : text;
  }

  // ── The keyboard half ────────────────────────────────────────────────────

  /// Ctrl+B on Windows/Linux, Cmd+B on macOS — the platform split every other
  /// shortcut in the app already makes.
  static SingleActivator get boldActivator =>
      commandActivator(LogicalKeyboardKey.keyB);

  static SingleActivator get italicActivator =>
      commandActivator(LogicalKeyboardKey.keyI);

  static SingleActivator get bulletListActivator =>
      commandActivator(LogicalKeyboardKey.keyL, shift: true);

  // Every paragraph style has a key of its own (#652), so a keyboard or
  // screen-reader user never has to leave the text for the toolbar. All sit
  // on Cmd/Ctrl+Shift: Ctrl+Alt is AltGr on Windows and types characters,
  // Cmd+Shift+Q logs out on macOS, Ctrl+Shift+U opens the IBus Unicode
  // entry on Linux, and plain Cmd/Ctrl+E already toggles edit mode in
  // History, and Cmd/Ctrl+Shift+E is the systemwide snippet picker (#664).
  // 7 and 9 follow the numbered-list and quote keys of the common mail and
  // chat editors; H, T(odo) and C(ode) are mnemonic.

  static SingleActivator get headingActivator =>
      commandActivator(LogicalKeyboardKey.keyH, shift: true);

  static SingleActivator get numberedListActivator =>
      commandActivator(LogicalKeyboardKey.digit7, shift: true);

  static SingleActivator get checklistActivator =>
      commandActivator(LogicalKeyboardKey.keyT, shift: true);

  static SingleActivator get quoteActivator =>
      commandActivator(LogicalKeyboardKey.digit9, shift: true);

  static SingleActivator get codeActivator =>
      commandActivator(LogicalKeyboardKey.keyC, shift: true);

  /// Ctrl/Cmd+Shift+I: insert a Textbaustein at the caret (#664). "I" for
  /// insert; Ctrl/Cmd+Shift+E is the systemwide snippet picker and must stay
  /// free for it, so the in-editor command takes its own key.
  static SingleActivator get insertSnippetActivator =>
      commandActivator(LogicalKeyboardKey.keyI, shift: true);

  /// The bindings to hand a [CallbackShortcuts] above the field.
  ///
  /// [when] gates them on the surface's own notion of "the editor is live":
  /// History passes its edit-mode flag (outside edit mode Ctrl+B must not
  /// rewrite a transcript that is only being read), Notes passes the editor's
  /// focus (the panel also holds a tag input, and formatting the note body
  /// while typing a tag name would come out of nowhere). Omitted, the
  /// shortcuts are always live.
  ///
  /// [onInsertSnippet] binds [insertSnippetActivator] when the surface offers
  /// inserting a Textbaustein, gated by [when] like the formatting keys.
  Map<ShortcutActivator, VoidCallback> shortcutBindings({
    bool Function()? when,
    VoidCallback? onInsertSnippet,
  }) {
    bool enabled() => when?.call() ?? true;
    return <ShortcutActivator, VoidCallback>{
      boldActivator: () {
        if (enabled()) bold();
      },
      italicActivator: () {
        if (enabled()) italic();
      },
      bulletListActivator: () {
        if (enabled()) bulletList();
      },
      headingActivator: () {
        if (enabled()) heading();
      },
      numberedListActivator: () {
        if (enabled()) numberedList();
      },
      checklistActivator: () {
        if (enabled()) checklist();
      },
      quoteActivator: () {
        if (enabled()) quote();
      },
      codeActivator: () {
        if (enabled()) code();
      },
      if (onInsertSnippet != null)
        insertSnippetActivator: () {
          if (enabled()) onInsertSnippet();
        },
    };
  }

  /// How a shortcut is spelled in a tooltip, per platform: `⌘B` on macOS,
  /// `Strg+B` (German) or `Ctrl+B` elsewhere. The words are localized through
  /// [l10n] like the shortcut help overlay in History.
  static String boldShortcutLabel(L10n l10n) =>
      commandShortcutLabel('B', l10n: l10n);
  static String italicShortcutLabel(L10n l10n) =>
      commandShortcutLabel('I', l10n: l10n);
  static String bulletListShortcutLabel(L10n l10n) =>
      commandShortcutLabel('L', shift: true, l10n: l10n);
  static String insertSnippetShortcutLabel(L10n l10n) =>
      commandShortcutLabel('I', shift: true, l10n: l10n);
  static String headingShortcutLabel(L10n l10n) =>
      commandShortcutLabel('H', shift: true, l10n: l10n);
  static String numberedListShortcutLabel(L10n l10n) =>
      commandShortcutLabel('7', shift: true, l10n: l10n);
  static String checklistShortcutLabel(L10n l10n) =>
      commandShortcutLabel('T', shift: true, l10n: l10n);
  static String quoteShortcutLabel(L10n l10n) =>
      commandShortcutLabel('9', shift: true, l10n: l10n);
  static String codeShortcutLabel(L10n l10n) =>
      commandShortcutLabel('C', shift: true, l10n: l10n);

  // ── Implementation ───────────────────────────────────────────────────────

  /// Every formatting action is one undo step of its own (#651).
  void _apply(TextEditingValue value) =>
      TextUndoController.command(controller, () => controller.value = value);

  void _wrapSelection(String prefix, [String? suffix]) {
    suffix ??= prefix;
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid) return;

    final before = text.substring(0, sel.start);
    final selected = text.substring(sel.start, sel.end);
    final after = text.substring(sel.end);

    // If already wrapped, unwrap
    if (selected.startsWith(prefix) && selected.endsWith(suffix)) {
      final unwrapped = selected.substring(
        prefix.length,
        selected.length - suffix.length,
      );
      _apply(
        TextEditingValue(
          text: '$before$unwrapped$after',
          selection: TextSelection(
            baseOffset: sel.start,
            extentOffset: sel.start + unwrapped.length,
          ),
        ),
      );
    } else {
      final wrapped = '$prefix$selected$suffix';
      _apply(
        TextEditingValue(
          text: '$before$wrapped$after',
          selection: TextSelection(
            baseOffset: sel.start,
            extentOffset: sel.start + wrapped.length,
          ),
        ),
      );
    }

    focusNode.requestFocus();
  }

  void _toggleLinePrefix(String prefix) {
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid) return;

    // Find the start of the current line
    final lineStart = text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0);
    final actualStart = lineStart == -1 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', sel.end);
    final actualEnd = lineEnd == -1 ? text.length : lineEnd;

    final lines = text.substring(actualStart, actualEnd).split('\n');
    final allPrefixed = lines.every((l) => l.startsWith(prefix));

    final transformed = lines
        .map((l) {
          if (allPrefixed) {
            return l.startsWith(prefix) ? l.substring(prefix.length) : l;
          }
          return l.startsWith(prefix) ? l : '$prefix$l';
        })
        .join('\n');

    final before = text.substring(0, actualStart);
    final after = text.substring(actualEnd);

    final diff = transformed.length - (actualEnd - actualStart);
    _apply(
      TextEditingValue(
        text: '$before$transformed$after',
        selection: TextSelection(
          baseOffset: sel.start + (sel.start > actualStart ? diff : 0),
          extentOffset: sel.end + diff,
        ),
      ),
    );

    focusNode.requestFocus();
  }
}

/// Markdown formatting toolbar for text editing, plus find-and-replace.
///
/// Every formatting button calls the matching method on
/// [WpMarkdownFormatting], which is also what the keyboard shortcuts call, so
/// the tooltip that promises `Ctrl+B` and the key that answers it can no
/// longer disagree. The button row is horizontally scrollable, because at the
/// 280 dp the detail panels render down to, nine buttons do not fit and the
/// panel must not be the thing that scrolls.
///
/// ## Keyboard and screen readers (#652)
///
/// The row is one stop in the Tab order, not nine: Tab lands on the button
/// used last (the first one at the start), the arrow keys move between the
/// buttons (mirrored in right-to-left languages), Home and End jump to the
/// ends, and Tab leaves the group again. Every button is a 48 dp target and
/// is announced once, by its label with the shortcut, and carries the
/// identifier `<testIdPrefix>-toolbar-<action>`. A disabled button (read-only
/// text, nothing to undo) is skipped by the arrow keys. The hosts put the text field
/// before the toolbar in the Tab order (see [WpEditorTraversal]), so typing
/// is always the first thing the keyboard reaches.
///
/// ## Why find-and-replace lives here
///
/// It is the one widget History's transcript editor, the Notes editor and the
/// Snippet dialog already share, so hanging the bar off it lights the feature
/// up on all three at once and keeps a single copy of the interaction. The bar
/// itself is [WpFindReplaceBar]; this widget only owns whether it is open.
///
/// Deliberately **not** bound to `Ctrl/Cmd+F`: that combination is already the
/// "focus the list search field" shortcut on the History and the Notes page
/// (`history_page.dart`, `notes_page.dart`), and quietly changing what it does
/// while a caret sits in the editor would break a shortcut people already use
/// to filter their list. The toggle button and `Escape`-to-close are the whole
/// keyboard story until that conflict is resolved on purpose.
class WpMarkdownToolbar extends StatefulWidget {
  const WpMarkdownToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onInsertSnippet,
    this.onSaveSelectionAsSnippet,
    this.testIdPrefix = 'editor',
    this.enabled = true,
    this.undoController,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Shares the button row where the width allows (the note's tags, #1498):
  /// the buttons keep their place on the left, [trailing] takes the rest.
  /// Below [trailingMinRowWidth] it moves onto its own line under the
  /// buttons.
  final Widget? trailing;

  /// Narrowest row that still holds the buttons and [trailing] side by side.
  static const double trailingMinRowWidth = 360;

  /// Width always left to [trailing] in the shared row.
  static const double trailingMinWidth = 140;

  /// Opens the Textbaustein chooser and inserts the pick at the caret (#664).
  /// `null` hides the button — the surface does not offer it.
  final VoidCallback? onInsertSnippet;

  /// Saves the current selection as a new Textbaustein (#664). `null` hides
  /// the button.
  final VoidCallback? onSaveSelectionAsSnippet;

  /// Every button carries the semantics identifier
  /// `<testIdPrefix>-toolbar-<action>` (for example
  /// `history-transcript-toolbar-bold`), so flows address it without text.
  /// The find bar uses the same prefix.
  final String testIdPrefix;

  /// Off while the text is only being read: the bar stays where it is (so
  /// switching into editing moves nothing) but none of its buttons act.
  final bool enabled;

  /// When given, the bar leads with undo and redo for this history — the same
  /// history Ctrl/Cmd+Z walks, so key and button cannot disagree (#651).
  final TextUndoController? undoController;

  @override
  State<WpMarkdownToolbar> createState() => _WpMarkdownToolbarState();
}

class _WpMarkdownToolbarState extends State<WpMarkdownToolbar> {
  bool _findOpen = false;

  void _toggleFind() {
    if (_findOpen) {
      // Tapping the lit button is a close like any other — same tint teardown,
      // same caret handover.
      _closeFind();
      return;
    }
    setState(() => _findOpen = true);
  }

  void _closeFind() {
    if (!_findOpen) return;
    // Before the bar leaves the tree, not after: the bar's own dispose runs
    // while the framework is locked and can only clear the tint silently, so
    // this is the call that actually repaints the field.
    final controller = widget.controller;
    if (controller is WpFindHighlightController) {
      controller.clearFindHighlight();
    }
    setState(() => _findOpen = false);
    widget.focusNode.requestFocus();
  }

  @override
  void didUpdateWidget(WpMarkdownToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving editing closes an open find bar: it would otherwise keep a
    // replace field live over text that is now read-only.
    if (oldWidget.enabled && !widget.enabled && _findOpen) {
      final controller = widget.controller;
      if (controller is WpFindHighlightController) {
        controller.clearFindHighlight();
      }
      _findOpen = false;
    }
  }

  /// The button row alone, or side by side with [WpMarkdownToolbar.trailing]
  /// when the width allows, else stacked above it.
  Widget _withTrailing(Widget buttons) {
    final trailing = widget.trailing;
    if (trailing == null) {
      return Align(alignment: AlignmentDirectional.centerStart, child: buttons);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!constraints.hasBoundedWidth ||
            width < WpMarkdownToolbar.trailingMinRowWidth) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buttons,
              const SizedBox(height: WpSpacing.xs),
              trailing,
            ],
          );
        }
        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    width - WpMarkdownToolbar.trailingMinWidth - WpSpacing.md,
              ),
              child: buttons,
            ),
            const SizedBox(width: WpSpacing.md),
            Expanded(child: trailing),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // The button row keeps shrink-wrapping (and left-aligning) exactly as it
    // did; the column around it is what the find bar can stretch across, so
    // its two fields get a bounded width on a panel that is otherwise happy to
    // hand out an unbounded one.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _withTrailing(
          _ButtonRow(
            controller: widget.controller,
            focusNode: widget.focusNode,
            findOpen: _findOpen,
            onToggleFind: _toggleFind,
            onInsertSnippet: widget.onInsertSnippet,
            onSaveSelectionAsSnippet: widget.onSaveSelectionAsSnippet,
            testIdPrefix: widget.testIdPrefix,
            enabled: widget.enabled,
            undoController: widget.undoController,
          ),
        ),
        if (_findOpen && widget.enabled) ...[
          const SizedBox(height: WpSpacing.xs),
          WpFindReplaceBar(
            controller: widget.controller,
            onClose: _closeFind,
            testIdPrefix: widget.testIdPrefix,
          ),
        ],
      ],
    );
  }
}

/// Tab order of an editor that pairs a text field with a [WpMarkdownToolbar]:
/// the field first, the toolbar after it, whatever their order on screen
/// (#652). Wrap the field in [field] and the toolbar in [toolbar]; [group]
/// goes around both. Everything else in the group keeps its reading order
/// after the ordered ones.
abstract final class WpEditorTraversal {
  /// The focus group that applies the order. Ordered nodes come before the
  /// unordered rest, in [NumericFocusOrder].
  static Widget group({required Widget child}) =>
      FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: child);

  /// Before the text, for a title the editor shows above it.
  static Widget title(Widget child) =>
      FocusTraversalOrder(order: const NumericFocusOrder(1), child: child);

  static Widget field(Widget child) =>
      FocusTraversalOrder(order: const NumericFocusOrder(2), child: child);

  static Widget toolbar(Widget child) =>
      FocusTraversalOrder(order: const NumericFocusOrder(3), child: child);
}

class _ToolbarItem {
  const _ToolbarItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive,
    this.dividerBefore = false,
  });

  final String id;
  final IconData icon;
  final String label;

  /// Null disables the button: read-only text, or nothing left to undo.
  final VoidCallback? onTap;

  /// Non-null only for the find toggle, the one button with a sticky state.
  final bool? isActive;
  final bool dividerBefore;
}

class _ButtonRow extends StatefulWidget {
  const _ButtonRow({
    required this.controller,
    required this.focusNode,
    required this.findOpen,
    required this.onToggleFind,
    this.onInsertSnippet,
    this.onSaveSelectionAsSnippet,
    required this.testIdPrefix,
    required this.enabled,
    required this.undoController,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool findOpen;
  final VoidCallback onToggleFind;
  final VoidCallback? onInsertSnippet;
  final VoidCallback? onSaveSelectionAsSnippet;
  final String testIdPrefix;
  final bool enabled;
  final TextUndoController? undoController;

  @override
  State<_ButtonRow> createState() => _ButtonRowState();
}

class _ButtonRowState extends State<_ButtonRow> {
  final List<FocusNode> _nodes = [];

  /// The button Tab lands on: the one focused last, the first at the start.
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.undoController?.addListener(_onUndoChanged);
  }

  @override
  void didUpdateWidget(_ButtonRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.undoController != widget.undoController) {
      oldWidget.undoController?.removeListener(_onUndoChanged);
      widget.undoController?.addListener(_onUndoChanged);
    }
  }

  /// Undo and redo light up and go dark as the history changes.
  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.undoController?.removeListener(_onUndoChanged);
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Which buttons can take focus now; set by [build] before the nodes.
  List<bool> _usable = const [];

  void _ensureNodes(int count) {
    while (_nodes.length < count) {
      final index = _nodes.length;
      final node = FocusNode(debugLabel: 'ToolbarButton $index');
      node.addListener(() {
        if (node.hasFocus && _current != index) {
          setState(() => _current = index);
        }
      });
      _nodes.add(node);
    }
    // A disabled button cannot take focus, so it must not be the Tab stop
    // either: fall back to the first usable one.
    if (_current >= _usable.length || !_usable[_current]) {
      final first = _usable.indexOf(true);
      if (first != -1) _current = first;
    }
    for (var i = 0; i < _nodes.length; i++) {
      // Roving tab stop: only the current button is a Tab target, the arrow
      // keys reach the rest.
      _nodes[i].skipTraversal = i != _current;
    }
  }

  /// Focuses the usable button at [index], or the next usable one in the
  /// direction of [step]; nothing when none is left that way.
  void _focusAt(int index, {int step = 1}) {
    final count = _nodes.length;
    if (count == 0) return;
    // Clamped, not wrapped: the ends are a clear stop, Home/End jump there.
    var target = index.clamp(0, count - 1);
    while (target >= 0 && target < count && !_usable[target]) {
      target += step;
    }
    if (target < 0 || target >= count) return;
    setState(() => _current = target);
    final node = _nodes[target]..requestFocus();
    final ctx = node.context;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: target > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  int get _focused {
    final i = _nodes.indexWhere((n) => n.hasFocus);
    return i == -1 ? _current : i;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final format = WpMarkdownFormatting(
      controller: widget.controller,
      focusNode: widget.focusNode,
    );
    final mutedColor = WpColors.textMuted;
    final accent = WpColors.accent;
    final divColor = mutedColor.withValues(alpha: 0.2);
    final enabled = widget.enabled;
    VoidCallback? act(VoidCallback action) => enabled ? action : null;
    final undo = widget.undoController;

    final items = <_ToolbarItem>[
      if (undo != null) ...[
        _ToolbarItem(
          id: 'undo',
          icon: LucideIcons.undo2,
          label: l10n.markdownToolbarUndo(
            commandShortcutLabel('Z', l10n: l10n),
          ),
          onTap: enabled && undo.canUndo ? () => _run(undo.undo) : null,
        ),
        _ToolbarItem(
          id: 'redo',
          icon: LucideIcons.redo2,
          label: l10n.markdownToolbarRedo(
            commandShortcutLabel('Z', shift: true, l10n: l10n),
          ),
          onTap: enabled && undo.canRedo ? () => _run(undo.redo) : null,
        ),
      ],
      _ToolbarItem(
        id: 'bold',
        icon: LucideIcons.bold,
        label: l10n.markdownToolbarBold(
          WpMarkdownFormatting.boldShortcutLabel(l10n),
        ),
        onTap: act(format.bold),
        dividerBefore: undo != null,
      ),
      _ToolbarItem(
        id: 'italic',
        icon: LucideIcons.italic,
        label: l10n.markdownToolbarItalic(
          WpMarkdownFormatting.italicShortcutLabel(l10n),
        ),
        onTap: act(format.italic),
      ),
      _ToolbarItem(
        id: 'heading',
        icon: LucideIcons.heading,
        label: l10n.markdownToolbarHeading(
          WpMarkdownFormatting.headingShortcutLabel(l10n),
        ),
        onTap: act(format.heading),
        dividerBefore: true,
      ),
      _ToolbarItem(
        id: 'bullet-list',
        icon: LucideIcons.list,
        label: l10n.markdownToolbarBulletList(
          WpMarkdownFormatting.bulletListShortcutLabel(l10n),
        ),
        onTap: act(format.bulletList),
      ),
      _ToolbarItem(
        id: 'numbered-list',
        icon: LucideIcons.listOrdered,
        label: l10n.markdownToolbarNumberedList(
          WpMarkdownFormatting.numberedListShortcutLabel(l10n),
        ),
        onTap: act(format.numberedList),
      ),
      _ToolbarItem(
        id: 'checklist',
        icon: LucideIcons.listChecks,
        label: l10n.markdownToolbarChecklist(
          WpMarkdownFormatting.checklistShortcutLabel(l10n),
        ),
        onTap: act(format.checklist),
      ),
      _ToolbarItem(
        id: 'quote',
        icon: LucideIcons.quote,
        label: l10n.markdownToolbarQuote(
          WpMarkdownFormatting.quoteShortcutLabel(l10n),
        ),
        onTap: act(format.quote),
        dividerBefore: true,
      ),
      _ToolbarItem(
        id: 'code',
        icon: LucideIcons.code,
        label: l10n.markdownToolbarCode(
          WpMarkdownFormatting.codeShortcutLabel(l10n),
        ),
        onTap: act(format.code),
      ),
      if (widget.onInsertSnippet case final insert?)
        _ToolbarItem(
          id: 'insert-snippet',
          icon: LucideIcons.textCursorInput,
          label: l10n.markdownToolbarInsertSnippet(
            WpMarkdownFormatting.insertSnippetShortcutLabel(l10n),
          ),
          onTap: act(insert),
          dividerBefore: true,
        ),
      if (widget.onSaveSelectionAsSnippet case final save?)
        _ToolbarItem(
          id: 'save-snippet',
          icon: LucideIcons.bookmarkPlus,
          label: l10n.markdownToolbarSaveSnippet,
          onTap: act(save),
          dividerBefore: widget.onInsertSnippet == null,
        ),
      _ToolbarItem(
        id: 'find',
        icon: LucideIcons.textSearch,
        label: l10n.findReplaceToggle,
        onTap: act(widget.onToggleFind),
        isActive: widget.findOpen,
        dividerBefore: true,
      ),
    ];
    _usable = [for (final item in items) item.onTap != null];
    _ensureNodes(items.length);

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final forward = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final backward = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.dividerBefore) {
        children.add(
          ExcludeSemantics(
            child: Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
              color: divColor,
            ),
          ),
        );
      }
      children.add(
        _ToolbarButton(
          icon: item.icon,
          tooltip: item.label,
          accent: accent,
          muted: mutedColor,
          onTap: item.onTap,
          isActive: item.isActive,
          focusNode: _nodes[i],
          testId: '${widget.testIdPrefix}-toolbar-${item.id}',
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      // The identifier `<testIdPrefix>-toolbar` sits on the host's wrapper
      // (WpTextEditor), so it is not repeated here.
      label: l10n.markdownToolbarGroup,
      // No pill of its own since #1498: the buttons sit flush with the field
      // edge below, like the editor header's.
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          SingleActivator(forward): () => _focusAt(_focused + 1),
          SingleActivator(backward): () => _focusAt(_focused - 1, step: -1),
          const SingleActivator(LogicalKeyboardKey.home): () => _focusAt(0),
          const SingleActivator(LogicalKeyboardKey.end): () =>
              _focusAt(items.length - 1, step: -1),
        },
        // Wraps instead of scrolling: with 48 dp targets the bar is wider
        // than a narrow editor, and a button scrolled out of view is out
        // of reach for the mouse (#652).
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
  }

  /// Like the formatting buttons: act, then hand the caret back.
  void _run(VoidCallback action) {
    action();
    widget.focusNode.requestFocus();
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.muted,
    required this.onTap,
    required this.focusNode,
    required this.testId,
    this.isActive,
  });

  final IconData icon;
  final String tooltip;
  final Color accent;
  final Color muted;

  /// Null disables the button: read-only text, or nothing left to undo.
  final VoidCallback? onTap;
  final FocusNode focusNode;
  final String testId;

  /// Sticky pressed state — only the find toggle has one, because only it
  /// opens something that stays open. The formatting buttons act and are done.
  final bool? isActive;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_ToolbarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final active = widget.isActive ?? false;
    final highlighted =
        enabled && (_hovered || active || widget.focusNode.hasFocus);
    // Same layering as WpIconButton: one semantics node with the label, the
    // tooltip kept out of the tree so the name is not read twice, and a
    // 48 dp touch target around the compact visual (#652).
    return MergeSemantics(
      child: Semantics(
        label: widget.tooltip,
        button: true,
        enabled: enabled,
        toggled: widget.isActive,
        identifier: widget.testId,
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: WpMotion.tooltipWait,
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: WpTouchTarget(
              onTap: widget.onTap,
              child: WpFocusRing(
                focusNode: widget.focusNode,
                radius: WpRadius.sm,
                child: InkWell(
                  onTap: widget.onTap,
                  focusNode: widget.focusNode,
                  borderRadius: BorderRadius.circular(WpRadius.sm),
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: AnimatedContainer(
                    duration: WpMotion.durationFor(context, WpMotion.hoverOut),
                    padding: const EdgeInsets.all(WpSpacing.xs),
                    decoration: BoxDecoration(
                      color: highlighted
                          ? widget.accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: WpRadius.borderSm,
                    ),
                    child: Icon(
                      widget.icon,
                      size: WpIconSize.xs,
                      color: highlighted
                          ? widget.accent
                          : enabled
                          ? widget.muted
                          : widget.muted.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
