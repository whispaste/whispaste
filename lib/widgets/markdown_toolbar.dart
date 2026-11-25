import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/command_shortcut.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/text/text_undo.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/smart_mode/editor_smart_action.dart';
import 'editor_smart_action_scope.dart';
import 'editor_text_view_scope.dart';
import 'find_replace.dart';
import 'find_replace_bar.dart';
import 'searchable_list_page.dart' show WpListMenuAction, showWpListMenu;
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
/// to filter their list. Find in the text is `Ctrl/Cmd+Shift+F` instead, with
/// `F3`/`Shift+F3` for the hits (#647); the editor binds those keys and
/// reaches the bar through [WpMarkdownToolbar.findCommands]. Opening, by key
/// or button, takes a one-line selection over as the query.
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
    this.outlineOpen = false,
    this.onToggleOutline,
    this.findCommands,
    this.onFindReveal,
    this.onSmartAction,
    this.smartCommands,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The host's find keys (#647); this bar attaches to them while mounted.
  final WpFindCommands? findCommands;

  /// Brings a search hit into view while the caret stays in the text (#653).
  final ValueChanged<TextSelection>? onFindReveal;

  /// Runs a Smart Mode action on the selection (#650); null hides the
  /// button. The button opens the menu of the four actions.
  final ValueChanged<EditorSmartAction>? onSmartAction;

  /// The host's Ctrl/Cmd+J (#650); this bar answers by opening its menu.
  final WpSmartActionCommands? smartCommands;

  /// Opens or closes the host's outline panel (#645); null hides the button.
  /// The host owns the panel, so it outlives a remount of this bar.
  final VoidCallback? onToggleOutline;

  /// Whether the host's outline panel is open: the button's pressed state.
  final bool outlineOpen;

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
  final GlobalKey<WpFindReplaceBarState> _findKey = GlobalKey();

  /// What the bar opens with: the selection as the query, starting on it.
  String? _seedQuery;
  int? _seedAnchor;

  /// Whether the bar opens for a search hit (#653) rather than by key.
  bool _seedReveal = false;

  /// The button row, whose Smart Mode button anchors the Ctrl/Cmd+J menu.
  final GlobalKey<_ButtonRowState> _rowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _attachFind(widget.findCommands);
    _attachSmart(widget.smartCommands);
  }

  void _attachSmart(WpSmartActionCommands? commands) => commands?.attach(
    this,
    open: () {
      if (widget.enabled) _rowKey.currentState?._openSmart();
    },
  );

  void _attachFind(WpFindCommands? commands) => commands?.attach(
    this,
    open: _openFind,
    next: () => _stepFind(forward: true),
    previous: () => _stepFind(forward: false),
    reveal: _revealFind,
  );

  @override
  void dispose() {
    widget.findCommands?.detach(this);
    widget.smartCommands?.detach(this);
    super.dispose();
  }

  void _toggleFind() {
    if (_findOpen) {
      // Tapping the lit button is a close like any other — same tint teardown,
      // same caret handover.
      _closeFind();
      return;
    }
    _openFind();
  }

  /// Opens the bar with the selection as the query (#647); when it is open
  /// already, hands it the new selection (or has it select its query).
  void _openFind() {
    if (!widget.enabled) return;
    final controller = widget.controller;
    final query = WpFindReplaceBar.seedFrom(controller);
    final anchor = query == null ? null : controller.selection.start;
    final bar = _findKey.currentState;
    if (_findOpen && bar != null) {
      bar.seed(query, anchor: anchor);
      return;
    }
    setState(() {
      _seedQuery = query;
      _seedAnchor = anchor;
      _seedReveal = false;
      _findOpen = true;
    });
  }

  /// Opens the bar on a search hit (#653), or hands the open bar the new
  /// query; the caret stays in the text, on the hit.
  void _revealFind(String query, int? anchor) {
    if (!widget.enabled) return;
    final bar = _findKey.currentState;
    if (_findOpen && bar != null) {
      bar.reveal(query, anchor: anchor);
      return;
    }
    setState(() {
      _seedQuery = query;
      _seedAnchor = anchor;
      _seedReveal = true;
      _findOpen = true;
    });
  }

  /// F3 / Shift+F3: steps when the bar is open, else opens it, which already
  /// lands on the hit at the caret.
  void _stepFind({required bool forward}) {
    final bar = _findKey.currentState;
    if (!_findOpen || bar == null) {
      _openFind();
      return;
    }
    if (forward) {
      bar.next();
    } else {
      bar.previous();
    }
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
    if (oldWidget.findCommands != widget.findCommands) {
      oldWidget.findCommands?.detach(this);
      _attachFind(widget.findCommands);
    }
    if (oldWidget.smartCommands != widget.smartCommands) {
      oldWidget.smartCommands?.detach(this);
      _attachSmart(widget.smartCommands);
    }
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
        // The buttons come first: the tags only share the line when the
        // whole bar still fits beside them, else they move below (#1845).
        if (!constraints.hasBoundedWidth ||
            width < WpMarkdownToolbar.trailingMinRowWidth ||
            width - WpMarkdownToolbar.trailingMinWidth - WpSpacing.md <
                _fullButtonsWidth) {
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

  /// Width of the whole button row on one line, as [_ButtonRow] lays it
  /// out: undo/redo, eight formatting buttons, the snippet buttons, find
  /// and text view, with a divider between groups.
  double get _fullButtonsWidth {
    final undo = widget.undoController != null;
    final snippets =
        (widget.onInsertSnippet != null ? 1 : 0) +
        (widget.onSaveSelectionAsSnippet != null ? 1 : 0);
    final outline = widget.onToggleOutline != null ? 1 : 0;
    final smart = widget.onSmartAction != null ? 1 : 0;
    final buttons = (undo ? 2 : 0) + 8 + snippets + smart + 2 + outline;
    final dividers = (undo ? 1 : 0) + 2 + (snippets > 0 ? 1 : 0) + smart + 1;
    return buttons * _ButtonRowState._buttonExtent +
        dividers * _ButtonRowState._dividerExtent;
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
            key: _rowKey,
            onSmartAction: widget.onSmartAction,
            controller: widget.controller,
            focusNode: widget.focusNode,
            findOpen: _findOpen,
            onToggleFind: _toggleFind,
            onInsertSnippet: widget.onInsertSnippet,
            onSaveSelectionAsSnippet: widget.onSaveSelectionAsSnippet,
            testIdPrefix: widget.testIdPrefix,
            enabled: widget.enabled,
            undoController: widget.undoController,
            outlineOpen: widget.outlineOpen,
            onToggleOutline: widget.onToggleOutline,
          ),
        ),
        if (_findOpen && widget.enabled) ...[
          const SizedBox(height: WpSpacing.xs),
          WpFindReplaceBar(
            key: _findKey,
            controller: widget.controller,
            onClose: _closeFind,
            testIdPrefix: widget.testIdPrefix,
            initialQuery: _seedQuery,
            initialAnchor: _seedAnchor,
            revealInitial: _seedReveal,
            onReveal: widget.onFindReveal,
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

  /// Non-null only for the find and outline toggles, the buttons with a
  /// sticky state.
  final bool? isActive;
  final bool dividerBefore;
}

class _ButtonRow extends StatefulWidget {
  const _ButtonRow({
    super.key,
    this.onSmartAction,
    required this.controller,
    required this.focusNode,
    required this.findOpen,
    required this.onToggleFind,
    this.onInsertSnippet,
    this.onSaveSelectionAsSnippet,
    required this.testIdPrefix,
    required this.enabled,
    required this.undoController,
    required this.outlineOpen,
    required this.onToggleOutline,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool outlineOpen;
  final VoidCallback? onToggleOutline;
  final bool findOpen;
  final VoidCallback onToggleFind;
  final VoidCallback? onInsertSnippet;
  final VoidCallback? onSaveSelectionAsSnippet;
  final ValueChanged<EditorSmartAction>? onSmartAction;
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
      // Smart Mode on the selection or the paragraph at the caret (#650).
      if (widget.onSmartAction != null)
        _ToolbarItem(
          id: 'smart-actions',
          icon: LucideIcons.sparkles,
          label: l10n.editorSmartActionMenu(
            editorSmartActionShortcutLabel(l10n),
          ),
          onTap: act(_openSmart),
          dividerBefore: true,
        ),
      _ToolbarItem(
        id: 'find',
        icon: LucideIcons.textSearch,
        label: l10n.findReplaceToggle(WpFindReplaceBar.openShortcutLabel(l10n)),
        onTap: act(widget.onToggleFind),
        isActive: widget.findOpen,
        dividerBefore: true,
      ),
      // The headings of the text, to jump to (#645).
      if (widget.onToggleOutline case final toggle?)
        _ToolbarItem(
          id: 'outline',
          icon: LucideIcons.listTree,
          // The key of WpTextEditor.outlineActivator.
          label: l10n.editorOutlineToggle(
            commandShortcutLabel('G', shift: true, l10n: l10n),
          ),
          onTap: act(toggle),
          isActive: widget.outlineOpen,
        ),
      // Text size, line length and spacing of the body (#648). Here because
      // all three editors share this bar; usable while reading, too.
      _ToolbarItem(
        id: 'text-view',
        icon: LucideIcons.aLargeSmall,
        label: l10n.editorTextViewMenu,
        onTap: _openTextView,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => _buildRow(
        context,
        items,
        constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity,
        mutedColor: mutedColor,
        accent: accent,
        divColor: divColor,
      ),
    );
  }

  /// Width of one button (its 48 px touch target) and of a group divider.
  static const double _buttonExtent = 48;
  static const double _dividerExtent = 1 + 2 * WpSpacing.xxs;

  /// How many [items] fit in [maxWidth] on one line; the rest go into a
  /// "More" menu at the end, which then needs room of its own.
  static int _fitting(List<_ToolbarItem> items, double maxWidth) {
    double widthOf(int count) {
      var w = 0.0;
      for (var i = 0; i < count; i++) {
        if (items[i].dividerBefore && i > 0) w += _dividerExtent;
        w += _buttonExtent;
      }
      return w;
    }

    if (widthOf(items.length) <= maxWidth) return items.length;
    var count = items.length - 1;
    while (count > 0 &&
        widthOf(count) + _dividerExtent + _buttonExtent > maxWidth) {
      count--;
    }
    return count;
  }

  Widget _buildRow(
    BuildContext context,
    List<_ToolbarItem> items,
    double maxWidth, {
    required Color mutedColor,
    required Color accent,
    required Color divColor,
  }) {
    final l10n = L10n.of(context);
    // One line on every width: what does not fit moves into "More" instead
    // of wrapping, so a short editor keeps its height for the text (#1845,
    // notes at 800x600 showed four rows of buttons and no text).
    final fit = _fitting(items, maxWidth);
    final hidden = items.sublist(fit);
    final shown = [
      ...items.take(fit),
      if (hidden.isNotEmpty)
        _ToolbarItem(
          id: 'more',
          icon: LucideIcons.ellipsis,
          label: l10n.dockOverflow,
          onTap: () => _openMore(hidden),
          dividerBefore: true,
        ),
    ];
    _usable = [for (final item in shown) item.onTap != null];
    _textViewIndex = fit == items.length ? items.length - 1 : shown.length - 1;
    // The Smart Mode menu opens under its own button, or under "More" when
    // that button moved in there.
    final smart = items.indexWhere((item) => item.id == 'smart-actions');
    _smartIndex = smart < 0
        ? -1
        : smart < fit
        ? smart
        : shown.length - 1;
    _ensureNodes(shown.length);

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final forward = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final backward = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final item = shown[i];
      if (item.dividerBefore && i > 0) {
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
              _focusAt(shown.length - 1, step: -1),
        },
        // Neither wraps nor scrolls: a scrolled-out button is out of reach
        // for the mouse (#652), and wrapping took the text's height on a
        // short editor; the "More" menu holds what does not fit.
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  /// Index of the text view button, the last item; set by [build].
  int _textViewIndex = 0;

  /// Opens the text view menu under its button.
  void _openTextView() {
    final index = _textViewIndex;
    final buttonContext = index < _nodes.length ? _nodes[index].context : null;
    if (buttonContext == null || !buttonContext.mounted) return;
    showWpListMenu(buttonContext, editorTextViewMenuActions(buttonContext));
  }

  /// Index of the Smart Mode button (or "More" holding it); -1 without one.
  int _smartIndex = -1;

  /// Opens the menu of the four Smart Mode actions (#650) under its button;
  /// by click and by Ctrl/Cmd+J alike.
  void _openSmart() {
    final onAction = widget.onSmartAction;
    final index = _smartIndex;
    if (onAction == null || index < 0 || index >= _nodes.length) return;
    final buttonContext = _nodes[index].context;
    if (buttonContext == null || !buttonContext.mounted) return;
    showWpListMenu(
      buttonContext,
      editorSmartActionMenuActions(
        buttonContext,
        testIdPrefix: widget.testIdPrefix,
        onAction: onAction,
      ),
    );
  }

  /// The buttons that did not fit, as a menu under the "More" button.
  void _openMore(List<_ToolbarItem> hidden) {
    final index = _nodes.length - 1;
    final buttonContext = index >= 0 ? _nodes[index].context : null;
    if (buttonContext == null || !buttonContext.mounted) return;
    showWpListMenu(buttonContext, [
      for (final item in hidden)
        WpListMenuAction(
          itemKey: ValueKey('${widget.testIdPrefix}-toolbar-more-${item.id}'),
          label: item.label,
          icon: item.icon,
          checked: item.isActive,
          enabled: item.onTap != null,
          dividerBefore: item.dividerBefore && item != hidden.first,
          onSelected: item.onTap ?? () {},
        ),
    ]);
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

  /// Sticky pressed state — only the find and outline toggles have one,
  /// because only they open something that stays open. The formatting buttons act and are done.
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
