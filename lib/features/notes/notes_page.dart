import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/notes/notes_exporter.dart' as notes_exporter;
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/toast.dart';
import 'data/note_autosave.dart';
import 'data/note_title.dart';
import 'data/notes_actions.dart';
import 'data/providers.dart';
import 'widgets/notes_search_bar.dart';
import 'widgets/notes_split_view.dart';

/// Signature of the export-note seam used by [NotesPage].
///
/// Defaults to the top-level [notes_exporter.exportNote]. Widget tests
/// substitute a fake to assert that the editor-toolbar export button invokes
/// the exporter with the selected note and its tags, without touching the
/// filesystem or platform channels.
typedef NotesPageExportFn =
    Future<void> Function(BuildContext context, Note note, List<Tag> tags);

/// Notes page — standalone sidebar area for free-form notes.
///
/// Master-detail layout mirroring [HistoryPage]'s split view, but deliberately
/// minimal: flat note list on the left, always-editable plain-text editor on
/// the right, plus an active/trash filter with favourite, trash, restore and
/// delete-forever actions (Ticket 04), tag editing/display (Ticket 05),
/// content/tag search with Ctrl/Cmd+F focus (Ticket 06), txt/md export
/// (Ticket 07) and voice input at the cursor position (Ticket 08).
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.exportFn = notes_exporter.exportNote});

  /// Injection seam for the export flow.
  ///
  /// Defaults to the production [notes_exporter.exportNote]. Widget tests
  /// substitute a fake to assert that the editor-toolbar export button
  /// invokes the exporter with the open note and its tags without touching
  /// the filesystem or platform channels.
  final NotesPageExportFn exportFn;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  /// Editor controller + focus node live HERE, not in [NoteEditorPanel] —
  /// the panel rebuilds on every stream emit, and panel-owned controllers
  /// would lose cursor position and IME state on each rebuild.
  final TextEditingController _editorController = TextEditingController();
  final FocusNode _editorFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// Captured once in [initState] so the autosave/dispose chain never touches
  /// `ref` after the widget is unmounted.
  late final NotesActions _actions;
  late final NoteAutosave _autosave;

  String? _selectedNoteId;

  /// Guards the controller listener while the editor text is swapped
  /// programmatically on note switch — without it, the swap itself would
  /// schedule a bogus autosave for the newly selected note.
  bool _syncingEditor = false;

  @override
  void initState() {
    super.initState();
    _actions = ref.read(notesActionsProvider);
    _autosave = NoteAutosave(onSave: _actions.save);
    _editorController.addListener(_onEditorChanged);
    // One-time safety-net sweep: drop stale empty notes left behind by a
    // previous session (fire-and-forget; the stream provider picks it up).
    unawaited(_actions.purgeEmpty());
  }

  @override
  void dispose() {
    final lastId = _selectedNoteId;
    final lastContent = _editorController.text;
    // Empty-discard on page teardown: flush the pending autosave, then
    // permanently delete the last selected note if it is blank, then cancel
    // the autosave timer. Fire-and-forget — dispose is synchronous and the
    // chain only uses values captured above.
    unawaited(() async {
      await _autosave.flush();
      if (lastId != null && lastContent.trim().isEmpty) {
        await _actions.deleteForever(lastId);
      }
      _autosave.dispose();
    }());
    _editorController.dispose();
    _editorFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    if (_syncingEditor) return;
    final id = _selectedNoteId;
    if (id == null) return;
    _autosave.schedule(id, _editorController.text);
  }

  /// Replaces the editor text without triggering an autosave schedule.
  ///
  /// Normalizes Windows line endings (`\r\n` → `\n`) before writing — the
  /// plain-text-paste guarantee (US18). TextField already strips rich text,
  /// so CRLF normalization is the only active measure needed.
  void _setEditorText(String text) {
    _syncingEditor = true;
    final normalized = text.replaceAll('\r\n', '\n');
    _editorController.text = normalized;
    _editorController.selection = TextSelection.collapsed(
      offset: normalized.length,
    );
    _syncingEditor = false;
  }

  /// Flushes the pending autosave for the currently selected note and
  /// permanently discards it when its content is blank (empty-discard rule:
  /// leaving an empty note deletes it outright — never to trash).
  Future<void> _leaveCurrentNote() async {
    final previousId = _selectedNoteId;
    final previousContent = _editorController.text;
    await _autosave.flush();
    if (previousId != null && previousContent.trim().isEmpty) {
      await _actions.deleteForever(previousId);
    }
  }

  Future<void> _selectNote(Note note) async {
    if (note.id == _selectedNoteId) return;
    await _leaveCurrentNote();
    if (!mounted) return;
    setState(() => _selectedNoteId = note.id);
    _setEditorText(note.content);
  }

  Future<void> _createNote() async {
    // Creating from the trash view: switch back to the active filter first,
    // otherwise the freshly created (active) note would be invisible.
    if (ref.read(notesFilterProvider) == NotesFilter.trash) {
      ref.read(notesFilterProvider.notifier).set(NotesFilter.active);
    }
    // Creating a note is a selection change too — apply the same
    // empty-discard rule to the note being left behind.
    await _leaveCurrentNote();
    final note = await _actions.create();
    if (!mounted) return;
    setState(() => _selectedNoteId = note.id);
    _setEditorText(note.content);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocusNode.requestFocus();
    });
  }

  Future<void> _closeEditor() async {
    await _leaveCurrentNote();
    if (!mounted) return;
    setState(() => _selectedNoteId = null);
    _setEditorText('');
  }

  /// Switching between active and trash always closes the editor — carrying a
  /// selection across the filter boundary would show a note that isn't in the
  /// visible list (and would dodge the empty-discard rule on the way out).
  Future<void> _setFilter(NotesFilter filter) async {
    if (ref.read(notesFilterProvider) == filter) return;
    await _leaveCurrentNote();
    if (!mounted) return;
    setState(() => _selectedNoteId = null);
    _setEditorText('');
    ref.read(notesFilterProvider.notifier).set(filter);
  }

  /// Flushes first so a just-typed, not-yet-saved draft can't be overwritten
  /// by the stream re-emitting the stale pre-flush content after the toggle.
  Future<void> _toggleFavorite(Note note) async {
    await _autosave.flush();
    await _actions.togglePin(note.id, pinned: !note.pinned);
  }

  Future<void> _moveToTrash(Note note) async {
    // Flush before mutating so a pending draft is persisted — restoring from
    // the trash must bring back exactly what the user last saw.
    await _autosave.flush();
    await _actions.moveToTrash(note.id);
    if (!mounted) return;
    if (note.id == _selectedNoteId) {
      // Like _closeEditor, but without _leaveCurrentNote — the pending
      // autosave was already flushed above.
      setState(() => _selectedNoteId = null);
      _setEditorText('');
    }
    final l10n = L10n.of(context);
    WpToast.show(
      context,
      message: l10n.notesMovedToTrash,
      type: WpToastType.info,
      duration: const Duration(seconds: 4),
      actionLabel: l10n.notesUndo,
      onAction: () => _actions.restore(note.id),
    );
  }

  /// No flush needed — restore only clears `deletedAt`, never touches content.
  Future<void> _restoreNote(Note note) async {
    await _actions.restore(note.id);
  }

  Future<void> _addTag(Note note, String tagName) =>
      _actions.addTag(note.id, tagName);

  Future<void> _removeTag(Note note, String tagId) =>
      _actions.removeTag(note.id, tagId);

  /// Inserts [transcript] at the editor's current selection (replacing any
  /// selected range) — a genuine content edit, so it goes through the normal
  /// `_onEditorChanged` listener → autosave debounce, unlike `_setEditorText`
  /// (which suppresses autosave via `_syncingEditor` for programmatic note
  /// switches).
  void _insertVoiceTranscript(String transcript) {
    final text = _editorController.text;
    final selection = _editorController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, transcript);
    _editorController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + transcript.length),
    );
  }

  void _exportNote(Note note, List<Tag> tags) {
    // Fire-and-forget: the exporter surfaces success/error via WpToast.
    widget.exportFn(context, note, tags);
  }

  /// Only reachable from the trash view (list tile / editor toolbar there).
  Future<void> _deleteForever(Note note) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.notesDeleteForeverConfirm,
      // The dialog requires a message; the derived note title tells the user
      // exactly which note is about to go — no extra ARB key needed.
      message: deriveNoteTitle(note.content) ?? l10n.notesUntitled,
      confirmLabel: l10n.notesDeleteForever,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
    await _actions.deleteForever(note.id);
    if (!mounted) return;
    if (note.id == _selectedNoteId) {
      setState(() => _selectedNoteId = null);
      _setEditorText('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final filter = ref.watch(notesFilterProvider);
    final isTrash = filter == NotesFilter.trash;
    // Kept solely for the error-retry invalidate below — the list itself
    // reads from filteredNotesProvider (filter + search combined).
    final activeStreamProvider = isTrash ? trashNotesProvider : notesProvider;
    final notesAsync = ref.watch(filteredNotesProvider);
    final query = ref.watch(notesSearchProvider).trim();
    final hasQuery = query.isNotEmpty;
    final tagsByNoteId =
        ref.watch(allNoteTagsProvider).value ?? const <String, List<Tag>>{};
    // Watched unconditionally in build (empty fallback when nothing is
    // selected) so Riverpod manages the family subscription correctly.
    final selectedNoteTags = _selectedNoteId != null
        ? (ref.watch(noteTagsProvider(_selectedNoteId!)).value ?? const <Tag>[])
        : const <Tag>[];

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          SingleActivator(
            LogicalKeyboardKey.keyF,
            control: !Platform.isMacOS,
            meta: Platform.isMacOS,
          ): () {
            _searchFocusNode.requestFocus();
          },
        },
        // Focus wrapper: autofocus ensures a descendant of CallbackShortcuts
        // has focus when the notes page loads so that the Ctrl+F / Cmd+F
        // shortcut is reachable via key-event bubbling without stealing
        // interactive focus (see settings_page.dart for the same pattern).
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: Column(
            children: [
              _NotesHeader(onCreate: _createNote),
              NotesSearchBar(
                currentFilter: filter,
                onFilterChanged: _setFilter,
                isDark: isDark,
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
                onSearchChanged: () {
                  ref
                      .read(notesSearchProvider.notifier)
                      .set(_searchController.text);
                  // Explicit rebuild so the clear button and result count react
                  // to every keystroke, independent of provider plumbing.
                  setState(() {});
                },
                resultCount: notesAsync.value?.length ?? 0,
                showResultCount: hasQuery,
              ),
              Expanded(
                child: notesAsync.when(
                  data: (notes) {
                    if (notes.isEmpty) {
                      if (hasQuery) {
                        return WpEmptyState(
                          icon: LucideIcons.searchX,
                          title: l10n.notesNoResults,
                          hint: l10n.notesNoResultsHint(query),
                          actionLabel: l10n.notesClearSearch,
                          onAction: () {
                            _searchController.clear();
                            ref.read(notesSearchProvider.notifier).set('');
                            setState(() {});
                          },
                        );
                      }
                      // No action button in either empty state on purpose: the
                      // header's "New note" button is always visible and already
                      // offers the only sensible action — a second identically
                      // labeled button would be redundant, and the trash empty
                      // state has no action at all.
                      return WpEmptyState(
                        icon: isTrash
                            ? LucideIcons.trash2
                            : LucideIcons.stickyNote,
                        title: isTrash
                            ? l10n.notesTrashEmpty
                            : l10n.notesEmptyTitle,
                        hint: isTrash
                            ? l10n.notesTrashEmptyHint
                            : l10n.notesEmptyHint,
                      );
                    }
                    Note? selectedNote;
                    if (_selectedNoteId != null) {
                      final idx = notes.indexWhere(
                        (n) => n.id == _selectedNoteId,
                      );
                      selectedNote = idx >= 0 ? notes[idx] : null;
                    }
                    final currentNote = selectedNote;
                    return NotesSplitView(
                      notes: notes,
                      tagsByNoteId: tagsByNoteId,
                      isDark: isDark,
                      isTrashView: isTrash,
                      selectedNote: selectedNote,
                      selectedNoteTags: selectedNoteTags,
                      editorController: _editorController,
                      editorFocusNode: _editorFocusNode,
                      onNoteTap: _selectNote,
                      onCloseEditor: _closeEditor,
                      onFavoriteToggle: _toggleFavorite,
                      onMoveToTrash: _moveToTrash,
                      onRestore: _restoreNote,
                      onDeleteForever: _deleteForever,
                      onAddTag: (name) {
                        if (currentNote != null) _addTag(currentNote, name);
                      },
                      onRemoveTag: (id) {
                        if (currentNote != null) _removeTag(currentNote, id);
                      },
                      onExport: () {
                        if (currentNote != null) {
                          _exportNote(currentNote, selectedNoteTags);
                        }
                      },
                      onVoiceTranscript: _insertVoiceTranscript,
                    );
                  },
                  loading: () => _NotesSkeleton(isDark: isDark),
                  error: (e, _) => WpEmptyState(
                    icon: LucideIcons.triangleAlert,
                    title: l10n.errorGeneric,
                    actionLabel: l10n.actionRetry,
                    onAction: () => ref.invalidate(activeStreamProvider),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page header — "New note" action
// ---------------------------------------------------------------------------

class _NotesHeader extends StatelessWidget {
  const _NotesHeader({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        WpSpacing.sm,
        WpSpacing.md,
        WpSpacing.xs,
      ),
      child: Row(
        children: [
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(LucideIcons.plus, size: WpIconSize.md),
            label: Text(l10n.notesNewNote),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — list-shaped placeholder rows (see _HistorySkeleton)
// ---------------------------------------------------------------------------

class _NotesSkeleton extends StatelessWidget {
  const _NotesSkeleton({required this.isDark});

  final bool isDark;

  @override
  // loam-ignore: code-duplicates – mirrors _HistorySkeleton in
  // history_page.dart by design (Notizen is a structural, not a shared,
  // Vorbild of History per the Ticket-02 plan — no feature-to-feature
  // dependency between lib/features/notes and lib/features/history).
  Widget build(BuildContext context) {
    final boxColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: WpSpacing.xs),
      itemBuilder: (_, _) => Container(
        // Note tiles carry a title + two-line preview — slightly taller
        // placeholder than the history skeleton's 52.
        height: 64,
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: WpRadius.borderMd,
        ),
      ),
    );
  }
}
