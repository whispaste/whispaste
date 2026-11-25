import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/accessibility/announce.dart';
import '../core/config/command_shortcut.dart';
import '../core/data/content_metadata.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/text/entry_link.dart';
import '../core/text/markdown_outline.dart';
import '../core/text/text_stats.dart';
import '../core/text/text_undo.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/smart_mode/editor_smart_action.dart';
import 'editor_smart_action_scope.dart';
import 'editor_spell_check.dart';
import 'editor_text_view_scope.dart';
import 'searchable_list_page.dart' show showWpListMenu;
import 'find_replace_bar.dart';
import 'find_reveal.dart';
import 'markdown_toolbar.dart';
import 'page_shell.dart' show WpPageFrame;
import 'wp_editor_view_memory.dart';
import 'wp_fill_column.dart';
import 'wp_outline_panel.dart';
import 'wp_save_status.dart';
import 'wp_text_field.dart';

/// The one text editor of the app: the transcript in History, the note body in
/// Notes and the snippet body in Snippets are all this block (#638).
///
/// It owns everything the three used to assemble on their own, each a little
/// differently:
///
/// * **Toolbar** — [WpMarkdownToolbar] with undo/redo, formatting and
///   find/replace, always in the same place above the text. While the text is
///   only being read ([editable] false) the bar stays and is merely disabled,
///   so switching between reading and editing moves no control.
/// * **Undo** — the page's [TextUndoController] on [controller] (or one of
///   the editor's own when the page keeps none), driven by Ctrl/Cmd+Z, Ctrl+Y
///   and the toolbar's buttons alike. Typing is grouped, every toolbar action,
///   replace and dictation is a step of its own (#651).
/// * **Shortcuts** — [shortcutBindings]: the formatting keys plus Ctrl/Cmd+S
///   for [onSave], identical on every surface and only live while the field
///   itself has a key event to answer.
/// * **Status line and save timing** — the footer line names words,
///   characters and reading time, and the words and characters of a
///   selection, recounted while typing at most every [counterThrottle]
///   (#649); [statsActivator] reads them out for screen readers. Whenever
///   there is something to save it names the one rule all three share:
///   drafts are kept while typing, Ctrl/Cmd+S saves.
///
/// It is the editor slot of `WpEditorPane` and draws the page inset itself
/// on every surface (#1498): tool row, writing surface and status line start
/// and end on the same lines in all three editors. What differs per surface
/// is only which slots are on: the tags in [toolbarTrailing], the bar itself
/// ([showToolbar], disabled while not [editable]), [betweenToolbarAndField],
/// [fieldOverlays] (in the left inset) and [readView]. [variant] only says
/// whether the surface fills its box (`bare`) or grows with its text
/// (`passage`); both are the same card surface.
///
/// * **Place per entry** — with [viewMemory] the body keeps caret or
///   selection and scroll place of that entry ([WpEditorViewMemory], #678),
///   in reading and in editing alike.
/// * **Text view** — text size, line length and line spacing are one view
///   for all three editors ([WpEditorText], #648): Ctrl/Cmd+Plus, Minus and 0
///   anywhere in the block, or the toolbar's text view menu. Only the body
///   is scaled, so the toolbar and the status line stay in reach.
/// * **Outline** — the toolbar's outline button or Ctrl/Cmd+Shift+G opens
///   [WpOutlinePanel] between the bar and the text: every heading, indented
///   by level; choosing one puts the caret at its end and the focus back in
///   the text (#645). [nextHeadingActivators] and
///   [previousHeadingActivators] step from heading to heading with the panel
///   open or closed.
/// * **Find and replace** — Ctrl/Cmd+Shift+F opens the toolbar's find bar
///   with a one-line selection as the query, F3 and Shift+F3 step through the
///   hits from the text as from the bar (#647). Ctrl/Cmd+F stays the list
///   search of the page around the editor.
class WpTextEditor extends StatefulWidget {
  const WpTextEditor({
    super.key,
    required this.testId,
    required this.controller,
    required this.focusNode,
    required this.variant,
    this.editable = true,
    this.readOnly = false,
    this.onSave,
    this.fieldKey,
    this.toolbarKey,
    this.toolbarTrailing,
    this.hintText,
    this.semanticsLabel,
    this.autofocus = false,
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.scrollToEnd,
    this.onSubmitted,
    this.betweenToolbarAndField,
    this.fieldOverlays = const <Widget>[],
    this.readView,
    this.readText,
    this.externalWordCount = false,
    this.wordCount,
    this.showToolbar = true,
    this.fieldOverride,
    this.extraShortcuts = const <ShortcutActivator, VoidCallback>{},
    this.viewMemory,
    this.saveStatus,
    this.onInsertSnippet,
    this.onSaveSelectionAsSnippet,
    this.onPickLink,
    this.onSmartAction,
  });

  /// Runs a Smart Mode action on the selection or the paragraph at the caret
  /// (#650): a toolbar menu, Ctrl/Cmd+J and four rows in the field's context
  /// menu. Null where the surface offers none (read-only text).
  final ValueChanged<EditorSmartAction>? onSmartAction;

  /// The page's save status ([WpSaveStatus]), drawn first in the status line
  /// under the surface in every editor as `<testId>-save-status` (#1498).
  /// Every editable editor passes one, so "Saved" after a pause or Ctrl/Cmd+S
  /// reads the same in Recordings, Notes and Snippets.
  final ValueListenable<WpSaveStatus>? saveStatus;

  /// Prefix of every semantics identifier inside the block:
  /// `<testId>-toolbar`, `<testId>-toolbar-<action>`, `<testId>-field`,
  /// `<testId>-status-line`, `<testId>-counter`, `<testId>-selection-count`,
  /// `<testId>-save-hint`, `<testId>-save-status`.
  final String testId;

  final TextEditingController controller;
  final FocusNode focusNode;
  final WpTextFieldVariant variant;

  /// False while the text is only being read (History outside edit mode).
  /// The toolbar stays in place, disabled; [readView] stands in for the field.
  final bool editable;

  /// True for text that is shown in the field but must not change (the notes
  /// trash, #656): the field stays, formatting and save keys are unbound.
  /// Pair it with `showToolbar: false` and a null [onSave].
  final bool readOnly;

  /// What Ctrl/Cmd+S does. Null, the key is not bound and the footer names no
  /// save shortcut.
  final VoidCallback? onSave;

  final Key? fieldKey;

  /// Changing it remounts only the toolbar, which owns the find/replace bar's
  /// open flag and both of its fields — e.g. per note, so note B never opens
  /// with note A's query one click from rewriting it. The field itself stays
  /// mounted (its scroll position and caret logic survive).
  final Key? toolbarKey;

  /// Shares the toolbar's row where the width allows (the note's tags), see
  /// [WpMarkdownToolbar.trailing]. Shown on its own when [showToolbar] is
  /// false.
  final Widget? toolbarTrailing;
  final String? hintText;
  final String? semanticsLabel;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;

  /// `form`/`passage`: the field takes the height left between toolbar and
  /// footer, so the footer sits at the bottom of a bounded parent instead of
  /// below a fixed line count (the static snippet).
  final bool expands;
  final Listenable? scrollToEnd;
  final ValueChanged<String>? onSubmitted;

  /// Sits between the bar and the text (the note's attached images).
  final Widget? betweenToolbarAndField;

  /// Positioned children stacked over the field (the note's quick-note marks).
  final List<Widget> fieldOverlays;

  /// The read-only rendering used while [editable] is false. It must keep the
  /// field's geometry so the text does not move when editing starts.
  final Widget? readView;

  /// The text being read while [editable] is false — the counter counts it.
  final String? readText;

  /// True when the word count of the read text comes from outside (the
  /// metadata index of a long recording): while not [editable] the counter
  /// then shows [wordCount] instead of counting [readText] itself, and counts
  /// only while that is still unknown. While editing, the text is always
  /// counted live, throttled to [counterThrottle].
  final bool externalWordCount;
  final int? wordCount;

  /// False hides the bar entirely, for text that can never be edited (the
  /// trash view). There is no mode switch there, so nothing can move.
  final bool showToolbar;

  /// Stands in for the plain text field while the text is edited — the note's
  /// long-text editor, which builds only the visible paragraphs. It edits the
  /// same [controller] and [focusNode], so toolbar, shortcuts, counter and save
  /// rule stay this block's own.
  final Widget? fieldOverride;

  /// Keys only one surface has (the note's "Go to paragraph"), bound next to
  /// the shared ones.
  final Map<ShortcutActivator, VoidCallback> extraShortcuts;

  /// The entry whose caret and scroll place the body remembers (#678); null
  /// where there is no stored entry yet (a new snippet).
  final ContentKey? viewMemory;

  /// Opens the snippet picker for this editor (#664): a toolbar button and
  /// the insert-snippet key. Null where the surface offers none.
  final VoidCallback? onInsertSnippet;

  /// Saves the selected text as a new snippet (#664): a toolbar button only.
  final VoidCallback? onSaveSelectionAsSnippet;

  /// Opens the link chooser when `[[` is typed (#660) and answers with the
  /// link text to put in place of the two brackets (`[[note:<id>|Name]]`),
  /// or null to keep them. Only typing opens it, never paste, undo or
  /// dictation. Null where the surface offers no links.
  final Future<String?> Function()? onPickLink;

  /// The keys every editor answers, in one place: formatting from
  /// [WpMarkdownFormatting] and Ctrl/Cmd+S for [onSave].
  static Map<ShortcutActivator, VoidCallback> shortcutBindings({
    required TextEditingController controller,
    required FocusNode focusNode,
    VoidCallback? onSave,
    VoidCallback? onInsertSnippet,
  }) => <ShortcutActivator, VoidCallback>{
    ...WpMarkdownFormatting(
      controller: controller,
      focusNode: focusNode,
    ).shortcutBindings(onInsertSnippet: onInsertSnippet),
    saveActivator: ?onSave,
  };

  /// Least height of a growing writing surface at 100 % text size, scaled
  /// with the text (#1371): about four lines of body text stay visible when
  /// the window is too short for tool row, status line and text together.
  static const double minSurfaceExtent = 96;

  /// Controllers whose next focus gain keeps the caret (#664).
  static final Expando<bool> _keepCaret = Expando('keepCaret');

  /// Marks the next focus gain of the editor on [controller] as a return
  /// from a dialog it opens (the snippet chooser): the caret or selection
  /// stays where it is instead of moving to the end. Call it before the
  /// dialog opens, because the route may hand focus back on its own when it
  /// closes; [clearKeepCaret] drops a mark no focus gain used.
  static void keepCaretOnNextFocus(TextEditingController controller) =>
      _keepCaret[controller] = true;

  /// Drops the mark set by [keepCaretOnNextFocus].
  static void clearKeepCaret(TextEditingController controller) =>
      _keepCaret[controller] = null;

  /// Ctrl+S on Windows/Linux, Cmd+S on macOS.
  static SingleActivator get saveActivator =>
      commandActivator(LogicalKeyboardKey.keyS);

  /// Ctrl/Cmd+Shift+G: opens the outline and puts the focus on the heading
  /// at the caret (#645). G as in "go to", next to the note's Ctrl/Cmd+G
  /// "Go to paragraph"; the Ctrl/Cmd+Shift letters of the formatting keys
  /// are taken, and Ctrl+Alt is AltGr on Windows.
  static SingleActivator get outlineActivator =>
      commandActivator(LogicalKeyboardKey.keyG, shift: true);

  /// Next heading: Ctrl/Cmd+Page Down everywhere, and on macOS also
  /// Option+Cmd+Down, because most Mac keyboards have no Page Down key.
  /// Alt+arrow and Ctrl/Cmd+Shift+arrow already move or select by paragraph
  /// in text fields, Ctrl+Alt+arrow switches workspaces on GNOME and is
  /// VoiceOver's own key on macOS (Ctrl+Option).
  static List<SingleActivator> get nextHeadingActivators => [
    commandActivator(LogicalKeyboardKey.pageDown),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
        meta: true,
        alt: true,
      ),
  ];

  /// Previous heading, the mirror of [nextHeadingActivators].
  static List<SingleActivator> get previousHeadingActivators => [
    commandActivator(LogicalKeyboardKey.pageUp),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true, alt: true),
  ];

  /// How the first of [nextHeadingActivators] the platform's keyboards have
  /// is spelled: `⌥⌘↓` on macOS, `Strg+Bild runter` elsewhere.
  static String nextHeadingShortcutLabel(L10n l10n) =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? '⌥⌘↓'
      : commandShortcutLabel(l10n.shortcutKeyPageDown, l10n: l10n);

  /// How the first of [previousHeadingActivators] is spelled.
  static String previousHeadingShortcutLabel(L10n l10n) =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? '⌥⌘↑'
      : commandShortcutLabel(l10n.shortcutKeyPageUp, l10n: l10n);

  /// Ctrl/Cmd+Shift+W reads the status line's counts out (#649), W as in
  /// "words". The formatting keys hold most Ctrl/Cmd+Shift letters, and
  /// Ctrl+Shift+U is the Unicode input of IBus on Linux.
  /// Next misspelled word (#670): F7, the usual key for spelling.
  static const List<SingleActivator> nextSpellErrorActivators = [
    SingleActivator(LogicalKeyboardKey.f7),
  ];

  /// Previous misspelled word.
  static const List<SingleActivator> previousSpellErrorActivators = [
    SingleActivator(LogicalKeyboardKey.f7, shift: true),
  ];

  /// The context menu from the keyboard: Shift+F10 and the menu key.
  static const List<SingleActivator> contextMenuActivators = [
    SingleActivator(LogicalKeyboardKey.f10, shift: true),
    SingleActivator(LogicalKeyboardKey.contextMenu),
  ];

  static SingleActivator get statsActivator =>
      commandActivator(LogicalKeyboardKey.keyW, shift: true);

  /// The status line recounts at most this often while typing or selecting
  /// (#649), so even a very long text never costs a count per key.
  static const Duration counterThrottle = Duration(milliseconds: 250);

  /// Keeps a group ("67 words") on one line, so a narrow panel wraps between
  /// the facts, never inside one.
  static String _group(String s) => s.replaceAll(' ', ' ');

  // ~200 wpm, rounded: a short text reads "< 1 min", not "1 min".
  static String _readingTime(L10n l10n, EditorTextStats stats) =>
      stats.readingMinutes < 1
      ? l10n.historyReadingTimeUnder1
      : l10n.historyReadingTime(stats.readingMinutes);

  /// "67 words · 412 characters · 1 min read".
  static String counterLabel(L10n l10n, EditorTextStats stats) => [
    l10n.historyWordCount(stats.words),
    l10n.editorCharacterCount(stats.characters),
    _readingTime(l10n, stats),
  ].map(_group).join(' · ');

  /// "Selection: 12 words · 80 characters", or null without a selection.
  static String? selectionLabel(L10n l10n, EditorTextStats stats) =>
      stats.hasSelection
      ? l10n.editorSelectionCount(
          _group(l10n.historyWordCount(stats.selectionWords)),
          _group(l10n.editorCharacterCount(stats.selectionCharacters)),
        )
      : null;

  /// What [statsActivator] announces: the counts of the text and, with a
  /// selection, those of the selection.
  static String statsAnnouncement(L10n l10n, EditorTextStats stats) {
    if (stats.characters == 0) return l10n.editorStatsEmpty;
    final text = l10n.editorStatsAnnouncement(
      l10n.historyWordCount(stats.words),
      l10n.editorCharacterCount(stats.characters),
      _readingTime(l10n, stats),
    );
    if (!stats.hasSelection) return text;
    final selection = l10n.editorStatsSelectionAnnouncement(
      l10n.historyWordCount(stats.selectionWords),
      l10n.editorCharacterCount(stats.selectionCharacters),
    );
    return '$text $selection';
  }

  @override
  State<WpTextEditor> createState() => _WpTextEditorState();
}

/// Page inset left and right: the editor owns it, see [WpTextEditor].
const EdgeInsets _sideInset = EdgeInsets.symmetric(
  horizontal: WpPageFrame.inset,
);

class _WpTextEditorState extends State<WpTextEditor> {
  /// Only when the page registered no history on its controller.
  TextUndoController? _ownUndo;

  TextUndoController get _undo =>
      TextUndoController.of(widget.controller) ?? _adopt();

  TextUndoController _adopt() =>
      _ownUndo = TextUndoController(widget.controller);

  /// True from a pointer press on the body until the frame after it, so the
  /// focus change it causes is recognised as a click (the caret then stays
  /// where the click put it) and not as keyboard focus.
  bool _pointerOnBody = false;

  /// Whether the outline panel is open (#645). Kept here, not in the
  /// toolbar, so it stays open when a note switch remounts the toolbar.
  bool _outlineOpen = false;

  /// Whether [WpTextEditor.focusNode] held the focus at its last notice.
  bool _hadFocus = false;
  final GlobalKey<WpOutlinePanelState> _outlineKey = GlobalKey();

  /// The find keys of the text (#647), answered by whichever toolbar is
  /// mounted: a note switch remounts it, the keys stay bound here.
  final WpFindCommands _findCommands = WpFindCommands();

  /// The text at the last controller notice, to tell a typed `[[` from a
  /// paste (#660).
  String _lastText = '';
  bool _picking = false;

  /// The Smart Mode key (#650), answered by the mounted toolbar.
  final WpSmartActionCommands _smartCommands = WpSmartActionCommands();

  ValueChanged<EditorSmartAction>? get _smartAction =>
      widget.editable && !widget.readOnly ? widget.onSmartAction : null;

  /// Ctrl/Cmd+J: the menu under the toolbar's button, or under the text
  /// where no toolbar is shown.
  void _openSmartMenu() {
    final onAction = _smartAction;
    if (onAction == null || _smartCommands.open()) return;
    final anchor = widget.focusNode.context ?? context;
    showWpListMenu(
      anchor,
      editorSmartActionMenuActions(
        anchor,
        testIdPrefix: widget.testId,
        onAction: onAction,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _undo;
    _lastText = widget.controller.text;
    widget.controller.addListener(_watchLinkTrigger);
    _hadFocus = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocusChanged);
    WpFindReveal.changes.addListener(_scheduleReveal);
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(WpTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ownUndo?.dispose();
      _ownUndo = null;
      _undo;
      oldWidget.controller.removeListener(_watchLinkTrigger);
      widget.controller.addListener(_watchLinkTrigger);
      _lastText = widget.controller.text;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
      _hadFocus = widget.focusNode.hasFocus;
    }
    // Reading only: the outline goes with the rest of the bar's tools, as
    // the find bar does.
    if (oldWidget.editable && !widget.editable) _outlineOpen = false;
    if (oldWidget.viewMemory != widget.viewMemory ||
        oldWidget.editable != widget.editable ||
        oldWidget.readOnly != widget.readOnly) {
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    WpFindReveal.changes.removeListener(_scheduleReveal);
    widget.controller.removeListener(_watchLinkTrigger);
    _stopWaiting();
    widget.focusNode.removeListener(_onFocusChanged);
    _ownUndo?.dispose();
    super.dispose();
  }

  // ── Links (#660) ──────────────────────────────────────────────────────

  void _watchLinkTrigger() {
    final value = widget.controller.value;
    final before = _lastText;
    _lastText = value.text;
    final pick = widget.onPickLink;
    if (pick == null ||
        _picking ||
        !widget.editable ||
        widget.readOnly ||
        !widget.focusNode.hasFocus ||
        value.composing.isValid ||
        !value.selection.isCollapsed) {
      return;
    }
    final start = typedLinkTrigger(
      before,
      value.text,
      value.selection.extentOffset,
    );
    if (start == null) return;
    // Not inside the notification: the dialog would take the focus while
    // the field is still handling the key.
    _picking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pickLink(pick, start));
    });
  }

  Future<void> _pickLink(Future<String?> Function() pick, int start) async {
    try {
      if (!mounted) return;
      final link = await pick();
      if (!mounted) return;
      final c = widget.controller;
      final text = c.text;
      // The brackets must still be where they were typed; otherwise the
      // text changed under the dialog (an autosave reload) and stays as is.
      final intact =
          start + 2 <= text.length && text.substring(start, start + 2) == '[[';
      if (link != null && intact) {
        TextUndoController.command(
          c,
          () => c.value = TextEditingValue(
            text: text.replaceRange(start, start + 2, link),
            selection: TextSelection.collapsed(offset: start + link.length),
          ),
        );
      }
      WpTextEditor.keepCaretOnNextFocus(c);
      widget.focusNode.requestFocus();
    } finally {
      _picking = false;
    }
  }

  /// Keyboard focus (Tab, shortcut, autofocus) puts the caret at the end of
  /// the text; a click keeps the position it set itself (#1498
  /// F-caret-edit-mode: typing used to land inside existing text). Focus
  /// handed back by a dialog the editor opened keeps the caret too
  /// ([WpTextEditor.keepCaretOnNextFocus]).
  ///
  /// Only a real gain counts: the node also notifies when the focus moves
  /// between its own descendants, which the long-note editor does whenever
  /// the caret enters another paragraph. Taken for a gain, that sent a
  /// caret placed by a jump (outline, go to paragraph) to the end (#645).
  void _onFocusChanged() {
    final has = widget.focusNode.hasFocus;
    final gained = has && !_hadFocus;
    _hadFocus = has;
    if (!gained) return;
    final c = widget.controller;
    final returning = WpTextEditor._keepCaret[c] ?? false;
    WpTextEditor._keepCaret[c] = null;
    if (returning || !widget.editable || _pointerOnBody) return;
    // A real range stays: a toolbar button hands focus back to the field
    // after formatting the selection, and that selection must survive.
    if (c.selection.isValid && !c.selection.isCollapsed) return;
    c.selection = TextSelection.collapsed(offset: c.text.length);
  }

  // ── Search hit (#653) ────────────────────────────────────────────────

  /// Looks for a search hit left for this entry once the frame is built:
  /// by then the toolbar is mounted and the entry's text is loaded.
  void _scheduleReveal() {
    if (widget.viewMemory == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeReveal());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _takeReveal() {
    final entry = widget.viewMemory;
    if (!mounted || entry == null || !_outlineAvailable || widget.readOnly) {
      return;
    }
    final request = WpFindReveal.peek(entry);
    if (request == null) {
      _stopWaiting();
      return;
    }
    final c = widget.controller;
    // The text may still be on its way (a recording loads after its row is
    // chosen): wait for it rather than open the bar on nothing.
    if (!c.text.toLowerCase().contains(request.query.toLowerCase())) {
      _waitingFor?.removeListener(_scheduleReveal);
      _waitingFor = c..addListener(_scheduleReveal);
      return;
    }
    _stopWaiting();
    WpFindReveal.take(entry);
    _findCommands.reveal(request.query, anchor: request.anchor);
  }

  /// The controller watched for the text a waiting search hit needs.
  TextEditingController? _waitingFor;

  void _stopWaiting() {
    _waitingFor?.removeListener(_scheduleReveal);
    _waitingFor = null;
  }

  /// The find bar's hit, while the caret stays in the text: placed so the
  /// entry's remembered place does not override it, focused, on screen.
  void _revealAt(TextSelection selection) {
    WpEditorViewMemory.place(widget.controller, selection);
    _returnToText();
    _bringIntoView(selection.start);
  }

  /// Scrolls the plain field to [offset]; the long-note editor follows the
  /// caret on its own.
  void _bringIntoView(int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editable = widget.focusNode.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (editable != null && editable.mounted) {
        editable.bringIntoView(TextPosition(offset: offset));
      }
    });
  }

  // ── Outline (#645) ───────────────────────────────────────────────────

  bool get _outlineAvailable => widget.editable && widget.showToolbar;

  void _toggleOutline() {
    if (_outlineOpen) {
      _closeOutline();
    } else {
      _openOutline();
    }
  }

  /// Opens the panel (if closed) and moves the focus onto the heading at the
  /// caret; with no heading the focus stays and the empty notice is read.
  void _openOutline() {
    if (!_outlineAvailable) return;
    // Also when already open: the rebuild is the frame the focus move
    // below waits for.
    setState(() => _outlineOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focused = _outlineKey.currentState?.focusList() ?? false;
      if (!focused) _announce(L10n.of(context).editorOutlineEmpty);
    });
  }

  void _closeOutline() {
    if (!_outlineOpen) return;
    setState(() => _outlineOpen = false);
    _returnToText();
  }

  /// Hands the focus back to the text with the caret where it is.
  void _returnToText() {
    if (!widget.focusNode.hasFocus) {
      WpTextEditor.keepCaretOnNextFocus(widget.controller);
    }
    widget.focusNode.requestFocus();
  }

  /// Puts the caret at the end of [heading], the focus in the text and the
  /// line on screen. The plain field is scrolled here; the long-note editor
  /// follows the caret on its own (and opens a folded section around it).
  void _jumpTo(OutlineHeading heading) {
    final c = widget.controller;
    final offset = heading.end.clamp(0, c.text.length);
    c.selection = TextSelection.collapsed(offset: offset);
    _returnToText();
    _bringIntoView(offset);
    final l10n = L10n.of(context);
    _announce(
      l10n.editorOutlineJumped(
        heading.title.isEmpty ? l10n.editorOutlineUntitled : heading.title,
        heading.level,
      ),
    );
  }

  /// Next or previous heading from the caret; at the end a notice instead.
  void _stepHeading({required bool forward}) {
    if (!widget.editable) return;
    final c = widget.controller;
    final text = c.text;
    final outline = markdownOutline(text);
    final sel = c.selection;
    final caret = sel.isValid ? sel.extentOffset.clamp(0, text.length) : 0;
    final index = forward
        ? nextHeadingIndex(outline, caret)
        : previousHeadingIndex(outline, text, caret);
    if (index == null) {
      final l10n = L10n.of(context);
      _announce(
        outline.isEmpty
            ? l10n.editorOutlineEmpty
            : forward
            ? l10n.editorOutlineNoNext
            : l10n.editorOutlineNoPrevious,
      );
      return;
    }
    _jumpTo(outline[index]);
  }

  // ── Counts (#649) ─────────────────────────────────────────────────────

  /// The counts as they are now, not as the throttled line last drew them.
  EditorTextStats _currentStats() {
    if (widget.editable) {
      final c = widget.controller;
      return EditorTextStats.of(c.text, selection: c.selection);
    }
    return EditorTextStats.of(
      widget.readText ?? '',
      knownWords: widget.externalWordCount ? widget.wordCount : null,
    );
  }

  // ── Spell check (#670) ────────────────────────────────────────────────

  final GlobalKey<WpEditorSpellCheckState> _spellKey = GlobalKey();

  /// Selects the next (or previous) misspelled word and reads it out with
  /// its suggestions, so the check works without seeing the underline.
  Future<void> _stepSpell({required bool forward}) async {
    final spell = _spellKey.currentState;
    if (spell == null || !spell.active) return;
    final l10n = L10n.of(context);
    final word = spell.step(forward: forward);
    if (word == null) {
      _announce(l10n.spellCheckNoErrors);
      return;
    }
    final c = widget.controller;
    c.selection = TextSelection(baseOffset: word.start, extentOffset: word.end);
    _returnToText();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editable = widget.focusNode.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (editable != null && editable.mounted) {
        editable.bringIntoView(TextPosition(offset: word.end));
      }
    });
    final suggestions = await spell.suggestionsFor(word);
    if (!mounted) return;
    _announce(
      suggestions.isEmpty
          ? l10n.spellCheckAnnounceNoSuggestions(word.text)
          : l10n.spellCheckAnnounce(word.text, suggestions.join(', ')),
    );
  }

  /// Opens the focused field's context menu from the keyboard (Shift+F10,
  /// the menu key), where the suggestions for the word at the caret sit.
  void _openContextMenu() {
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.showToolbar();
  }

  /// Spell suggestions first (#670), then the platform's entries, then the
  /// Smart Mode actions (#650).
  Widget _contextMenu(BuildContext context, EditableTextState editable) =>
      spellCheckContextMenu(
        context,
        editable,
        _spellKey.currentState,
        menu: (context, editable, leading) => editorContextMenu(
          context,
          editable,
          leading: leading,
          onSmartAction: _smartAction,
          testIdPrefix: widget.testId,
        ),
      );

  void _announceStats() => _announce(
    WpTextEditor.statsAnnouncement(L10n.of(context), _currentStats()),
  );

  void _announce(String message) {
    if (!mounted) return;
    announce(View.of(context), message, Directionality.of(context));
  }

  void _pressOnBody(PointerDownEvent _) {
    _pointerOnBody = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pointerOnBody = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final fills = WpTextField.fillsBox(widget.variant);
    final grows = fills || widget.expands;

    Widget field = Semantics(
      container: true,
      identifier: '${widget.testId}-field',
      child:
          widget.fieldOverride ??
          WpTextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: widget.focusNode,
            variant: widget.variant,
            hintText: widget.hintText,
            semanticsLabel: widget.semanticsLabel,
            autofocus: widget.autofocus,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            expands: widget.expands,
            scrollToEnd: widget.scrollToEnd,
            onSubmitted: widget.onSubmitted,
            readOnly: widget.readOnly,
            contextMenuBuilder: _contextMenu,
          ),
    );
    final smartAction = _smartAction;
    if (smartAction != null) {
      field = WpEditorSmartActionScope(
        onAction: smartAction,
        testIdPrefix: widget.testId,
        child: field,
      );
    }
    field = WpEditorSpellCheck(
      key: _spellKey,
      controller: widget.controller,
      enabled: widget.editable && !widget.readOnly,
      child: field,
    );
    if (widget.fieldOverlays.isNotEmpty) {
      field = Stack(
        children: [
          grows ? Positioned.fill(child: field) : field,
          ...widget.fieldOverlays,
        ],
      );
    }
    // Bound around the field only: a key pressed in a neighbouring input (the
    // note's tag field, the snippet's name) never reaches these bindings.
    field = CallbackShortcuts(
      bindings: {
        if (!widget.readOnly)
          ...WpTextEditor.shortcutBindings(
            controller: widget.controller,
            focusNode: widget.focusNode,
            onSave: widget.onSave,
            onInsertSnippet: widget.onInsertSnippet,
          ),
        ...widget.extraShortcuts,
        if (smartAction != null) editorSmartActionActivator: _openSmartMenu,
        if (_outlineAvailable) ...{
          WpTextEditor.outlineActivator: _openOutline,
          for (final key in WpTextEditor.nextHeadingActivators)
            key: () => _stepHeading(forward: true),
          for (final key in WpTextEditor.previousHeadingActivators)
            key: () => _stepHeading(forward: false),
        },
        if (widget.editable && !widget.readOnly) ...{
          for (final key in WpTextEditor.nextSpellErrorActivators)
            key: () => unawaited(_stepSpell(forward: true)),
          for (final key in WpTextEditor.previousSpellErrorActivators)
            key: () => unawaited(_stepSpell(forward: false)),
          for (final key in WpTextEditor.contextMenuActivators)
            key: _openContextMenu,
        },
        if (_outlineAvailable && !widget.readOnly) ...{
          WpFindReplaceBar.openActivator: _findCommands.open,
          WpFindReplaceBar.nextActivator: _findCommands.next,
          WpFindReplaceBar.previousActivator: _findCommands.previous,
        },
      },
      child: TextUndoActions(
        controller: widget.controller,
        enabled: widget.editable && !widget.readOnly,
        child: field,
      ),
    );

    Widget body = widget.editable
        ? Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _pressOnBody,
            child: field,
          )
        : (widget.readView ?? const SizedBox.shrink());
    final entry = widget.viewMemory;
    if (entry != null) {
      body = WpEditorViewMemory(
        // Keyed by the entry, so a switch restores the next entry's own place.
        key: ValueKey('${widget.testId}-view-${entry.kind.name}-${entry.id}'),
        entry: entry,
        text: () =>
            widget.editable ? widget.controller.text : (widget.readText ?? ''),
        controller: widget.editable ? widget.controller : null,
        focusNode: widget.focusNode,
        child: body,
      );
    }
    // The chosen text size scales the body only (#648); the reset chip sits
    // over the text.
    body = WpEditorTextBody(testIdPrefix: widget.testId, child: body);

    // Toolbar above the text on screen, but the text first in the Tab order
    // and the toolbar right after it (#652); the footer and anything else
    // follow in reading order.
    body = WpEditorTraversal.field(body);
    final rows = <Widget>[
      if (widget.showToolbar) ...[
        WpEditorTraversal.toolbar(
          Padding(
            // The editor carries the page inset on every surface (#1498),
            // so bar, surface and status line share one left and right
            // edge in Notes, Recordings and Snippets; the pane pads
            // nothing around it.
            padding: _sideInset,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                container: true,
                identifier: '${widget.testId}-toolbar',
                child: WpMarkdownToolbar(
                  key: widget.toolbarKey,
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  testIdPrefix: widget.testId,
                  enabled: widget.editable,
                  undoController: _undo,
                  onInsertSnippet: widget.onInsertSnippet,
                  onSaveSelectionAsSnippet: widget.onSaveSelectionAsSnippet,
                  outlineOpen: _outlineOpen,
                  onToggleOutline: _toggleOutline,
                  findCommands: _findCommands,
                  onFindReveal: _revealAt,
                  onSmartAction: widget.readOnly ? null : widget.onSmartAction,
                  smartCommands: _smartCommands,
                  trailing: widget.toolbarTrailing,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        // The outline sits between the bar and the text (#645): it reads
        // top-down with the text it lists, and the narrow panels have no
        // room for a column beside the text.
        if (_outlineOpen && _outlineAvailable)
          Padding(
            padding: _sideInset.copyWith(bottom: WpSpacing.xs),
            child: WpOutlinePanel(
              key: _outlineKey,
              testId: widget.testId,
              controller: widget.controller,
              onSelect: _jumpTo,
              onClose: _closeOutline,
              onLeave: _returnToText,
              stepHint: l10n.editorOutlineStepHint(
                WpTextEditor.nextHeadingShortcutLabel(l10n),
                WpTextEditor.previousHeadingShortcutLabel(l10n),
              ),
            ),
          ),
      ] else if (widget.toolbarTrailing case final trailing?)
        Padding(
          padding: _sideInset.copyWith(bottom: WpSpacing.xs),
          child: trailing,
        ),
      ?widget.betweenToolbarAndField,
      // The surface keeps the page's side inset on both sides, so it ends
      // where the rest of the page does (#1498 F-editor-pattern).
      if (grows)
        WpFillSlot(
          child: Padding(padding: _sideInset, child: body),
        )
      else
        Padding(padding: _sideInset, child: body),
      _EditorFooter(
        testId: widget.testId,
        controller: widget.controller,
        countText: widget.editable ? null : (widget.readText ?? ''),
        knownWords: !widget.editable && widget.externalWordCount
            ? widget.wordCount
            : null,
        saveHint: widget.editable && widget.onSave != null
            ? l10n.editorSaveHint(commandShortcutLabel('S', l10n: l10n))
            : null,
        status: switch (widget.saveStatus) {
          final status? => WpSaveStatusLabel(
            testId: widget.testId,
            status: status,
          ),
          null => null,
        },
        saveState: widget.saveStatus,
      ),
    ];
    // The counts key works anywhere in the block, in reading as in editing
    // (#649).
    final editor = CallbackShortcuts(
      bindings: {WpTextEditor.statsActivator: _announceStats},
      child: WpEditorTraversal.group(
        // A growing surface fills what tool row and status line leave, but
        // keeps a few lines (#1371): at 200 % text size in a short window the
        // block grows taller than its slot instead of overflowing, and the
        // editor pane scrolls.
        child: grows
            ? WpFillColumn(
                minFillExtent: MediaQuery.textScalerOf(
                  context,
                ).scale(WpTextEditor.minSurfaceExtent),
                children: rows,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
      ),
    );
    // Text size, line length and spacing for the whole block (#648).
    return WpEditorText(child: editor);
  }
}

/// The status line: save status, the counts of text and selection, and the
/// save rule while editing.
class _EditorFooter extends StatefulWidget {
  const _EditorFooter({
    required this.testId,
    required this.controller,
    required this.countText,
    required this.knownWords,
    required this.saveHint,
    required this.status,
    required this.saveState,
  });

  final String testId;
  final TextEditingController controller;

  /// The page's save status, shown first in the line.
  final Widget? status;

  /// Drives [status]; once it leaves idle the status replaces the save
  /// hint, so the line never shows two save messages side by side (#1498).
  final ValueListenable<WpSaveStatus>? saveState;

  /// Fixed text to count (read mode); null counts the live [controller],
  /// its selection included.
  final String? countText;

  /// Word count of [countText] known from outside (the metadata index).
  final int? knownWords;
  final String? saveHint;

  @override
  State<_EditorFooter> createState() => _EditorFooterState();
}

class _EditorFooterState extends State<_EditorFooter> {
  EditorTextStats _stats = EditorTextStats.empty;
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _stats = _count();
  }

  @override
  void didUpdateWidget(_EditorFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    if (controllerChanged) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    // Another text to read, a known count or a switch between reading and
    // editing is drawn right away, not after the throttle.
    if (controllerChanged ||
        oldWidget.countText != widget.countText ||
        oldWidget.knownWords != widget.knownWords) {
      _pending?.cancel();
      _pending = null;
      _stats = _count();
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  EditorTextStats _count() {
    final fixed = widget.countText;
    if (fixed != null) {
      return EditorTextStats.of(fixed, knownWords: widget.knownWords);
    }
    final c = widget.controller;
    return EditorTextStats.of(c.text, selection: c.selection);
  }

  /// Throttled: the first change after a pause starts the clock, and the one
  /// count when it runs out takes in every change since. Steady typing so
  /// updates the line every [WpTextEditor.counterThrottle], not per key.
  void _onTextChanged() {
    if (widget.countText != null || _pending != null) return;
    _pending = Timer(WpTextEditor.counterThrottle, () {
      _pending = null;
      if (!mounted) return;
      final next = _count();
      if (next != _stats) setState(() => _stats = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final style = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    final saveState = widget.saveState;
    return Padding(
      // The status line: same inset as bar and surface, same small step
      // below the surface in every editor.
      padding: const EdgeInsets.fromLTRB(
        WpPageFrame.inset,
        WpSpacing.xxs,
        WpPageFrame.inset,
        WpSpacing.xs,
      ),
      child: Semantics(
        container: true,
        identifier: '${widget.testId}-status-line',
        child: ListenableBuilder(
          listenable: Listenable.merge([?saveState]),
          builder: (context, _) {
            final saveHint = widget.saveHint;
            final showHint =
                saveHint != null &&
                (saveState == null || saveState.value == WpSaveStatus.idle);
            final stats = _stats;
            final selection = WpTextEditor.selectionLabel(l10n, stats);
            return Wrap(
              spacing: WpSpacing.sm,
              runSpacing: WpSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ?widget.status,
                if (stats.characters > 0)
                  Semantics(
                    container: true,
                    identifier: '${widget.testId}-counter',
                    child: Text(
                      WpTextEditor.counterLabel(l10n, stats),
                      style: style,
                    ),
                  ),
                if (selection != null)
                  Semantics(
                    container: true,
                    identifier: '${widget.testId}-selection-count',
                    child: Text(selection, style: style),
                  ),
                if (showHint)
                  Semantics(
                    container: true,
                    identifier: '${widget.testId}-save-hint',
                    child: Text(saveHint, style: style),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
