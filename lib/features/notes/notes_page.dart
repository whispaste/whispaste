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
import '../history/widgets/history_helpers.dart' show isTextFieldFocused;
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
  final FocusNode _listFocusNode = FocusNode();

  /// Captured once in [initState] so the autosave/dispose chain never touches
  /// `ref` after the widget is unmounted.
  late final NotesActions _actions;
  late final NoteAutosave _autosave;

  String? _selectedNoteId;

  /// Keyboard-focused note ID (distinct from the selected/editor note).
  String? _focusedNoteId;

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
    _editorFocusNode.addListener(_onEditorFocusChanged);
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
    _listFocusNode.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    if (_syncingEditor) return;
    final id = _selectedNoteId;
    if (id == null) return;
    _autosave.schedule(id, _editorController.text);
  }

  /// Flushes on blur (window loses focus, user clicks elsewhere without
  /// switching notes) — one of the four flush triggers documented on
  /// [NoteAutosave.schedule].
  void _onEditorFocusChanged() {
    if (!_editorFocusNode.hasFocus) {
      unawaited(_autosave.flush());
    }
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
    setState(() {
      _selectedNoteId = note.id;
      // Align the keyboard cursor with the click so arrow-key navigation
      // continues seamlessly from the opened note.
      _focusedNoteId = note.id;
    });
    _setEditorText(note.content);
  }

  /// Moves the list's virtual keyboard cursor by [delta] within [notes].
  void _moveFocus(int delta, List<Note> notes) {
    if (notes.isEmpty) return;
    final currentIdx = notes.indexWhere((n) => n.id == _focusedNoteId);
    final int nextIdx;
    if (currentIdx < 0) {
      nextIdx = delta > 0 ? 0 : notes.length - 1;
    } else {
      nextIdx = (currentIdx + delta).clamp(0, notes.length - 1);
    }
    setState(() => _focusedNoteId = notes[nextIdx].id);
  }

  Note? _focusedNote(List<Note> notes) {
    if (_focusedNoteId == null) return null;
    final idx = notes.indexWhere((n) => n.id == _focusedNoteId);
    return idx >= 0 ? notes[idx] : null;
  }

  /// Handles bare-key events on the list focus node (arrows, enter, delete,
  /// backspace, F, escape). Returns [KeyEventResult.ignored] when a text
  /// field has focus so [DefaultTextEditingShortcuts] can process the keys
  /// normally — critical here because the note editor is a permanently
  /// focused text field; without this guard Delete/Backspace/arrow keys
  /// would eat text input instead of editing it.
  KeyEventResult _handleListKeyEvent(
    FocusNode node,
    KeyEvent event,
    List<Note> notes,
    bool isTrash,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isTextFieldFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1, notes);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1, notes);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final note = _focusedNote(notes);
      if (note != null) _selectNote(note);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      final note = _focusedNote(notes);
      if (note != null) {
        if (isTrash) {
          _deleteForever(note);
        } else {
          _moveToTrash(note);
        }
      }
      return KeyEventResult.handled;
    }
    // F: toggle favourite on the focused note (active view only — trash
    // view has no favourite star). Excludes Ctrl/Cmd+F: without this guard,
    // the bare-key check below fires before the modifier combo can bubble up
    // to the page-level CallbackShortcuts that focuses the search field.
    final hasModifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.keyF && !isTrash && !hasModifier) {
      final note = _focusedNote(notes);
      if (note != null) _toggleFavorite(note);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_selectedNoteId != null) {
        _closeEditor();
      } else if (_focusedNoteId != null) {
        setState(() => _focusedNoteId = null);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

  /// Exports the live editor text, not the (possibly stale, pre-debounce)
  /// DB-streamed [note] — same "controller, not DB" rule as copy (Ticket 03).
  void _exportNote(Note note, List<Tag> tags) {
    // Fire-and-forget: the exporter surfaces success/error via WpToast.
    widget.exportFn(
      context,
      note.copyWith(content: _editorController.text),
      tags,
    );
  }

  /// Only reachable from the trash view (list tile / editor toolbar there).
  Future<void> _deleteForever(Note note) async {
    // Flush first, same as favourite/trash: any pending autosave write
    // completes (or its timer is cancelled) before the row disappears,
    // instead of racing the delete.
    await _autosave.flush();
    if (!mounted) return;
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
    // Fallback list used by the shortcut/focus layer below, which now wraps
    // ALL notesAsync states (not just the populated data branch) — empty
    // during loading/error, harmless since _moveFocus/_focusedNote no-op on
    // an empty list.
    final notes = notesAsync.value ?? const <Note>[];
    Note? currentNote;
    if (_selectedNoteId != null) {
      final idx = notes.indexWhere((n) => n.id == _selectedNoteId);
      currentNote = idx >= 0 ? notes[idx] : null;
    }

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
        // Focus wrapper: the list focus node further down is the real initial
        // focus target now (autofocus there); Ctrl/Cmd+F still bubbles up from
        // it to this outer handler (same pattern as history_page.dart, whose
        // outer wrapper is also autofocus: false and only binds Ctrl/Cmd+F).
        child: Focus(
          autofocus: false,
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
                child: CallbackShortcuts(
                  // Wraps ALL notesAsync states (data-with-notes, both empty
                  // states, loading, error) — not just the populated data
                  // branch. Ctrl/Cmd+N/+C used to live only inside the
                  // non-empty data branch, which left them (and Ctrl/Cmd+F,
                  // which depends on this Focus node holding focus for its
                  // key event to bubble to the page-level handler above)
                  // dead exactly when a first-time user or an empty search
                  // result needed "create a note" most. Only modifier-combo
                  // shortcuts live here; bare keys (arrows, enter, delete,
                  // backspace, escape, F) are handled in Focus.onKeyEvent
                  // below so they can return KeyEventResult.ignored when a
                  // text field has focus.
                  bindings: _buildListShortcuts(
                    context,
                    l10n,
                    notes,
                    currentNote,
                  ),
                  child: Focus(
                    focusNode: _listFocusNode,
                    autofocus: true,
                    // Bare-key shortcuts are handled here via onKeyEvent
                    // so that KeyEventResult.ignored can be returned when
                    // a text field has focus. CallbackShortcuts always
                    // consumes matched events, which would prevent
                    // DefaultTextEditingShortcuts from processing
                    // Backspace/Enter/etc. in the always-editable note
                    // editor.
                    onKeyEvent: (node, event) =>
                        _handleListKeyEvent(node, event, notes, isTrash),
                    child: _buildNotesContent(
                      notesAsync: notesAsync,
                      isTrash: isTrash,
                      hasQuery: hasQuery,
                      query: query,
                      isDark: isDark,
                      l10n: l10n,
                      tagsByNoteId: tagsByNoteId,
                      currentNote: currentNote,
                      selectedNoteTags: selectedNoteTags,
                      activeStreamProvider: activeStreamProvider,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Modifier-combo bindings for the list-level shortcut layer (Ctrl/Cmd+N,
  /// Ctrl/Cmd+C). Split out of [build] to keep its cyclomatic complexity in
  /// check — bare-key shortcuts live in [_handleListKeyEvent] instead.
  Map<ShortcutActivator, VoidCallback> _buildListShortcuts(
    BuildContext context,
    L10n l10n,
    List<Note> notes,
    Note? currentNote,
  ) {
    return <ShortcutActivator, VoidCallback>{
      // Ctrl+N / Cmd+N: create a new note.
      SingleActivator(
        LogicalKeyboardKey.keyN,
        control: !Platform.isMacOS,
        meta: Platform.isMacOS,
      ): () {
        if (isTextFieldFocused()) return;
        _createNote();
      },
      // Ctrl+C / Cmd+C: copy the open/focused note's content.
      SingleActivator(
        LogicalKeyboardKey.keyC,
        control: !Platform.isMacOS,
        meta: Platform.isMacOS,
      ): () {
        if (isTextFieldFocused()) return;
        final note = currentNote ?? _focusedNote(notes);
        if (note == null) return;
        Clipboard.setData(ClipboardData(text: note.content));
        WpToast.show(
          context,
          message: l10n.notesCopied,
          type: WpToastType.success,
          duration: const Duration(seconds: 2),
        );
      },
    };
  }

  /// Renders the notesAsync states (populated list, both empty states,
  /// loading skeleton, error) — the [Focus]/[CallbackShortcuts] layer in
  /// [build] wraps this unconditionally so shortcuts stay reachable in
  /// every state, not just the populated one. Split out of [build] to keep
  /// its cyclomatic complexity in check.
  Widget _buildNotesContent({
    required AsyncValue<List<Note>> notesAsync,
    required bool isTrash,
    required bool hasQuery,
    required String query,
    required bool isDark,
    required L10n l10n,
    required Map<String, List<Tag>> tagsByNoteId,
    required Note? currentNote,
    required List<Tag> selectedNoteTags,
    required StreamProvider<List<Note>> activeStreamProvider,
  }) {
    return notesAsync.when(
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
            icon: isTrash ? LucideIcons.trash2 : LucideIcons.stickyNote,
            title: isTrash ? l10n.notesTrashEmpty : l10n.notesEmptyTitle,
            hint: isTrash ? l10n.notesTrashEmptyHint : l10n.notesEmptyHint,
          );
        }
        return NotesSplitView(
          notes: notes,
          tagsByNoteId: tagsByNoteId,
          isDark: isDark,
          isTrashView: isTrash,
          selectedNote: currentNote,
          focusedNoteId: _focusedNoteId,
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
