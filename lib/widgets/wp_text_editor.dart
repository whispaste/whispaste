import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/command_shortcut.dart';
import '../core/data/content_metadata.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/text/text_undo.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../core/utils/word_count.dart';
import 'markdown_toolbar.dart';
import 'page_shell.dart' show WpPageFrame;
import 'wp_editor_view_memory.dart';
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
/// * **Counter and save timing** — the footer line names the word count with
///   reading time and, whenever there is something to save, the one rule all
///   three share: drafts are kept while typing, Ctrl/Cmd+S saves.
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
///   selection, scroll place and text size of that entry ([WpEditorViewMemory],
///   #678), in reading and in editing alike.
class WpTextEditor extends StatefulWidget {
  const WpTextEditor({
    super.key,
    required this.testId,
    required this.controller,
    required this.focusNode,
    required this.variant,
    this.editable = true,
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
  });

  /// The page's save status ([WpSaveStatus]), drawn first in the status line
  /// under the surface in every editor as `<testId>-save-status` (#1498).
  /// Every editable editor passes one, so "Saved" after a pause or Ctrl/Cmd+S
  /// reads the same in Recordings, Notes and Snippets.
  final ValueListenable<WpSaveStatus>? saveStatus;

  /// Prefix of every semantics identifier inside the block:
  /// `<testId>-toolbar`, `<testId>-toolbar-<action>`, `<testId>-field`, `<testId>-counter`,
  /// `<testId>-save-hint`, `<testId>-save-status`.
  final String testId;

  final TextEditingController controller;
  final FocusNode focusNode;
  final WpTextFieldVariant variant;

  /// False while the text is only being read (History outside edit mode).
  /// The toolbar stays in place, disabled; [readView] stands in for the field.
  final bool editable;

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

  /// True when the count comes from outside (the metadata index of a long
  /// recording) instead of being counted here on every change: the counter then
  /// shows [wordCount], or "—" while that is still unknown.
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

  /// The entry whose caret, scroll place and text size the body remembers
  /// (#678); null where there is no stored entry yet (a new snippet). Only
  /// the body is wrapped: the toolbar keeps its size and the reset chip sits
  /// over the text.
  final ContentKey? viewMemory;

  /// Opens the snippet picker for this editor (#664): a toolbar button and
  /// the insert-snippet key. Null where the surface offers none.
  final VoidCallback? onInsertSnippet;

  /// Saves the selected text as a new snippet (#664): a toolbar button only.
  final VoidCallback? onSaveSelectionAsSnippet;

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

  /// Ctrl+S on Windows/Linux, Cmd+S on macOS.
  static SingleActivator get saveActivator =>
      commandActivator(LogicalKeyboardKey.keyS);

  /// "67 words · 1 min read", with non-breaking spaces inside each group so a
  /// narrow panel wraps between the two facts, never inside one.
  static String counterLabel(L10n l10n, String text) =>
      counterLabelForWords(l10n, computeWordCountFast(text));

  /// [counterLabel] for an already known word count.
  static String counterLabelForWords(L10n l10n, int words) {
    final readMinutes = (words / 200).ceil(); // ~200 wpm average
    String group(String s) => s.replaceAll(' ', ' ');
    final wordStr = group(l10n.historyWordCount(words));
    final timeStr = group(
      readMinutes < 1
          ? l10n.historyReadingTimeUnder1
          : l10n.historyReadingTime(readMinutes),
    );
    return '$wordStr · $timeStr';
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

  @override
  void initState() {
    super.initState();
    _undo;
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(WpTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ownUndo?.dispose();
      _ownUndo = null;
      _undo;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _ownUndo?.dispose();
    super.dispose();
  }

  /// Keyboard focus (Tab, shortcut, autofocus) puts the caret at the end of
  /// the text; a click keeps the position it set itself (#1498
  /// F-caret-edit-mode: typing used to land inside existing text).
  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus || !widget.editable || _pointerOnBody) {
      return;
    }
    final c = widget.controller;
    // A real range stays: a toolbar button hands focus back to the field
    // after formatting the selection, and that selection must survive.
    if (c.selection.isValid && !c.selection.isCollapsed) return;
    c.selection = TextSelection.collapsed(offset: c.text.length);
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
          ),
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
        ...WpTextEditor.shortcutBindings(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onSave: widget.onSave,
          onInsertSnippet: widget.onInsertSnippet,
        ),
        ...widget.extraShortcuts,
      },
      child: TextUndoActions(
        controller: widget.controller,
        enabled: widget.editable,
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
        testIdPrefix: widget.testId,
        child: body,
      );
    }

    // Toolbar above the text on screen, but the text first in the Tab order
    // and the toolbar right after it (#652); the footer and anything else
    // follow in reading order.
    body = WpEditorTraversal.field(body);
    return WpEditorTraversal.group(
      child: Column(
        mainAxisSize: grows ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      trailing: widget.toolbarTrailing,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: WpSpacing.xs),
          ] else if (widget.toolbarTrailing case final trailing?)
            Padding(
              padding: _sideInset.copyWith(bottom: WpSpacing.xs),
              child: trailing,
            ),
          ?widget.betweenToolbarAndField,
          // The surface keeps the page's side inset on both sides, so it ends
          // where the rest of the page does (#1498 F-editor-pattern).
          if (grows)
            Expanded(
              child: Padding(padding: _sideInset, child: body),
            )
          else
            Padding(padding: _sideInset, child: body),
          _EditorFooter(
            testId: widget.testId,
            controller: widget.controller,
            countText: widget.editable ? null : (widget.readText ?? ''),
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
            externalWordCount: widget.externalWordCount,
            wordCount: widget.wordCount,
          ),
        ],
      ),
    );
  }
}

/// Word count with reading time, and the save rule while editing.
class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.testId,
    required this.controller,
    required this.countText,
    required this.saveHint,
    required this.status,
    required this.saveState,
    required this.externalWordCount,
    required this.wordCount,
  });

  final String testId;
  final TextEditingController controller;

  /// The page's save status, shown first in the line.
  final Widget? status;

  /// Drives [status]; once it leaves idle the status replaces the save
  /// hint, so the line never shows two save messages side by side (#1498).
  final ValueListenable<WpSaveStatus>? saveState;

  /// Fixed text to count (read mode); null counts the live [controller].
  final String? countText;
  final String? saveHint;

  final bool externalWordCount;
  final int? wordCount;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final style = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    return Padding(
      // The status line: same inset as bar and surface, same small step
      // below the surface in every editor.
      padding: const EdgeInsets.fromLTRB(
        WpPageFrame.inset,
        WpSpacing.xxs,
        WpPageFrame.inset,
        WpSpacing.xs,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, ?saveState]),
        builder: (context, _) {
          final text = countText ?? controller.text;
          final showHint =
              saveHint != null &&
              (saveState == null || saveState!.value == WpSaveStatus.idle);
          // While an external count is still pending the counter stays
          // away; a lone dash under the editor read as a stray line (#1498).
          final String? counter = externalWordCount
              ? (wordCount == null
                    ? null
                    : WpTextEditor.counterLabelForWords(l10n, wordCount!))
              : WpTextEditor.counterLabel(l10n, text);
          return Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ?status,
              if (text.isNotEmpty && counter != null)
                Semantics(
                  container: true,
                  identifier: '$testId-counter',
                  child: Text(counter, style: style),
                ),
              if (showHint)
                Semantics(
                  container: true,
                  identifier: '$testId-save-hint',
                  child: Text(saveHint!, style: style),
                ),
            ],
          );
        },
      ),
    );
  }
}
