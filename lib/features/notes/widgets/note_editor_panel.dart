import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/content_metadata_providers.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/text/markdown_plain_text.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/find_replace.dart';
import '../../../widgets/markdown_toolbar.dart' show WpEditorTraversal;
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_save_status.dart';
import '../../../widgets/wp_text_editor.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_editor_pane.dart';
import '../../../widgets/wp_head_actions.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_markdown_view.dart';
import '../../../widgets/wp_text_field.dart';
import '../../../widgets/wp_voice_input_button.dart';
import 'note_tag_field.dart';
import '../../../widgets/wp_page_notice.dart';
import '../blocks/long_note_layout.dart';
import '../data/note_title.dart';
import '../data/writing_focus.dart' show writingFocusShortcutLabel;
import 'note_append_gutter.dart';
import 'long_note_editor.dart';
import 'note_image_strip.dart';
import 'note_title_field.dart';
import 'note_source_link.dart';
import 'quick_note_hotkey_line.dart';
import '../../../widgets/wp_copy_feedback.dart';
import '../../snippets/snippets_page.dart' show insertSnippetAtCursor;

// ---------------------------------------------------------------------------
// Note editor panel — strongly reduced sibling of HistoryDetailPanel:
// a slim toolbar row, a hairline divider, and an always-editable multiline
// text field. Controller + focus node are OWNED BY _NotesPageState and only
// passed through here, so cursor/IME state survive panel rebuilds.
// ---------------------------------------------------------------------------

/// Width the note title keeps before head actions move into the menu
/// (#1498): about fifteen characters of the heading style, enough to tell
/// notes apart while every primary action stays in view.
const double _titleMinWidth = 160;

/// Secondary actions the head shows at most, however wide the panel (#1498).
/// Like the history detail, only copy stays beside the primaries; reading
/// view, duplicate, export, quick note and trash live in the … menu, so the
/// title gets the width instead of a row of icons.
const int _maxRowSecondaries = 1;

/// Actions the editor offers beyond the core toolbar (ticket). Each callback is
/// optional: a control whose callback is null is not shown.
class NoteEditorExtras {
  const NoteEditorExtras({
    this.onSaveTitle,
    this.onSaveVersionNow,
    this.saveStatus,
    this.onMarkSelection,
    this.onAddImage,
    this.onShowVersions,
    this.onCreateSnippet,
    this.onGoToParagraph,
    this.onSplitNote,
    this.onToggleFocusMode,
    this.focusMode = false,
    this.titleRevision = 0,
  });

  final void Function(String noteId, String title)? onSaveTitle;
  final VoidCallback? onSaveVersionNow;

  /// The body's save status, shown in the editor's status line (#1498).
  final ValueListenable<WpSaveStatus>? saveStatus;
  final VoidCallback? onMarkSelection;
  final VoidCallback? onAddImage;
  final VoidCallback? onShowVersions;
  final VoidCallback? onCreateSnippet;

  /// "Go to paragraph" (Ctrl/Cmd+G) — the way through a long note (#641).
  final VoidCallback? onGoToParagraph;

  /// "Split note" at the caret — offered in the menu and by the notice at
  /// the editing limit (#641).
  final VoidCallback? onSplitNote;

  /// Enters or leaves focus mode (#669); `null` hides the button.
  final VoidCallback? onToggleFocusMode;

  /// Whether focus mode is on — flips the button to "leave".
  final bool focusMode;

  /// Bumped after a version restore, so the title field reloads the restored
  /// title instead of keeping what was typed before.
  final int titleRevision;
}

/// Whether the note body shows the rendered reading view instead of the text
/// field (#643). Editing is the default: Notes is a writing surface, and the
/// reading view is a deliberate switch for working through a checklist. It
/// stays chosen across notes for the session, the way a view mode does.
class NoteReadingViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final noteReadingViewProvider = NotifierProvider<NoteReadingViewNotifier, bool>(
  NoteReadingViewNotifier.new,
);

class NoteEditorPanel extends ConsumerWidget {
  const NoteEditorPanel({
    super.key,
    required this.note,
    required this.tags,
    required this.controller,
    required this.focusNode,
    this.scrollEditorToEnd,
    required this.onClose,
    required this.onDuplicate,
    required this.onToggleFavorite,
    required this.onQuickNoteSet,
    required this.onQuickNoteClear,
    required this.onMoveToTrash,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onExport,
    required this.onVoiceTranscript,
    this.extras = const NoteEditorExtras(),
  });

  final Note note;

  /// Tags linked to this note (from noteTagsProvider, alphabetically sorted).
  final List<Tag> tags;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Fires when the body field should jump to the end of the note — after a
  /// quick-note append, so the freshly appended text is what is visible
  /// (Ticket 21). Owned by `_NotesPageState` like the two above, and optional
  /// so the panel stays constructible without one (several widget tests build
  /// it directly).
  final Listenable? scrollEditorToEnd;
  final VoidCallback onClose;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleFavorite;

  /// Make this note the quick note — offered only while it is not already the
  /// quick note (see the toolbar's comment on the two separate controls).
  final VoidCallback onQuickNoteSet;

  /// Drop the quick-note mark, leaving no note marked.
  final VoidCallback onQuickNoteClear;
  final VoidCallback onMoveToTrash;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  /// Add/remove a tag on this note (tagName / tagId).
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  /// Export this note via the format picker (txt/md).
  final VoidCallback onExport;

  /// Called with the raw transcript when the voice-input button finishes —
  /// the panel does not insert it itself, that's `_NotesPageState`'s job
  /// (cursor position lives in the shared controller/selection, not here).
  final ValueChanged<String> onVoiceTranscript;

  /// Title saving, snapshots, marks, images, versions and Textbausteine.
  final NoteEditorExtras extras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(contentMetadataProvider((kind: ContentKind.note, id: note.id)));
    final l10n = L10n.of(context);
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;
    final errorColor = WpColors.error;
    final isTrashed = note.deletedAt != null;
    // A trashed note is read-only: nothing is inserted into it (#664).
    final VoidCallback? insertSnippet = isTrashed
        ? null
        : () => unawaited(
            insertSnippetAtCursor(
              context: context,
              ref: ref,
              controller: controller,
              focusNode: focusNode,
            ),
          );
    final showQuickNoteMark = !isTrashed && note.isQuickNote;
    // An empty note has nothing to read; it always opens for writing, so a
    // new note never asks for a click before the first word.
    final reading =
        ref.watch(noteReadingViewProvider) && controller.text.trim().isNotEmpty;

    // The shared editor pane (#1498): the same slots, insets and edges as
    // History and Snippets. The editor draws the page inset itself, so the
    // note's append gutter can sit in that inset.
    // The title first in the Tab order, then the rest in reading order
    // (#652); the editor below orders its own text before its toolbar.
    return WpEditorTraversal.group(
      child: WpEditorPane(
        head:
            // ── Toolbar row ──
            // Quick-note mark (only when this note holds it) + derived title +
            // copy + export + voice input + favourite/quick-note/trash (or
            // restore/delete-forever for trashed notes) + close.
            // The shared editor head (#1498): the same band as History and
            // Snippets, right edge on the page inset where the field below ends.
            LayoutBuilder(
              builder: (context, constraints) {
                // ── Secondary actions ──
                // In the order they sit in the row. Each one that does not fit
                // beside a readable title moves into the "more" menu (#1498);
                // `rank` says which stay longest (0 = last to go). Dictation,
                // favourite, the trash pair of a trashed note, the menu and
                // close always stay.
                final secondary = <_HeadAction>[
                  _HeadAction(
                    testId: 'notes-editor-duplicate',
                    rank: 4,
                    icon: LucideIcons.files,
                    label: l10n.actionDuplicate,
                    onSelected: onDuplicate,
                    button: WpIconButton.ghost(
                      compact: true,
                      key: ValueKey('notes-editor-duplicate-${note.id}'),
                      testId: 'notes-editor-duplicate',
                      icon: LucideIcons.files,
                      tooltip: l10n.actionDuplicate,
                      onPressed: onDuplicate,
                      color: textMuted,
                    ),
                  ),
                  // Reading view (#643): the rendered Markdown with tickable
                  // checklists. The icon names where the click leads, the
                  // accent marks the view that is on.
                  _HeadAction(
                    testId: 'notes-editor-read-toggle',
                    rank: 1,
                    icon: reading ? LucideIcons.pencil : LucideIcons.bookOpen,
                    label: reading ? l10n.notesEditMode : l10n.notesReadMode,
                    onSelected: () =>
                        ref.read(noteReadingViewProvider.notifier).toggle(),
                    button: WpIconButton.ghost(
                      compact: true,
                      testId: 'notes-editor-read-toggle',
                      icon: reading ? LucideIcons.pencil : LucideIcons.bookOpen,
                      tooltip: reading
                          ? l10n.notesEditMode
                          : l10n.notesReadMode,
                      onPressed: () =>
                          ref.read(noteReadingViewProvider.notifier).toggle(),
                      color: reading ? WpColors.accent : textMuted,
                    ),
                  ),
                  _HeadAction(
                    testId: 'notes-editor-copy',
                    rank: 0,
                    icon: LucideIcons.copy,
                    label: l10n.historyCopyText,
                    // Deliberately no telemetry here: note contents are on the
                    // telemetry negative list (internal-notes) — unlike the history
                    // copy action, this stays event-free. Plain text by default
                    // (#644); the overflow menu keeps the Markdown.
                    onSelected: () => unawaited(
                      copyWithFeedback(
                        context,
                        text: markdownToPlainText(controller.text),
                        target: 'note-editor',
                      ),
                    ),
                    button: WpCopyAnchor(
                      target: 'note-editor',
                      child: WpIconButton.ghost(
                        compact: true,
                        testId: 'notes-editor-copy',
                        icon: LucideIcons.copy,
                        tooltip: l10n.historyCopyText,
                        onPressed: () => unawaited(
                          copyWithFeedback(
                            context,
                            text: markdownToPlainText(controller.text),
                            target: 'note-editor',
                          ),
                        ),
                        color: textMuted,
                      ),
                    ),
                  ),
                  _HeadAction(
                    testId: 'notes-editor-export',
                    rank: 3,
                    icon: LucideIcons.download,
                    label: l10n.notesExport,
                    onSelected: onExport,
                    button: WpIconButton.ghost(
                      compact: true,
                      testId: 'notes-editor-export',
                      icon: LucideIcons.download,
                      tooltip: l10n.notesExport,
                      onPressed: onExport,
                      color: textMuted,
                    ),
                  ),
                  if (extras.onToggleFocusMode != null)
                    _HeadAction(
                      testId: 'notes-editor-focus',
                      rank: 6,
                      icon: extras.focusMode
                          ? LucideIcons.minimize2
                          : LucideIcons.maximize2,
                      // Already a fixed entry of the menu (notes-editor-menu-focus).
                      label: null,
                      onSelected: extras.onToggleFocusMode!,
                      button: WpIconButton.ghost(
                        compact: true,
                        testId: 'notes-editor-focus',
                        icon: extras.focusMode
                            ? LucideIcons.minimize2
                            : LucideIcons.maximize2,
                        tooltip:
                            '${extras.focusMode ? l10n.notesFocusModeExit : l10n.notesFocusModeEnter}'
                            ' (${writingFocusShortcutLabel(l10n)})',
                        onPressed: extras.onToggleFocusMode,
                        color: textMuted,
                      ),
                    ),
                  if (!isTrashed && !note.isQuickNote)
                    // Setting the mark sits with the other per-note actions; on
                    // the note that already holds it this action is simply
                    // absent, so re-marking is impossible rather than a silent
                    // no-op. Removing the mark lives on the title side.
                    _HeadAction(
                      testId: 'notes-editor-quicknote',
                      rank: 5,
                      icon: LucideIcons.zap,
                      label: l10n.notesQuickNoteSet,
                      onSelected: onQuickNoteSet,
                      button: WpIconButton.ghost(
                        compact: true,
                        key: ValueKey('notes-editor-quicknote-${note.id}'),
                        testId: 'notes-editor-quicknote',
                        icon: LucideIcons.zap,
                        tooltip: l10n.notesQuickNoteSet,
                        onPressed: onQuickNoteSet,
                        color: textMuted,
                      ),
                    ),
                  if (!isTrashed)
                    _HeadAction(
                      testId: 'notes-editor-trash',
                      rank: 2,
                      icon: LucideIcons.trash2,
                      label: l10n.notesMoveToTrash,
                      onSelected: onMoveToTrash,
                      button: WpIconButton.ghost(
                        compact: true,
                        key: ValueKey('notes-editor-trash-${note.id}'),
                        testId: 'notes-editor-trash',
                        icon: LucideIcons.trash2,
                        tooltip: l10n.notesMoveToTrash,
                        onPressed: onMoveToTrash,
                        color: textMuted,
                      ),
                    ),
                ];

                // ── Width budget ──
                // The title keeps at least [_titleMinWidth]; the fixed part is
                // the gap, dictation (a full touch
                // target), favourite or the trash pair, the menu and close.
                // Close sits at the same pitch as its neighbours, as in the
                // history and snippet heads (#1498).
                // Every slot of the strip has the same pitch (WpHeadActions).
                const extent = WpHeadActions.slot + WpHeadActions.gap;
                final fixed =
                    WpSpacing.xs +
                    // dictation, favourite (or the trash pair), menu, close
                    WpHeadActions.widthFor(isTrashed ? 5 : 4);
                final room = constraints.hasBoundedWidth
                    ? constraints.maxWidth -
                          WpEditorHead.padding.horizontal -
                          _titleMinWidth -
                          fixed
                    : double.infinity;
                final fitting = room.isInfinite
                    ? _maxRowSecondaries
                    : (room / extent).floor().clamp(0, _maxRowSecondaries);
                final shown = {
                  for (final action in secondary)
                    // Its place among the actions present, by rank.
                    if (secondary.where((o) => o.rank < action.rank).length <
                        fitting)
                      action.testId,
                };
                final collapsed = [
                  for (final action in secondary)
                    if (!shown.contains(action.testId) && action.label != null)
                      action,
                ];

                return WpEditorHead(
                  actionsFit: WpEditorHeadFit.scale,
                  // The title takes all the width the actions leave; actions
                  // that would squeeze it below [_titleMinWidth] went into
                  // the menu above (#1498).
                  title: extras.onSaveTitle == null
                      ? Padding(
                          // The heading field's inset, as in the other heads.
                          padding: WpTextField.headingContentPadding,
                          child: Text(
                            note.title ??
                                deriveNoteTitle(note.content) ??
                                l10n.notesUntitled,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WpTextField.styleFor(
                              WpTextFieldVariant.heading,
                              color: textPrimary,
                            ),
                          ),
                        )
                      // Before the text in the Tab order (#652).
                      : WpEditorTraversal.title(
                          NoteTitleField(
                            key: ValueKey(
                              'notes-editor-title-${note.id}-${extras.titleRevision}',
                            ),
                            noteId: note.id,
                            initialTitle: note.title,
                            hintText:
                                deriveNoteTitle(note.content) ??
                                l10n.notesUntitled,
                            onSave: extras.onSaveTitle!,
                          ),
                        ),
                  // The budget above keeps the cluster within the row at
                  // every width the panel rests at; below that (the split
                  // view's open/close animation) the head scales it.
                  // One strip in all three editors (#1498): copy,
                  // dictation, the star (or the trash pair), any other
                  // action that fits, then the menu, then close.
                  // WpIconButton names itself from its tooltip, so
                  // every control here reaches a screen reader labelled.
                  actions: WpHeadActions(
                    actions: [
                      for (final action in secondary)
                        if (action.testId == 'notes-editor-copy' &&
                            shown.contains(action.testId))
                          action.button,
                      Semantics(
                        container: true,
                        identifier: 'notes-editor-voice',
                        child: WpVoiceInputButton(
                          // Keyed per note. A dictation started here
                          // delivers its transcript into whichever note
                          // is open when it finishes (up to 45 s later),
                          // so the button has to go down with the note it
                          // was started on: its own mounted-guard then
                          // drops the transcript instead of writing note
                          // A's words into note B.
                          key: ValueKey('voice-${note.id}'),
                          compact: true,
                          onTranscript: onVoiceTranscript,
                          onError: (message) => showWpPageNotice(
                            context,
                            page: WpNoticePage.notes,
                            notice: WpPageNotice(
                              id: 'notes-voice-failed',
                              message: message,
                              area: note.id,
                            ),
                          ),
                        ),
                      ),
                      if (isTrashed) ...[
                        // Trash view: restore + delete forever instead of
                        // the favourite.
                        WpIconButton.ghost(
                          compact: true,
                          testId: 'notes-editor-restore',
                          icon: LucideIcons.undo2,
                          tooltip: l10n.notesRestore,
                          onPressed: onRestore,
                          color: textMuted,
                        ),
                        WpIconButton.ghost(
                          compact: true,
                          testId: 'notes-editor-delete-forever',
                          icon: LucideIcons.trash2,
                          tooltip: l10n.notesDeleteForever,
                          onPressed: onDeleteForever,
                          color: errorColor,
                        ),
                      ] else
                        WpFavouriteStar.head(
                          key: ValueKey('notes-editor-favorite-${note.id}'),
                          testId: 'notes-editor-favorite',
                          isFavourite: note.pinned,
                          onToggle: onToggleFavorite,
                        ),
                      for (final action in secondary)
                        if (action.testId != 'notes-editor-copy' &&
                            shown.contains(action.testId))
                          action.button,
                    ],
                    menu: (!isTrashed || collapsed.isNotEmpty)
                        ? _NoteEditorMenu(
                            noteId: note.id,
                            extras: isTrashed
                                ? const NoteEditorExtras()
                                : extras,
                            collapsed: collapsed,
                            onCopyMarkdown: isTrashed
                                ? null
                                : () => unawaited(
                                    copyWithFeedback(
                                      context,
                                      text: controller.text,
                                      target: 'note-editor',
                                    ),
                                  ),
                          )
                        : null,
                    close: WpIconButton.ghost(
                      compact: true,
                      key: ValueKey('notes-editor-close-${note.id}'),
                      testId: 'notes-editor-close',
                      icon: LucideIcons.x,
                      tooltip: '${l10n.actionClose} (Esc)',
                      onPressed: onClose,
                      color: textMuted,
                    ),
                  ),
                );
              },
            ),
        notices: [
          // ── Notice ──
          // What a note action has to say (export result, refused image, no
          // selection, voice error), at the toolbar that started it. It stays
          // until closed, so an error cannot pass unread.
          WpPageNoticeSlot(page: WpNoticePage.notes, area: note.id),
          if (!isTrashed) NoteSourceLink(sourceEntryId: note.sourceEntryId),
        ],
        // ── Meta: quick-note mark + hotkey ──
        // Only on the note that holds the mark. The mark used to lead the
        // title; no editor head carries a leading mark any more (#1498), so it
        // moved to the pane's meta row together with its hotkey: whoever
        // picks the target note is right then asking what triggers it
        // (Ticket 24). The bolt is still the only control that drops the mark
        // and stays apart from the action cluster that sets it, so no
        // position carries both meanings. Cyan interaction accent (ADR 0013),
        // never the amber star. `showQuickNoteMark` also keeps it out of the
        // trash view.
        meta: !showQuickNoteMark
            ? null
            : Row(
                children: [
                  WpIconButton.ghost(
                    compact: true,
                    key: ValueKey('notes-editor-quicknote-clear-${note.id}'),
                    testId: 'notes-editor-quicknote-clear',
                    faIcon: FontAwesomeIcons.bolt,
                    tooltip: l10n.notesQuickNoteClear,
                    onPressed: onQuickNoteClear,
                    color: WpColors.accent,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  const Expanded(child: QuickNoteHotkeyLine()),
                ],
              ),
        // ── Editor ──
        // The shared editor block (#638): the same toolbar, undo, shortcuts,
        // counter and save rule as History's transcript and the snippet body.
        // The bar sits in its own row, permanently — a bar that comes and
        // goes on a surface whose whole purpose is writing would move the
        // text under the cursor. The tags share that row where the width
        // allows (#1498), so the header stays a thin band above the text. In the optional
        // reading view (#643) the bar stays in place, disabled.
        // Deliberately *not* in the header row above: that cluster already
        // overflowed at the 280 dp panel floor (FLUTTER_WHISPASTE-64).
        //
        // Toolbar keyed per note: it owns the find/replace bar's open flag and
        // both of its fields. Carried over, note B would open with note A's
        // query and replacement one click from rewriting note B. Only the
        // toolbar remounts — the field stays, so the switch-to-caret scroll
        // keeps its controller.
        //
        // Nothing else shares the region below, so the field *is* the
        // surface (`bare`): no stroke at rest, prose metrics identical to
        // History's transcript. See WpTextField's library docs.
        editor: WpEditorTraversal.field(
          _NoteEditorBody(
            noteId: note.id,
            controller: controller,
            focusNode: focusNode,
            scrollEditorToEnd: scrollEditorToEnd,
            isTrashed: isTrashed,
            reading: reading,
            onSplitNote: extras.onSplitNote,
            // Ctrl/Cmd+S saves a version now, the way a document's save key
            // does; the body also saves on its own after a pause.
            onSave: extras.onSaveVersionNow,
            saveStatus: isTrashed ? null : extras.saveStatus,
            onGoToParagraph: extras.onGoToParagraph,
            onInsertSnippet: insertSnippet,
            onSaveSelectionAsSnippet: isTrashed ? null : extras.onCreateSnippet,
            // Suggestions of the existing tags (#830); no inline label and no
            // management-dialog button, unlike history's tag section.
            tags: Semantics(
              container: true,
              identifier: 'notes-editor-tags',
              child: NoteTagField(
                // Keyed per note: a half-typed, unsubmitted tag name must not
                // ride along to the next note, where Enter would file it.
                // Clicking a list tile already closes add mode through the
                // input's own TapRegion, but Ctrl/Cmd+N (deliberately not
                // guarded by isTextFieldFocused, see _buildListShortcuts) and
                // the quick-note deep link do not go through a pointer.
                key: ValueKey('tags-${note.id}'),
                tags: tags,
                onAdd: onAddTag,
                onRemove: onRemoveTag,
                hintText: l10n.notesAddTag,
                searchHintText: l10n.notesTagPlaceholder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The note's text on the shared editor block (#638): one text field, or from
/// [LongNoteLimits.enterLongMode] characters the long-note editor that builds
/// only the visible paragraphs (#641, ADR 0035). Both edit the page's
/// controller, so autosave, find, dictation and formatting do not notice the
/// switch. From [LongNoteLimits.editingLimit] on a notice above the text offers
/// to split the note; there is no limit, editing goes on.
class _NoteEditorBody extends StatefulWidget {
  const _NoteEditorBody({
    required this.noteId,
    required this.controller,
    required this.focusNode,
    required this.scrollEditorToEnd,
    required this.isTrashed,
    required this.reading,
    required this.onSplitNote,
    required this.onSave,
    required this.saveStatus,
    required this.onGoToParagraph,
    required this.onInsertSnippet,
    required this.onSaveSelectionAsSnippet,
    required this.tags,
  });

  final String noteId;

  /// The note's tag input, sharing the toolbar's row (#1498).
  final Widget tags;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Listenable? scrollEditorToEnd;
  final bool isTrashed;

  /// Shows the rendered reading view instead of the field (#643).
  final bool reading;
  final VoidCallback? onSplitNote;
  final VoidCallback? onSave;
  final ValueListenable<WpSaveStatus>? saveStatus;
  final VoidCallback? onGoToParagraph;
  final VoidCallback? onInsertSnippet;
  final VoidCallback? onSaveSelectionAsSnippet;

  @override
  State<_NoteEditorBody> createState() => _NoteEditorBodyState();
}

class _NoteEditorBodyState extends State<_NoteEditorBody> {
  bool _long = false;
  bool _overLimit = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _long = _wantsLong(widget.controller.text.length, currentlyLong: false);
    _overLimit = widget.controller.text.length >= LongNoteLimits.editingLimit;
  }

  @override
  void didUpdateWidget(_NoteEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (oldWidget.noteId != widget.noteId) _onText();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// The long-note editor needs the find highlight of the page's controller;
  /// a plain controller (some widget tests) keeps the text field.
  bool _wantsLong(int length, {required bool currentlyLong}) =>
      widget.controller is WpFindHighlightController &&
      LongNoteLimits.useLongMode(length, currentlyLong: currentlyLong);

  void _onText() {
    final length = widget.controller.text.length;
    final long = _wantsLong(length, currentlyLong: _long);
    final overLimit = length >= LongNoteLimits.editingLimit;
    if (long == _long && overLimit == _overLimit) return;
    final hadFocus = widget.focusNode.hasFocus;
    setState(() {
      _long = long;
      _overLimit = overLimit;
    });
    // The other editor takes over the same focus node; give it the caret
    // back once it is mounted, so typing across the threshold goes on.
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.focusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final controller = widget.controller;
    final onSplit = widget.onSplitNote;
    final showLimit = _overLimit && !widget.isTrashed;
    return WpTextEditor(
      toolbarKey: ValueKey('toolbar-${widget.noteId}'),
      toolbarTrailing: widget.tags,
      testId: 'notes-editor',
      fieldKey: const ValueKey('notes-editor-body'),
      controller: controller,
      focusNode: widget.focusNode,
      scrollToEnd: widget.scrollEditorToEnd,
      variant: WpTextFieldVariant.bare,
      hintText: l10n.notesEditorPlaceholder,
      onSave: widget.onSave,
      saveStatus: widget.saveStatus,
      onInsertSnippet: widget.onInsertSnippet,
      onSaveSelectionAsSnippet: widget.onSaveSelectionAsSnippet,
      // Caret, place and text size come back per note (#678).
      viewMemory: (kind: ContentKind.note, id: widget.noteId),
      // Reading view (#643): the same text rendered, in the field's own
      // style and inset, so the words keep their place when switching. A
      // ticked box rewrites the controller's text, and the page's autosave
      // stores it like any edit. In the trash the boxes are read-only.
      editable: !widget.reading,
      readText: widget.reading ? controller.text : null,
      readView: widget.reading
          ? ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Semantics(
                container: true,
                identifier: 'notes-editor-read',
                // The same framed writing surface as the field, so the
                // switch to reading keeps the box, its edge and its inset.
                child: WpTextFieldSurface(
                  variant: WpTextFieldVariant.bare,
                  liftsOnHover: false,
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: WpMarkdownView(
                        testId: 'notes-editor-read',
                        source: controller.text,
                        style: WpTextField.styleFor(
                          WpTextFieldVariant.bare,
                          color: WpColors.textPrimary,
                        ),
                        onChanged: widget.isTrashed
                            ? null
                            : (text) => controller.text = text,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      extraShortcuts: {
        if (widget.onGoToParagraph != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyG, control: true):
              widget.onGoToParagraph!,
          const SingleActivator(LogicalKeyboardKey.keyG, meta: true):
              widget.onGoToParagraph!,
        },
      },
      fieldOverride: _long
          ? Semantics(
              container: true,
              identifier: 'notes-editor-body',
              child: LongNoteEditor(
                key: ValueKey('notes-editor-body-long-${widget.noteId}'),
                controller: controller as WpFindHighlightController,
                focusNode: widget.focusNode,
                scrollToEnd: widget.scrollEditorToEnd,
                semanticsLabel: l10n.notesLongEditorLabel,
              ),
            )
          : null,
      // ── Attached images and the split notice ──
      // Above the body and out of its way: nothing is shown without images,
      // and images never take part in the text the field edits.
      betweenToolbarAndField: widget.isTrashed
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLimit)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WpSpacing.xl,
                      WpSpacing.xs,
                      WpSpacing.xl,
                      WpSpacing.xs,
                    ),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      identifier: 'notes-editor-limit',
                      child: WpBanner(
                        tone: WpBannerTone.warning,
                        message: l10n.notesEditingLimitNotice,
                        action: onSplit == null
                            ? null
                            : WpButton(
                                testId: 'notes-editor-limit-split',
                                label: l10n.notesSplitNote,
                                variant: WpButtonVariant.ghost,
                                onPressed: onSplit,
                              ),
                      ),
                    ),
                  ),
                Semantics(
                  identifier: 'notes-images-${widget.noteId}',
                  child: NoteImageStrip(
                    key: ValueKey('notes-images-${widget.noteId}'),
                    noteId: widget.noteId,
                  ),
                ),
              ],
            ),
      // The quick-note margin marks (#803) lie over the field's left inset, so
      // the text never shifts for them. The long-note editor leaves them out:
      // they place themselves by the single field's line metrics, which a list
      // of paragraphs does not have.
      fieldOverlays: [
        if (!widget.isTrashed && !_long)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: WpSpacing.xl,
            child: NoteAppendGutter(
              key: ValueKey('notes-append-gutter-${widget.noteId}'),
              noteId: widget.noteId,
              controller: controller,
              focusNode: widget.focusNode,
            ),
          ),
      ],
    );
  }
}

/// A head action that moves into the overflow menu when the title needs the
/// width (#1498).
class _HeadAction {
  const _HeadAction({
    required this.testId,
    required this.rank,
    required this.icon,
    required this.label,
    required this.onSelected,
    required this.button,
  });

  final String testId;

  /// Order of staying visible: 0 stays longest.
  final int rank;

  /// Glyph of the menu row once collapsed.
  final IconData icon;

  /// Menu label once collapsed; `null` when the menu already has the entry.
  final String? label;
  final VoidCallback onSelected;
  final Widget button;
}

/// Entries of the overflow menu. Kept out of the toolbar row, which is already
/// capped for the narrowest panel (FLUTTER_WHISPASTE-64).
class _NoteEditorMenu extends StatelessWidget {
  const _NoteEditorMenu({
    required this.noteId,
    required this.extras,
    required this.collapsed,
    required this.onCopyMarkdown,
  });

  final String noteId;
  final NoteEditorExtras extras;

  /// Head actions that did not fit beside the title; they lead the menu,
  /// as `notes-editor-menu-<action>` (#1498).
  final List<_HeadAction> collapsed;

  /// Second choice next to the plain-text copy button (#644).
  final VoidCallback? onCopyMarkdown;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final focusIcon = extras.focusMode
        ? LucideIcons.minimize2
        : LucideIcons.maximize2;
    final entries = <(String, IconData, String, VoidCallback?)>[
      for (final action in collapsed)
        (
          action.testId.replaceFirst('notes-editor-', 'notes-editor-menu-'),
          action.icon,
          action.label!,
          action.onSelected,
        ),
      (
        'notes-editor-menu-copy-markdown',
        LucideIcons.fileCode,
        l10n.historyCopyAsMarkdown,
        onCopyMarkdown,
      ),
      (
        'notes-editor-menu-save-version',
        LucideIcons.save,
        l10n.notesVersionSaveNow,
        extras.onSaveVersionNow,
      ),
      (
        'notes-editor-menu-mark',
        LucideIcons.highlighter,
        l10n.notesMenuMark,
        extras.onMarkSelection,
      ),
      (
        'notes-editor-menu-add-image',
        LucideIcons.imagePlus,
        l10n.notesMenuAddImage,
        extras.onAddImage,
      ),
      (
        'notes-editor-menu-versions',
        LucideIcons.history,
        l10n.notesMenuVersions,
        extras.onShowVersions,
      ),
      (
        'notes-editor-menu-snippet',
        LucideIcons.textQuote,
        l10n.notesMenuSnippet,
        extras.onCreateSnippet,
      ),
      (
        'notes-editor-menu-goto',
        LucideIcons.listOrdered,
        l10n.notesMenuGoToParagraph,
        extras.onGoToParagraph,
      ),
      (
        'notes-editor-menu-split',
        LucideIcons.split,
        l10n.notesSplitNote,
        extras.onSplitNote,
      ),
      (
        'notes-editor-menu-focus',
        focusIcon,
        extras.focusMode ? l10n.notesFocusModeExit : l10n.notesFocusModeEnter,
        extras.onToggleFocusMode,
      ),
    ].where((entry) => entry.$4 != null).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return WpHeadMenuButton<String>(
      key: ValueKey('notes-editor-more-$noteId'),
      testId: 'notes-editor-more',
      tooltip: l10n.notesMoreActions,
      onSelected: (testId) =>
          entries.firstWhere((entry) => entry.$1 == testId).$4!.call(),
      itemBuilder: (_) => [
        for (final entry in entries)
          PopupMenuItem<String>(
            key: ValueKey(entry.$1),
            value: entry.$1,
            child: Semantics(
              identifier: entry.$1,
              child: WpMenuRow(
                icon: entry.$2,
                label: entry.$3,
                isDestructive: entry.$1 == 'notes-editor-menu-trash',
              ),
            ),
          ),
      ],
    );
  }
}
