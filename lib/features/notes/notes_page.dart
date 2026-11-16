import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/accessibility/announce.dart';
import '../../core/config/command_shortcut.dart';
import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/data/text_writer/text_writer.dart';
import '../../core/data/note_asset_storage.dart';
import '../../core/data/note_version_limits.dart';
import '../../core/logging/app_logger.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/text/text_undo.dart';
import '../../core/text/markdown_plain_text.dart';
import '../../core/navigation/page_state.dart' show notesEditorTargetProvider;
import '../../core/navigation/work_state.dart';
import '../../core/utils/focus_helpers.dart';
import '../../services/notes/notes_exporter.dart' as notes_exporter;
import '../../services/recording_orchestrator.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/find_replace.dart';
import '../../widgets/wp_favourite_star.dart';
import '../../widgets/wp_save_status.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_notice_bar.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_list_skeleton.dart';
import '../../widgets/wp_multi_select_bar.dart';
import '../../widgets/wp_text_field.dart';
import 'data/note_asset_store.dart';
import 'data/note_autosave.dart';
import 'data/note_clipboard_image.dart';
import 'data/note_title.dart';
import 'data/note_version_scheduler.dart';
import 'data/notes_actions.dart';
import 'data/notes_view_options.dart';
import 'data/writing_focus.dart';
import 'data/providers.dart';
import 'voice_insert.dart';
import '../history/data/history_lock.dart';
import 'widgets/notes_pin_gate.dart';
import 'blocks/long_note_layout.dart';
import 'widgets/go_to_paragraph_dialog.dart';
import 'widgets/note_editor_panel.dart';
import 'widgets/note_markup_controller.dart';
import 'widgets/note_versions_dialog.dart';
import 'widgets/notes_bulk_tag_dialog.dart';
import 'widgets/notes_search_bar.dart';
import '../../widgets/wp_collection_split.dart';
import 'widgets/notes_list_view.dart';
import 'widgets/writing_focus_bar.dart';
import '../../widgets/wp_collection_page.dart';
import '../../widgets/wp_copy_feedback.dart';

final _log = AppLogger('NotesPage');

/// The save and snapshot chain of the most recent page teardown, so a test
/// can wait for it instead of for a duration.
@visibleForTesting
Future<void> notesPageLastTeardown = Future<void>.value();

/// Signature of the export-note seam used by [NotesPage].
///
/// Defaults to the top-level [notes_exporter.exportNote]. Widget tests
/// substitute a fake to assert that the editor-toolbar export button invokes
/// the exporter with the selected note and its tags, without touching the
/// filesystem or platform channels.
typedef NotesPageExportFn =
    Future<void> Function(BuildContext context, Note note, List<Tag> tags);

/// Signature of the multi-select export seam used by [NotesPage] (#655).
typedef NotesPageExportManyFn =
    Future<void> Function(
      BuildContext context,
      List<Note> notes,
      Map<String, List<Tag>> tagsByNoteId,
    );

/// Placeholder-bar height of the loading skeleton, matched to the real
/// [NotesListTile]. Measured at a 340 dp list column with the populated
/// fixture: two-line title, two-line preview and the update time on its own
/// metadata line. That is taller than the earlier single-line-title layout,
/// so the value moved from 104 to 139 when the tile was aligned with history.
/// The residual step when switching areas mid-load is the step the loaded
/// lists have too.
const _notesSkeletonRowHeight = 139.0;

/// Notes page — standalone sidebar area for free-form notes.
///
/// Master-detail layout mirroring [HistoryPage]'s split view, but deliberately
/// minimal: flat note list on the left, always-editable plain-text editor on
/// the right, plus an active/trash filter with favourite, trash, restore and
/// delete-forever actions (Ticket 04), tag editing/display (Ticket 05),
/// content/tag search with Ctrl/Cmd+F focus (Ticket 06), txt/md export
/// (Ticket 07) and voice input at the cursor position (Ticket 08).
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({
    super.key,
    this.exportFn = notes_exporter.exportNote,
    this.exportManyFn = notes_exporter.exportNotes,
  });

  /// Injection seam for the multi-select export (#655): one file for all
  /// selected notes. Defaults to [notes_exporter.exportNotes].
  final NotesPageExportManyFn exportManyFn;

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
  ///
  /// A [WpFindHighlightController] so the editor toolbar's find bar can tint
  /// its hits — a [TextField] only paints a *selection* while focused, and
  /// while a query is being typed the focus is in the find field.
  final NoteMarkupController _editorController = NoteMarkupController();

  /// Undo for the open note, across the short and the long editor; each
  /// note keeps its own history while the user switches around (#651).
  late final TextUndoController _editorUndo;
  final FocusNode _editorFocusNode = FocusNode();

  /// Asks the editor's body field to jump to the end of the note. A signal
  /// rather than a [ScrollController] owned here: the split view mounts and
  /// unmounts the editor panel around this page (closing the detail column,
  /// the compact layout), and a controller attached to two fields at once —
  /// or to none — is an error a signal cannot have. See
  /// [WpTextField.scrollToEnd].
  final WpScrollToEndSignal _scrollEditorToEndSignal = WpScrollToEndSignal();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _listFocusNode = FocusNode();

  /// Captured once in [initState] so the autosave/dispose chain never touches
  /// `ref` after the widget is unmounted.
  late final NotesActions _actions;

  /// The app-wide providers, kept so a notice can still be raised after this
  /// page is gone (a snapshot taken on teardown, #636).
  late final ProviderContainer _container;

  /// Text of the "version too large" notice, refreshed on each build because
  /// [L10n] cannot be read once the page is disposed.
  String _tooLargeNoticeText = '';

  /// View and text direction of the page, kept for announcing that notice
  /// after the page is gone (no context is left then).
  FlutterView? _announceView;
  TextDirection _announceDirection = TextDirection.ltr;
  late final NoteAutosave _autosave;

  /// What the editor's status line says about saving the body (#1498).
  final ValueNotifier<WpSaveStatus> _saveStatus = ValueNotifier(
    WpSaveStatus.idle,
  );

  /// Bumped on every scheduled edit: a write only reports "saved" when no
  /// newer edit came in while it ran.
  int _editGeneration = 0;

  /// The note [_saveStatus] speaks about; opening another one resets it.
  String? _statusNoteId;
  StreamSubscription<TextMerge>? _mergeSub;

  /// Session holder for the open note across page switches (#1074).
  late final NotesWorkState _work;

  /// Decides when an edit becomes a version: after an idle pause here, and
  /// at once on Ctrl/Cmd+S (ticket).
  late final NoteVersionScheduler _versionScheduler;

  /// Bumped after a version restore so the title field reloads its text.
  int _titleRevision = 0;

  static const _imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp'];

  /// Same reason, for the two quick-note hooks this page registers on the
  /// orchestrator — [dispose] must be able to unregister them without `ref`.
  RecordingOrchestrator? _orchestrator;

  String? _selectedNoteId;

  /// The note [_createNote] has just written, held only until the notes
  /// stream re-emits with it.
  ///
  /// Without it, [build] resolves `currentNote` to `null` for the length of
  /// that async gap and the split view runs a full close animation, which
  /// unmounts the editor panel while its field holds the focus — and
  /// detaching a focused [FocusNode] silently drops the focus notification
  /// (`FocusManager._markDetached` removes the node from the pending set) and
  /// unparents the node. The field is then left painting a focus ring it
  /// cannot type into, which is what "a new note starts out locked" was.
  Note? _pendingCreatedNote;

  /// Keyboard-focused note ID (distinct from the selected/editor note).
  String? _focusedNoteId;

  /// Multi-select (#655): on while rows show checkboxes. [_checkedIds] keeps
  /// the click order, which is the order a merge combines the notes in.
  bool _selecting = false;
  final Set<String> _checkedIds = <String>{};

  /// Anchor of a Shift+click / Shift+arrow range.
  String? _lastClickedId;

  /// Guards the controller listener while the editor text is swapped
  /// programmatically on note switch — without it, the swap itself would
  /// schedule a bogus autosave for the newly selected note.
  bool _syncingEditor = false;

  /// Last body text handed to [_autosave] — see [_onEditorChanged] for why a
  /// notification is not by itself proof that anything was typed.
  String? _lastScheduledContent;

  @override
  void initState() {
    super.initState();
    _actions = ref.read(notesActionsProvider);
    _container = ProviderScope.containerOf(context, listen: false);
    _autosave = NoteAutosave(
      onSave: _persistNote,
      load: (id) async => (await _actions.getNote(id))?.content,
    );
    _mergeSub = _autosave.writer.merges.listen(_onTextMerged);
    _versionScheduler = NoteVersionScheduler(onSnapshot: _takeIdleSnapshot);
    _editorController.addListener(_onEditorChanged);
    _editorUndo = TextUndoController(_editorController);
    _editorFocusNode.addListener(_onEditorFocusChanged);
    // Paragraph focus paints through the controller, so it follows the
    // providers here instead of rebuilding the editor (#669).
    ref.listenManual(
      paragraphDimProvider,
      (_, dim) => _editorController.paragraphFocus = dim,
      fireImmediately: true,
    );
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // Quick-note takeover, registered for exactly as long as this area is on
    // screen (see the two handlers). Leaving the area, switching notes and
    // closing the editor all resolve through the note-id check inside
    // [_quickNoteLiveOverride] and this pair of initState/dispose lines.
    _orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    _orchestrator!
      ..quickNoteLiveEditorOverride = _quickNoteLiveOverride
      ..quickNoteEditorFlush = _autosave.flush;
    // One-time safety-net sweep: drop stale empty notes left behind by a
    // previous session (fire-and-forget; the stream provider picks it up).
    unawaited(_actions.purgeEmpty());
    // Image folders of notes that no longer exist (crash, factory reset).
    unawaited(_actions.sweepAssetFolders());
    // Deep link from a quick-note append that navigated here — the target is
    // already set when this page mounts, so `ref.listen` in build() would
    // never see it change. Post-frame so the editor exists to scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeEditorTarget();
    });
    // Back on this page after a switch: same search text in the field (the
    // query itself lives in [notesSearchProvider]) and the same note open
    // (#1074). A pending deep link wins over the remembered note.
    _searchController.text = ref.read(notesSearchProvider);
    _work = ref.read(notesWorkStateProvider);
    final remembered = _work.selectedNoteId;
    if (remembered != null && ref.read(notesEditorTargetProvider) == null) {
      unawaited(_reopenRemembered(remembered));
    }
  }

  /// Reopens the note that was open when the user left the page. Waits for
  /// the previous page's teardown first, so the editor gets the saved text,
  /// and leaves the page empty when the note was discarded as blank there.
  Future<void> _reopenRemembered(String noteId) async {
    await notesPageLastTeardown;
    final note = await _actions.getNote(noteId);
    // Something else was opened in the meantime (a click, a deep link).
    if (!mounted || note == null || _selectedNoteId != null) return;
    setState(() {
      _selectedNoteId = note.id;
      _focusedNoteId = note.id;
    });
    _showStored(note);
  }

  @override
  void dispose() {
    _work.selectedNoteId = _selectedNoteId;
    // Focus mode belongs to this page: leaving the area restores the app
    // frame and the window (#669). After the frame, as providers must not
    // change while the tree is being torn down.
    if (_container.read(writingFocusProvider)) {
      final focus = _container.read(writingFocusProvider.notifier);
      Future.microtask(focus.exit);
    }
    unawaited(_mergeSub?.cancel());
    // Unregister first: an append arriving mid-teardown must fall through to
    // the direct database write, not into a controller that is about to go.
    _orchestrator
      ?..quickNoteLiveEditorOverride = null
      ..quickNoteEditorFlush = null;
    final lastId = _selectedNoteId;
    final lastContent = _editorController.text;
    final hadPendingSnapshot = _versionScheduler.hasPending;
    _versionScheduler.dispose();
    // Empty-discard on page teardown: flush the pending autosave, then
    // permanently delete the last selected note if it is blank (unless it is
    // the marked quick note — discardIfBlank exempts it), then cancel the
    // autosave timer. Fire-and-forget — dispose is synchronous and the chain
    // only uses values captured above.
    final teardown = () async {
      try {
        await _autosave.flush();
        if (lastId != null &&
            hadPendingSnapshot &&
            lastContent.trim().isNotEmpty) {
          await _takeVersionSnapshot(lastId);
        }
        if (lastId != null && lastContent.trim().isEmpty) {
          await _actions.discardIfBlank(lastId);
        }
      } catch (e, st) {
        // Best effort: the page is gone, so nothing can show this error. The
        // database may already be closed when the app shuts down.
        _log.warning('Could not finish saving the note on teardown', e, st);
      } finally {
        _autosave.dispose();
      }
    }();
    notesPageLastTeardown = teardown;
    unawaited(teardown);
    _editorUndo.dispose();
    _editorController.dispose();
    // Removed before dispose(): FocusNode.dispose() synchronously unfocuses
    // (and thus notifies listeners) as part of teardown — without this, the
    // blur listener would fire mid-teardown and flush against an _autosave
    // that the chain above is concurrently disposing.
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _editorFocusNode.removeListener(_onEditorFocusChanged);
    _editorFocusNode.dispose();
    _scrollEditorToEndSignal.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    _saveStatus.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    if (_syncingEditor) return;
    final id = _selectedNoteId;
    if (id == null) return;
    final text = _editorController.text;
    // A controller notifies for more than typed characters: a caret move, and
    // — since the find bar arrived — a change of which matches are
    // highlighted. Scheduling those would write the note back unchanged and
    // bump its `updatedAt`, reordering the list under a user who only opened
    // find-and-replace and looked at it.
    if (text == _lastScheduledContent) return;
    _lastScheduledContent = text;
    _editGeneration++;
    _saveStatus.value = WpSaveStatus.saving;
    _autosave.schedule(id, text);
    _versionScheduler.touch(id);
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
  ///
  /// Switching to another note parks the undo history of the one left;
  /// replacing the text of the same note is an undoable step (#651).
  void _setEditorText(String text, {String? noteId}) {
    _syncingEditor = true;
    final normalized = text.replaceAll('\r\n', '\n');
    _editorUndo.open(noteId ?? _selectedNoteId ?? '', () {
      _editorController.text = normalized;
      _editorController.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
    });
    // The swap is the new baseline for [_onEditorChanged]: without this, the
    // first real keystroke after switching *back* to a note whose text the
    // user had already scheduled would compare against the wrong note's text.
    _lastScheduledContent = normalized;
    // A find bar left open on the previous note has no business tinting this
    // one's text at the old offsets.
    _editorController.clearFindHighlight();
    _syncingEditor = false;
  }

  /// Opens [note] as stored: its text is the writer's merge base for the
  /// edits that follow (#676).
  void _showStored(Note note) {
    if (note.id != _statusNoteId) {
      _statusNoteId = note.id;
      _saveStatus.value = WpSaveStatus.idle;
    }
    _autosave.opened(note.id, note.content);
    _setEditorText(note.content, noteId: note.id);
  }

  /// A save merged a change made elsewhere (quick-note append, automation
  /// API) into this note: show the merged text if the editor still holds
  /// exactly what went into the merge, keeping the caret where it was.
  void _onTextMerged(TextMerge merge) {
    if (!mounted ||
        merge.key != _autosave.keyOf(_selectedNoteId ?? '') ||
        _editorController.text != merge.ours) {
      return;
    }
    final selection = _editorController.selection;
    final merged = merge.merged.replaceAll('\r\n', '\n');
    _syncingEditor = true;
    // An undoable step, so the history stays in step with the text.
    _editorUndo.runCommand(
      () => _editorController.value = TextEditingValue(
        text: merged,
        selection: selection.isValid && selection.end <= merged.length
            ? selection
            : TextSelection.collapsed(offset: merged.length),
      ),
    );
    _lastScheduledContent = merged;
    _syncingEditor = false;
  }

  /// Flushes the pending autosave for the currently selected note and
  /// permanently discards it when its content is blank (empty-discard rule:
  /// leaving an empty note deletes it outright — never to trash). The marked
  /// quick note is exempt even while blank (`discardIfBlank`) — it must
  /// survive until unmarked, not just until the next dictation lands.
  Future<void> _leaveCurrentNote() async {
    // Every selection change funnels through here, which makes it the one
    // place the create-time fallback below has to be dropped again.
    _pendingCreatedNote = null;
    // A notice belongs to the note it was raised on.
    ref.read(wpPageNoticeProvider(WpNoticePage.notes).notifier).dismiss();
    final previousId = _selectedNoteId;
    final previousContent = _editorController.text;
    await _autosave.flush();
    // A blank note is deleted together with its versions, so a snapshot taken
    // just before that would be written only to be removed again.
    if (previousId != null && previousContent.trim().isEmpty) {
      if (await _actions.discardIfBlank(previousId)) return;
    }
    if (previousId != null && _versionScheduler.hasPending) {
      // The editor moves to another note, so a "too long" notice would stand
      // at the wrong note: it goes to the app-wide slot instead.
      _versionScheduler.dispose();
      await _takeVersionSnapshot(previousId, appWide: true);
    }
  }

  // ── Versions, images, marks and Textbausteine (ticket) ───────────────────

  /// Stores a version of [noteId] as it is in the database. The body is
  /// flushed first, so the snapshot is the text on screen. Returns `false`
  /// when the state repeats the newest version.
  Future<NoteVersionOutcome> _takeVersionSnapshot(
    String noteId, {
    bool appWide = false,
  }) async {
    await _autosave.flush();
    final note = await _actions.getNote(noteId);
    if (note == null) return NoteVersionOutcome.unchanged;
    final outcome = await _actions.snapshot(
      noteId,
      title: note.title,
      content: note.content,
    );
    // A text above the version limit gets no version; say so instead of
    // staying silent (#636). The notice belongs to this note.
    if (outcome == NoteVersionOutcome.tooLarge) {
      if (mounted && !appWide) {
        // Every idle pause while the text stays too long repeats this; the
        // notice is only said once, not read out again on each pause.
        final shown = _container.read(wpPageNoticeProvider(WpNoticePage.notes));
        if (shown?.id != 'notes-version-too-large' || shown?.area != noteId) {
          _notify(
            noteId,
            'version-too-large',
            L10n.of(context).notesVersionNoteTooLarge,
            tone: WpBannerTone.warning,
          );
        }
      } else if (_tooLargeNoticeText.isNotEmpty) {
        _raiseTooLargeAppWide();
      }
    }
    return outcome;
  }

  /// The "too long for versions" notice in the app-wide slot (the page was
  /// left, or the editor moved to another note), announced once: no page
  /// notice can carry it then. The container may already be gone when the
  /// app shuts down while the teardown snapshot runs; that is only logged.
  void _raiseTooLargeAppWide() {
    try {
      final errors = _container.read(wpAppErrorsProvider.notifier);
      final open = _container
          .read(wpAppErrorsProvider)
          .any((n) => n.id == 'notes-version-too-large');
      errors.add(
        WpPageNotice(
          id: 'notes-version-too-large',
          message: _tooLargeNoticeText,
          tone: WpBannerTone.warning,
        ),
      );
      final view = _announceView;
      if (!open && view != null) {
        announce(view, _tooLargeNoticeText, _announceDirection);
      }
    } catch (e, st) {
      _log.warning('Could not show the version notice after teardown', e, st);
    }
  }

  Future<void> _takeIdleSnapshot(String noteId) async {
    await _takeVersionSnapshot(noteId);
  }

  /// Writes the body for the autosave and reports it in the status line.
  /// A failure is rethrown: the writer keeps the text, backs it up, retries.
  Future<void> _persistNote(String noteId, String content) async {
    final generation = _editGeneration;
    try {
      await _actions.save(noteId, content);
    } catch (_) {
      if (mounted && noteId == _selectedNoteId) {
        _saveStatus.value = WpSaveStatus.failed;
      }
      rethrow;
    }
    if (mounted && noteId == _selectedNoteId && generation == _editGeneration) {
      _saveStatus.value = WpSaveStatus.saved;
    }
  }

  /// Ctrl/Cmd+S. Writes the body at once, says "Saved" as soon as it is
  /// stored, then takes a version; cancels the pending idle snapshot, since
  /// this one replaces it.
  Future<void> _saveVersionNow() async {
    final id = _selectedNoteId;
    if (id == null || !mounted) return;
    final l10n = L10n.of(context);
    _versionScheduler.dispose();
    final saved = await _autosave.flush();
    if (!mounted || _selectedNoteId != id) return;
    if (saved) _saveStatus.value = WpSaveStatus.saved;
    final outcome = await _takeVersionSnapshot(id);
    // A stored version shows in the version list, so only "nothing new" is
    // said, at the toolbar where the action was started.
    if (!mounted || _selectedNoteId != id) return;
    if (outcome == NoteVersionOutcome.stored) {
      // The version list shows it; screen readers still need to hear it.
      _announce(l10n.notesVersionSaved);
      return;
    }
    if (outcome == NoteVersionOutcome.unchanged) {
      _notify(
        id,
        'version-unchanged',
        l10n.notesVersionUnchanged,
        confirm: true,
      );
    }
  }

  /// Confirmations close themselves; errors and warnings stay until closed.
  static const _confirmationTime = Duration(seconds: 4);

  void _announce(String message) =>
      announce(View.of(context), message, Directionality.of(context));

  /// Enters or leaves focus mode (#669) for the open note; without one there
  /// is nothing to focus on. The caret goes back into the body either way, so
  /// writing simply continues.
  Future<void> _toggleWritingFocus() async {
    final notifier = ref.read(writingFocusProvider.notifier);
    final entering = !ref.read(writingFocusProvider);
    if (entering &&
        (_selectedNoteId == null ||
            ref.read(notesFilterProvider) == NotesFilter.trash)) {
      return;
    }
    final l10n = L10n.of(context);
    await notifier.toggle();
    if (!mounted) return;
    _announce(entering ? l10n.notesFocusModeEntered : l10n.notesFocusModeLeft);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedNoteId != null) _editorFocusNode.requestFocus();
    });
  }

  /// Puts [message] in the editor's notice slot for note [noteId]. It stays
  /// until it is closed or replaced, so an error cannot pass unread.
  void _notify(
    String noteId,
    String id,
    String message, {
    WpBannerTone tone = WpBannerTone.info,
    bool confirm = false,
  }) {
    showWpPageNotice(
      context,
      page: WpNoticePage.notes,
      notice: WpPageNotice(
        id: 'notes-$id',
        message: message,
        tone: tone,
        area: noteId,
        autoDismiss: confirm ? _confirmationTime : null,
      ),
    );
  }

  void _saveTitle(String noteId, String title) {
    final trimmed = title.trim();
    unawaited(_actions.saveTitle(noteId, trimmed.isEmpty ? null : trimmed));
  }

  /// Opens the version dialog. After a restore the editor shows the restored
  /// text: the controller is not bound to the database row.
  Future<void> _showVersions() async {
    final id = _selectedNoteId;
    if (id == null) return;
    await _autosave.flush();
    if (!mounted) return;
    final restored = await showNoteVersionsDialog(context: context, noteId: id);
    if (restored != true || !mounted) return;
    final fresh = await _actions.getNote(id);
    if (!mounted || fresh == null) return;
    if (_selectedNoteId == id) _showStored(fresh);
    // The editor shows the restored text; screen readers hear it.
    _announce(L10n.of(context).notesVersionRestored);
    setState(() => _titleRevision++);
  }

  void _markSelection() {
    var wrapped = false;
    _editorUndo.runCommand(
      () => wrapped = wrapSelectionInHighlight(_editorController),
    );
    if (wrapped) return;
    final id = _selectedNoteId;
    if (id == null) return;
    _notify(
      id,
      'mark-needs-selection',
      L10n.of(context).notesMarkNeedsSelection,
      tone: WpBannerTone.warning,
    );
  }

  Future<void> _addImage() async {
    final id = _selectedNoteId;
    if (id == null) return;
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: L10n.of(context).notesImageFilesLabel,
          extensions: _imageExtensions,
        ),
      ],
    );
    if (file == null || !mounted) return;
    await _addImageBytes(id, await file.readAsBytes());
  }

  /// The one way an image reaches a note (file picker, paste, drop): the
  /// store checks, cleans and limits it, and a refusal is shown in the editor.
  Future<void> _addImageBytes(String noteId, Uint8List bytes) async {
    final l10n = L10n.of(context);
    // Trashed notes show no images, so they take none either.
    final note = await ref.read(historyDatabaseProvider).getNote(noteId);
    if (note == null || note.deletedAt != null || !mounted) return;
    try {
      await _actions.addImage(noteId, bytes);
    } on NoteAssetLimitException catch (error) {
      if (!mounted) return;
      _notify(noteId, 'image-limit', switch (error.reason) {
        NoteAssetLimit.perNoteCount => l10n.notesImageLimitCount,
        NoteAssetLimit.perNoteBytes => l10n.notesImageLimitBytes,
        NoteAssetLimit.globalBytes => l10n.notesImageLimitTotal,
      }, tone: WpBannerTone.error);
    } on NoteImageRejectedException {
      if (!mounted) return;
      _notify(
        noteId,
        'image-rejected',
        l10n.notesImageRejected,
        tone: WpBannerTone.error,
      );
    }
  }

  /// Ctrl/Cmd+V with the editor focused: an image on the clipboard becomes an
  /// attachment. The key is not consumed; the text paste still runs and only
  /// finds text when the clipboard has some, so the two never both apply.
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? keys.isMetaPressed
        : keys.isControlPressed;
    if (modifier && _editorFocusNode.hasFocus) {
      unawaited(_pasteImageFromClipboard());
    }
    return false;
  }

  Future<void> _pasteImageFromClipboard() async {
    final id = _selectedNoteId;
    if (id == null) return;
    final bytes = await ref.read(noteClipboardImageReaderProvider)();
    if (bytes == null || !mounted) return;
    await _addImageBytes(id, bytes);
  }

  /// Image files dropped on the notes area go to the open note, in order.
  Future<void> _onDropDone(DropDoneDetails details) async {
    final id = _selectedNoteId;
    if (id == null || ref.read(historyContentHiddenProvider)) return;
    for (final item in details.files) {
      final name = item.name.toLowerCase();
      if (!_imageExtensions.any((ext) => name.endsWith('.$ext'))) continue;
      final bytes = await item.readAsBytes();
      if (!mounted) return;
      await _addImageBytes(id, bytes);
    }
  }

  /// Textbaustein from the selection, or the whole body when nothing is
  /// selected. The snippet keeps a link back to this note.
  Future<void> _createSnippet() async {
    final id = _selectedNoteId;
    if (id == null) return;
    final l10n = L10n.of(context);
    final selection = _editorController.selection;
    final text = selection.isValid && !selection.isCollapsed
        ? selection.textInside(_editorController.text)
        : _editorController.text;
    final body = text.trim();
    if (body.isEmpty) {
      _notify(
        id,
        'snippet-nothing',
        l10n.notesSnippetNothing,
        tone: WpBannerTone.warning,
      );
      return;
    }
    await _actions.createSnippetFromNote(
      noteId: id,
      title: deriveNoteTitle(body, maxLength: 60) ?? l10n.notesUntitled,
      body: body,
    );
    if (!mounted || _selectedNoteId != id) return;
    // The snippet lives on the Textbausteine page, so the result is not
    // visible here: say it where the action was started.
    _notify(id, 'snippet-created', l10n.notesSnippetCreated, confirm: true);
  }

  // ── Quick-note takeover (Ticket 21) ──────────────────────────────────────

  /// Applies a quick-note append to the *live* editor instead of letting the
  /// orchestrator write it to the database.
  ///
  /// Claims the append only when the target note is the one currently open —
  /// no separate "is this the quick note?" question is needed, because the
  /// orchestrator only ever calls this with the actual target id. With a
  /// different note open (or none), returning `false` sends the append down
  /// the direct-write path, which is right: the editor is showing something
  /// else and nothing on screen would be overwritten.
  ///
  /// Re-schedules the merged content on the autosave afterwards. Skipping the
  /// database write means the row is now behind the controller; the next
  /// [NoteAutosave.flush] — including the one the *next* quick-note run
  /// triggers through `quickNoteEditorFlush` — is what closes that gap. Drop
  /// the re-schedule and a second append reads the pre-append row and loses
  /// the first one.
  bool _quickNoteLiveOverride(String noteId, String newContent) {
    if (!mounted || _selectedNoteId != noteId) return false;
    _setEditorText(newContent);
    _autosave.schedule(noteId, newContent);
    _scrollEditorToEnd();
    return true;
  }

  /// Reads and immediately clears the deep-link target, then opens it.
  ///
  /// Clearing synchronously (before the `await` chain in
  /// [_openQuickNoteTarget]) is what lets a second append to the *same* note
  /// register at all — a `Notifier` set to its current value notifies nobody
  /// — and it is what keeps a later manual visit to this area from jumping to
  /// the note again.
  void _consumeEditorTarget() {
    if (!mounted) return;
    final targetId = ref.read(notesEditorTargetProvider);
    if (targetId == null) return;
    ref.read(notesEditorTargetProvider.notifier).set(null);
    unawaited(_openQuickNoteTarget(targetId));
  }

  /// Opens [targetId] in the editor, scrolled to the end.
  ///
  /// The already-open case only scrolls: [_quickNoteLiveOverride] has already
  /// put the appended text in the controller and deliberately left the
  /// database row behind, so re-reading the note here would overwrite the
  /// fresh text with the stale row.
  Future<void> _openQuickNoteTarget(String targetId) async {
    if (_selectedNoteId == targetId) {
      _scrollEditorToEnd();
      return;
    }
    await _leaveCurrentNote();
    if (!mounted) return;
    // Coming from the trash view, land in the normal notes view. Drops the
    // selection with it, exactly like _setFilter: carrying a trashed note
    // across the filter boundary would show a note that isn't in the list.
    if (ref.read(notesFilterProvider) == NotesFilter.trash) {
      setState(() => _selectedNoteId = null);
      _setEditorText('');
      ref.read(notesFilterProvider.notifier).set(NotesFilter.active);
    }
    // Read straight from the database, not from the streamed list: the note
    // may have been created by this very append and not have reached the
    // stream yet.
    final note = await _actions.getNote(targetId);
    if (!mounted || note == null) return;
    setState(() {
      _selectedNoteId = note.id;
      _focusedNoteId = note.id;
    });
    _showStored(note);
    _scrollEditorToEnd();
  }

  /// Asks the editor to reveal the end of the note, so the just-appended text
  /// is the part on screen. The field does the actual jump after the next
  /// layout — see [WpTextField.scrollToEnd].
  ///
  /// Fired twice on purpose: the editor may legitimately not be in the tree
  /// yet on the first attempt (the notes stream has not emitted the —
  /// possibly brand-new — note, so the split view renders no panel), and a
  /// field that mounts in between catches the second one. Jumping twice is a
  /// no-op; beyond that the request is dropped rather than retried forever.
  void _scrollEditorToEnd() {
    _scrollEditorToEndSignal.fire();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollEditorToEndSignal.fire();
    });
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
    // The list row holds only a preview: the open note reads its full text.
    final full = await _actions.getNote(note.id);
    if (!mounted || _selectedNoteId != note.id) return;
    _showStored(full ?? note);
    // The body field keeps its own scroll offset across a switch now that the
    // panel is updated in place rather than rebuilt (see WpCollectionSplit's
    // crossFadeDetail), so the new note would otherwise open at whatever
    // offset the previous one was left at. Reveal the end, which is where
    // [_setEditorText] has just put the caret.
    _scrollEditorToEnd();
  }

  /// Enter on a list row: opens [note] and puts the caret in its body. On the
  /// note that is already open it only moves focus, so the text and caret
  /// stay exactly as they were.
  Future<void> _openInEditor(Note note) async {
    if (note.id == _selectedNoteId) {
      _editorFocusNode.requestFocus();
      return;
    }
    await _selectNote(note);
    if (!mounted || _selectedNoteId != note.id) return;
    // The panel may only mount with this frame when nothing was open yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedNoteId == note.id) {
        _editorFocusNode.requestFocus();
      }
    });
  }

  /// Gives the list focus with its keyboard cursor on [noteId] (kept as is
  /// when null).
  void _focusList(String? noteId) {
    if (noteId != null && noteId != _focusedNoteId) {
      setState(() => _focusedNoteId = noteId);
    }
    _listFocusNode.requestFocus();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(notesSearchProvider.notifier).set('');
    setState(() {});
  }

  /// Keys in the search field, as on the other searchable pages: ↓ puts the
  /// list cursor on the first note, ↑ on the last, and hands focus to the
  /// list; Escape clears a running search, or on an empty one goes to the
  /// list. An empty list leaves the arrows to the field.
  KeyEventResult _handleSearchKeyEvent(KeyEvent event, List<Note> notes) {
    if (event is! KeyDownEvent || !_searchFocusNode.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (notes.isEmpty) return KeyEventResult.ignored;
      _focusList(
        (key == LogicalKeyboardKey.arrowDown ? notes.first : notes.last).id,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        noModifierPressed() &&
        !_searchController.value.composing.isValid) {
      if (_searchController.text.isNotEmpty) {
        _clearSearch();
      } else {
        _focusList(null);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Moves the list's virtual keyboard cursor by [delta] within [notes].
  void _moveFocus(int delta, List<Note> notes) {
    if (notes.isEmpty) return;
    final currentIdx = notes.indexWhere((n) => n.id == _focusedNoteId);
    final nextIdx = nextFocusIndex(currentIdx, delta, notes.length);
    setState(() => _focusedNoteId = notes[nextIdx].id);
  }

  Note? _focusedNote(List<Note> notes) {
    if (_focusedNoteId == null) return null;
    final idx = notes.indexWhere((n) => n.id == _focusedNoteId);
    return idx >= 0 ? notes[idx] : null;
  }

  // ── Multi-select (#655) ────────────────────────────────────────────────
  // Same pointer and keyboard model as the history list: Ctrl/Cmd+click
  // toggles, Shift+click and Shift+↑/↓ add a range in display order, Space
  // toggles the cursor row, Ctrl/Cmd+A selects all, Escape leaves. Every
  // change is announced, so a screen reader user hears the count.

  void _announceSelection() {
    if (!mounted) return;
    _announce(L10n.of(context).historyItemsSelected(_checkedIds.length));
  }

  void _toggleChecked(String id) {
    setState(() {
      _selecting = true;
      if (!_checkedIds.remove(id)) _checkedIds.add(id);
      _lastClickedId = id;
      _focusedNoteId = id;
    });
    _announceSelection();
  }

  /// Adds the rows between the range anchor and [toId] (in [notes], the
  /// display order) to the selection.
  void _checkRange(String toId, List<Note> notes) {
    final ids = notes.map((n) => n.id).toList();
    final to = ids.indexOf(toId);
    if (to < 0) return;
    var from = ids.indexOf(_lastClickedId ?? toId);
    if (from < 0) from = to;
    final start = from < to ? from : to;
    final end = from < to ? to : from;
    setState(() {
      _selecting = true;
      _checkedIds.addAll(ids.sublist(start, end + 1));
      _lastClickedId ??= toId;
      _focusedNoteId = toId;
    });
    _announceSelection();
  }

  void _selectAll(List<Note> notes) {
    if (notes.isEmpty) return;
    if (_selecting && notes.every((n) => _checkedIds.contains(n.id))) {
      _leaveSelection();
      return;
    }
    setState(() {
      _selecting = true;
      _checkedIds.addAll(notes.map((n) => n.id));
    });
    _announceSelection();
  }

  void _leaveSelection() {
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _checkedIds.clear();
      _lastClickedId = null;
    });
  }

  void _toggleSelecting(List<Note> notes) {
    if (_selecting) {
      _leaveSelection();
      return;
    }
    // Start with the open (or keyboard-focused) note ticked, so the mode
    // never opens on an empty selection the bar could not act on.
    final start = _selectedNoteId ?? _focusedNoteId;
    final startId = notes.any((n) => n.id == start)
        ? start
        : (notes.isEmpty ? null : notes.first.id);
    if (startId == null) return;
    _toggleChecked(startId);
    _listFocusNode.requestFocus();
  }

  /// A click on a row: modifiers select, a plain click opens the note —
  /// or, while selecting, ticks it.
  void _handleNoteTap(Note note, List<Note> notes) {
    final keys = HardwareKeyboard.instance;
    final isCtrl = keys.isControlPressed || keys.isMetaPressed;
    if (keys.isShiftPressed && !isCtrl) {
      _lastClickedId ??= _selectedNoteId;
      _checkRange(note.id, notes);
    } else if (isCtrl || _selecting) {
      _toggleChecked(note.id);
    } else {
      _lastClickedId = note.id;
      unawaited(_selectNote(note));
      return;
    }
    _listFocusNode.requestFocus();
  }

  /// The ticked notes still in [notes], in the order they were ticked.
  List<String> _checkedIn(List<Note> notes) {
    final present = {for (final n in notes) n.id};
    return [
      for (final id in _checkedIds)
        if (present.contains(id)) id,
    ];
  }

  /// Closes the editor when its note is among [ids] (it left the list).
  void _closeEditorIfIn(List<String> ids) {
    if (_selectedNoteId == null || !ids.contains(_selectedNoteId)) return;
    setState(() => _selectedNoteId = null);
    _setEditorText('');
  }

  void _showBulkUndo(String message, Future<void> Function() undo) {
    final l10n = L10n.of(context);
    showWpNotice(
      context,
      WpNotice(
        id: 'notes-bulk',
        kind: WpNoticeKind.undo,
        message: message,
        actionLabel: l10n.notesUndo,
        actionTestId: 'notes-bulk-undo',
        onAction: undo,
      ),
    );
  }

  void _bulkFailed(Object error) {
    _log.warning('Notes bulk action failed: $error');
    if (!mounted) return;
    showWpNotice(
      context,
      WpNotice(
        id: 'notes-bulk-failed',
        kind: WpNoticeKind.error,
        message: L10n.of(context).notesBulkFailed,
      ),
    );
  }

  /// Moves the selection to the trash after a count confirmation (#871).
  Future<void> _trashChecked(List<Note> notes) async {
    final ids = _checkedIn(notes);
    if (ids.isEmpty) return;
    await _autosave.flush();
    if (!mounted) return;
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.notesBulkTrashConfirm(ids.length),
      message: l10n.notesBulkTrashConfirmMessage,
      confirmLabel: l10n.notesBulkTrashAction,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final actions = _actions;
    try {
      final count = await actions.moveManyToTrash(ids);
      if (!mounted) return;
      _closeEditorIfIn(ids);
      _leaveSelection();
      _showBulkUndo(
        l10n.notesBulkMovedToTrash(count),
        () => actions.restoreMany(ids),
      );
    } catch (e) {
      _bulkFailed(e);
    }
  }

  /// Trash view: brings the selection back; undo puts it back in the trash.
  Future<void> _restoreChecked(List<Note> notes) async {
    final ids = _checkedIn(notes);
    if (ids.isEmpty) return;
    final l10n = L10n.of(context);
    final actions = _actions;
    try {
      final count = await actions.restoreMany(ids);
      if (!mounted) return;
      _closeEditorIfIn(ids);
      _leaveSelection();
      _showBulkUndo(
        l10n.notesBulkRestored(count),
        () => actions.moveManyToTrash(ids),
      );
    } catch (e) {
      _bulkFailed(e);
    }
  }

  /// Pins the selection, or unpins it when every ticked note is pinned.
  /// Undo flips back only the notes this action changed.
  Future<void> _pinChecked(List<Note> notes) async {
    final ids = _checkedIn(notes);
    if (ids.isEmpty) return;
    final idSet = ids.toSet();
    final checked = notes.where((n) => idSet.contains(n.id)).toList();
    final pin = !checked.every((n) => n.pinned);
    final changed = [
      for (final n in checked)
        if (n.pinned != pin) n.id,
    ];
    await _autosave.flush();
    if (!mounted) return;
    final l10n = L10n.of(context);
    final actions = _actions;
    try {
      await actions.setPinnedMany(changed, pinned: pin);
      if (!mounted) return;
      _leaveSelection();
      _showBulkUndo(
        pin
            ? l10n.notesBulkPinned(ids.length)
            : l10n.notesBulkUnpinned(ids.length),
        () => actions.setPinnedMany(changed, pinned: !pin),
      );
    } catch (e) {
      _bulkFailed(e);
    }
  }

  /// Asks for a tag and adds it to every ticked note. Undo removes it only
  /// from the notes that did not carry it before.
  Future<void> _tagChecked(List<Note> notes) async {
    final ids = _checkedIn(notes);
    if (ids.isEmpty) return;
    final name = await showNotesBulkTagDialog(context, count: ids.length);
    if (name == null || !mounted) return;
    await _autosave.flush();
    if (!mounted) return;
    final l10n = L10n.of(context);
    final actions = _actions;
    try {
      final result = await actions.addTagToMany(ids, name);
      if (!mounted || result == null) return;
      _leaveSelection();
      _showBulkUndo(
        l10n.notesBulkTagged(ids.length, name),
        () => actions.removeTagFromMany(result.added, result.tagId),
      );
    } catch (e) {
      _bulkFailed(e);
    }
  }

  /// Exports the selection into one file. The list rows hold only a preview
  /// (#639), so the full text is read first.
  Future<void> _exportChecked(List<Note> notes) async {
    final ids = _checkedIn(notes);
    if (ids.isEmpty) return;
    await _autosave.flush();
    final idSet = ids.toSet();
    final full = <Note>[];
    for (final note in notes.where((n) => idSet.contains(n.id))) {
      full.add(await _actions.getNote(note.id) ?? note);
    }
    if (!mounted) return;
    final tags =
        ref.read(allNoteTagsProvider).value ?? const <String, List<Tag>>{};
    _leaveSelection();
    // Fire-and-forget: the exporter reports in the page's notice area.
    unawaited(widget.exportManyFn(context, full, tags));
  }

  /// Merges the selection (in the order it was ticked) into one new note
  /// after a confirmation, then opens it. Undo deletes the merged note and
  /// restores the originals.
  Future<void> _mergeChecked(List<Note> notes) async {
    final ids = _checkedIn(notes);
    if (ids.length < 2) return;
    await _autosave.flush();
    if (!mounted) return;
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.notesMergeConfirm(ids.length),
      message: l10n.notesMergeConfirmMessage,
      confirmLabel: l10n.historyMerge,
      cancelLabel: l10n.actionCancel,
    );
    if (!confirmed || !mounted) return;
    final actions = _actions;
    try {
      final merged = await actions.merge(ids);
      if (!mounted || merged == null) return;
      _closeEditorIfIn(ids);
      _leaveSelection();
      setState(() {
        _selectedNoteId = merged.id;
        _focusedNoteId = merged.id;
        _pendingCreatedNote = merged;
      });
      _showStored(merged);
      _showBulkUndo(l10n.notesMerged(ids.length), () async {
        if (mounted && _selectedNoteId == merged.id) {
          setState(() => _selectedNoteId = null);
          _setEditorText('');
        }
        await actions.undoMerge(merged.id, ids);
      });
    } catch (e) {
      _bulkFailed(e);
    }
  }

  /// The selection bar above the list, or null outside multi-select.
  Widget? _buildSelectionBar(L10n l10n, List<Note> notes, bool isTrash) {
    if (!_selecting || _checkedIds.isEmpty) return null;
    final count = _checkedIn(notes).length;
    final checked = notes.where((n) => _checkedIds.contains(n.id));
    final allPinned = checked.isNotEmpty && checked.every((n) => n.pinned);
    return WpMultiSelectBar(
      idPrefix: 'notes-multiselect',
      isArchiveView: false,
      selectedCount: count,
      totalCount: notes.length,
      isTrashView: isTrash,
      onMerge: !isTrash && count >= 2
          ? () => unawaited(_mergeChecked(notes))
          : null,
      onExport: () => unawaited(_exportChecked(notes)),
      onTag: isTrash ? null : () => unawaited(_tagChecked(notes)),
      onFavourite: isTrash ? null : () => unawaited(_pinChecked(notes)),
      favouriteLabel: WpFavouriteStar.labelFor(l10n, isFavourite: allPinned),
      favouriteIcon: allPinned ? LucideIcons.starOff : LucideIcons.star,
      // The trash offers no bulk "delete forever": it could not be undone.
      onDelete: isTrash ? null : () => unawaited(_trashChecked(notes)),
      onRestore: isTrash ? () => unawaited(_restoreChecked(notes)) : null,
      onSelectAll: () => _selectAll(notes),
      onCancelSelection: _leaveSelection,
    );
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
    Note? currentNote,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Ctrl/Cmd+C copies the whole open or focused note, but only outside a
    // text field: inside one the key stays with the field so it copies the
    // selected text (ignored lets DefaultTextEditingShortcuts handle it).
    if (key == LogicalKeyboardKey.keyC && commandOnlyPressed()) {
      if (isTextFieldFocused()) return KeyEventResult.ignored;
      final note = currentNote ?? _focusedNote(notes);
      if (note == null) return KeyEventResult.ignored;
      unawaited(_copyNote(context, note));
      return KeyEventResult.handled;
    }
    // Escape in the note body hands focus back to the list, cursor on the
    // open note; the note stays open and a second Escape closes it. Only
    // from the body itself and never mid-composition: the tag field, find
    // and replace and menus handle their own Escape first, and an IME uses
    // Escape to cancel its candidate window.
    if (key == LogicalKeyboardKey.escape && _editorFocusNode.hasFocus) {
      if (!noModifierPressed() || _editorController.value.composing.isValid) {
        return KeyEventResult.ignored;
      }
      // In focus mode the first Escape leaves it and the caret stays put;
      // the next one goes back to the list as usual (#669).
      if (ref.read(writingFocusProvider)) {
        unawaited(_toggleWritingFocus());
        return KeyEventResult.handled;
      }
      _focusList(_selectedNoteId);
      return KeyEventResult.handled;
    }
    // Every other key is the list's only while the list itself holds focus:
    // not in a text field, and not on a focused toolbar or row button.
    if (!_listFocusNode.hasPrimaryFocus || isTextFieldFocused()) {
      return KeyEventResult.ignored;
    }

    // ↑/↓ and bare J/K: the shared list keyset (listStepFor). Shift+↑/↓
    // extends the selection over the rows it passes (#655).
    final step = listStepFor(key);
    if (step != null) {
      if (HardwareKeyboard.instance.isShiftPressed &&
          (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        final from = _focusedNoteId ?? _selectedNoteId;
        _lastClickedId ??= from;
        _moveFocus(step, notes);
        final to = _focusedNoteId;
        if (to != null) _checkRange(to, notes);
        return KeyEventResult.handled;
      }
      _moveFocus(step, notes);
      return KeyEventResult.handled;
    }
    // Space: tick or untick the row under the cursor.
    if (key == LogicalKeyboardKey.space && noModifierPressed()) {
      final note = _focusedNote(notes);
      if (note != null) _toggleChecked(note.id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final note = _focusedNote(notes);
      if (note != null) unawaited(_openInEditor(note));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_selecting && _checkedIds.isNotEmpty) {
        // The selection goes to the trash after a confirmation; in the trash
        // there is no bulk "delete forever" (it could not be undone).
        if (!isTrash) unawaited(_trashChecked(notes));
        return KeyEventResult.handled;
      }
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
    // view has no favourite star). Only a bare F: Ctrl/Cmd+F must bubble up
    // to the page-level CallbackShortcuts that focuses the search field.
    if (key == LogicalKeyboardKey.keyF && !isTrash && noModifierPressed()) {
      final note = _focusedNote(notes);
      if (note != null) _toggleFavorite(note);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_selecting) {
        _leaveSelection();
      } else if (_selectedNoteId != null) {
        _closeEditor();
      } else if (_focusedNoteId != null) {
        setState(() => _focusedNoteId = null);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _duplicateNote(Note note) async {
    await _leaveCurrentNote();
    final newNote = await _actions.duplicate(note.id);
    if (!mounted || newNote == null) return;
    confirmAtTrigger(context, target: 'note-${note.id}');
    setState(() {
      _selectedNoteId = newNote.id;
      _pendingCreatedNote = newNote;
    });
    _showStored(newNote);
  }

  /// "Go to paragraph" (#641): asks for a number, puts the caret at the start
  /// of that paragraph and says where it landed. In a long note the editor
  /// scrolls there through its height index.
  Future<void> _goToParagraph() async {
    if (_selectedNoteId == null) return;
    final l10n = L10n.of(context);
    final rows = NoteRows.of(_editorController.text);
    final count = rows.blockCount;
    final n = await showGoToParagraphDialog(context, count: count);
    if (n == null || !mounted) return;
    // The text may have changed while the dialog was open (a dictation).
    final now = NoteRows.of(_editorController.text);
    final index = n.clamp(1, now.blockCount);
    final offset = now.startOf(now.firstRowOfBlock(index - 1));
    _editorController.selection = TextSelection.collapsed(offset: offset);
    _editorFocusNode.requestFocus();
    final view = _announceView;
    if (view != null) {
      announce(
        view,
        l10n.notesGoToParagraphAnnounce(index, now.blockCount),
        _announceDirection,
      );
    }
  }

  /// "Split note" (#641): the text from the paragraph at the caret on moves
  /// to a new note, which opens. Offered by the editing-limit notice and the
  /// editor menu.
  Future<void> _splitNote() async {
    final id = _selectedNoteId;
    if (id == null) return;
    final l10n = L10n.of(context);
    final text = _editorController.text;
    final selection = _editorController.selection;
    final cut = splitOffset(
      text,
      caret: selection.isValid ? selection.start : null,
    );
    final view = _announceView;
    if (cut == null) {
      if (view != null) {
        announce(view, l10n.notesSplitNoteNothing, _announceDirection);
      }
      return;
    }
    final head = text.substring(0, cut).replaceFirst(RegExp(r'\n+$'), '');
    final tail = text.substring(cut);
    final Note created;
    try {
      // A pending save still holds the whole text; it must land before the
      // head replaces it, not after.
      await _autosave.flush();
      _setEditorText(head);
      await _actions.save(id, head);
      created = await _actions.create();
      await _actions.save(created.id, tail);
    } on Object catch (error, stack) {
      _log.warning('Split note failed: ${errorKind(error)}', null, stack);
      if (!mounted) return;
      showWpNotice(
        context,
        WpNotice(
          id: 'notes-split-error',
          kind: WpNoticeKind.error,
          message: l10n.notesCreateFailed,
        ),
      );
      return;
    }
    if (!mounted) return;
    await _leaveCurrentNote();
    if (!mounted) return;
    setState(() {
      _selectedNoteId = created.id;
      _pendingCreatedNote = created.copyWith(content: tail);
    });
    _setEditorText(tail);
    _editorController.selection = const TextSelection.collapsed(offset: 0);
    if (view != null) {
      announce(view, l10n.notesSplitNoteDone, _announceDirection);
    }
  }

  Future<void> _createNote() async {
    final Note note;
    try {
      await _autosave.flush();
      note = await _actions.create();
    } on Object catch (error, stack) {
      _log.warning('Create note failed: ${errorKind(error)}', null, stack);
      if (!mounted) return;
      // No note exists yet to carry the error, so it goes to the notice bar.
      showWpNotice(
        context,
        WpNotice(
          id: 'notes-create-error',
          kind: WpNoticeKind.error,
          message: L10n.of(context).notesCreateFailed,
        ),
      );
      return;
    }
    if (!mounted) return;
    // Only leave the selection and discard a blank predecessor after the
    // insert succeeds: a failed insert must leave the list unchanged.
    await _leaveCurrentNote();
    if (!mounted) return;
    if (ref.read(notesFilterProvider) == NotesFilter.trash) {
      ref.read(notesFilterProvider.notifier).set(NotesFilter.active);
    }
    setState(() {
      _selectedNoteId = note.id;
      _pendingCreatedNote = note;
    });
    _showStored(note);
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
    setState(() {
      _selectedNoteId = null;
      // A selection never carries over between the notes and the trash.
      _selecting = false;
      _checkedIds.clear();
      _lastClickedId = null;
    });
    _setEditorText('');
    ref.read(notesFilterProvider.notifier).set(filter);
  }

  /// Flushes first so a just-typed, not-yet-saved draft can't be overwritten
  /// by the stream re-emitting the stale pre-flush content after the toggle.
  Future<void> _toggleFavorite(Note note) async {
    await _autosave.flush();
    await _actions.togglePin(note.id, pinned: !note.pinned);
  }

  /// Makes [note] the quick note — the note the quick-note hotkey appends to.
  /// Exclusive: the write path drops whichever note held the mark before, so
  /// this never has to unmark anything first.
  ///
  /// Deliberately *not* a toggle, and deliberately not named like one: calling
  /// it on the note that already holds the mark would re-set the same value,
  /// which is why the UI does not offer the control there at all.
  ///
  /// Flushes first, same as the favourite action — the mark is a write on the
  /// same row, and the stream re-emitting pre-flush content afterwards would
  /// overwrite a just-typed draft.
  Future<void> _setQuickNote(Note note) async {
    await _autosave.flush();
    await _actions.markAsQuickNote(note.id);
  }

  /// Drops the quick-note mark without marking another note. Same flush rule:
  /// the marked note may well be the one open in the editor.
  Future<void> _clearQuickNote() async {
    await _autosave.flush();
    await _actions.clearQuickNoteMark();
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
    final actions = _actions;
    showWpNotice(
      context,
      WpNotice(
        id: 'notes-trashed',
        kind: WpNoticeKind.undo,
        message: l10n.notesMovedToTrash,
        actionLabel: l10n.notesUndo,
        onAction: () => actions.restore(note.id),
      ),
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
  /// selected range, with the word gap from [insertDictation]) — a genuine
  /// content edit, so it goes through the normal `_onEditorChanged`
  /// listener → autosave debounce, unlike `_setEditorText` (which suppresses
  /// autosave via `_syncingEditor` for programmatic note switches).
  void _insertVoiceTranscript(String transcript) {
    // Dictation is an undo unit of its own (#651).
    _editorUndo.runCommand(
      () => _editorController.value = insertDictation(
        _editorController.value,
        transcript,
      ),
    );
  }

  /// Exports the live editor text, not the (possibly stale, pre-debounce)
  /// DB-streamed [note] — same "controller, not DB" rule as copy (Ticket 03).
  void _exportNote(Note note, List<Tag> tags) {
    // Fire-and-forget: the exporter reports success/error in the editor's notice slot.
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
    return DropTarget(onDragDone: _onDropDone, child: _buildPage(context));
  }

  Widget _buildPage(BuildContext context) {
    final l10n = L10n.of(context);
    _tooLargeNoticeText = l10n.notesVersionNoteTooLarge;
    _announceView = View.of(context);
    _announceDirection = Directionality.of(context);
    // Deep link arriving while this area is already on screen (the normal
    // case from the second quick-note run on). The initState post-frame above
    // covers the other half: a target set before this page mounted.
    ref.listen<String?>(notesEditorTargetProvider, (_, target) {
      if (target == null) return;
      _consumeEditorTarget();
    });
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
    // What the arrow keys can reach: the favourites are skipped while their
    // section is folded (#830), as they are not in the list then.
    final navNotes =
        !isTrash &&
            !hasQuery &&
            (ref.watch(notesFavoritesCollapsedProvider).value ?? false)
        ? withoutFoldedFavorites(notes)
        : notes;
    Note? currentNote;
    if (_selectedNoteId != null) {
      final idx = notes.indexWhere((n) => n.id == _selectedNoteId);
      // The streamed row wins as soon as it exists; the just-created note
      // stands in only for the gap before the stream has it (see
      // [_pendingCreatedNote]).
      currentNote = idx >= 0
          ? notes[idx]
          : (_pendingCreatedNote?.id == _selectedNoteId
                ? _pendingCreatedNote
                : null);
    }

    if (ref.watch(historyContentHiddenProvider)) {
      return const NotesPinGate();
    }

    // Focus mode needs an open, editable note; losing it (closed, deleted,
    // moved to the trash) ends focus mode instead of leaving an empty frame.
    final writingFocus = ref.watch(writingFocusProvider);
    final focusMode = writingFocus && currentNote != null && !isTrash;
    if (writingFocus && !focusMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(writingFocusProvider.notifier).exit());
      });
    }

    // The page family's frame (`WpCollectionPage`, `internal-notes`):
    // toolbar above, list and editor below, landmarks `notes-page`,
    // `notes-toolbar`, `notes-list-area`, and Ctrl/Cmd+F to the search, the
    // same as on Recordings. The selection slot holds the multi-select bar
    // (#655, internal-notes §5.9).
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+N / Cmd+N: create a new note. Bound at page level so it works
        // from the search field as well as from the list and the editor.
        //
        // No isTextFieldFocused() guard, unlike Ctrl/Cmd+C. The guard was
        // there once and made the shortcut dead exactly when it is needed
        // most: the editor takes focus after every create, so from the second
        // note onwards Ctrl+N did nothing. Ctrl/Cmd+N is not a text-editing
        // binding on any of the three platforms (Flutter binds Ctrl+N to
        // "line down" only in its macOS Emacs set, and on macOS we send
        // Cmd+N). Snippets and Ersetzungen bind the same key through
        // WpSearchableListPage, equally unguarded.
        commandActivator(LogicalKeyboardKey.keyN): _createNote,
        // Cmd/Ctrl+Shift+Enter: focus mode (#669), from anywhere on the page.
        writingFocusActivator(): () => unawaited(_toggleWritingFocus()),
      },
      child: WpCollectionPage(
        screenId: 'notes',
        searchFocusNode: _searchFocusNode,
        selectionBar: _buildSelectionBar(l10n, notes, isTrash),
        // Focus mode swaps the search row for its own bar; the body below
        // keeps its place in the tree, so the editor is not rebuilt.
        toolbar: focusMode
            ? WritingFocusBar(
                paragraphFocus:
                    ref.watch(paragraphFocusProvider).value ?? false,
                onToggleParagraphFocus: () => unawaited(
                  ref.read(paragraphFocusProvider.notifier).toggle(),
                ),
                onExit: () => unawaited(_toggleWritingFocus()),
              )
            : Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) =>
                    _handleSearchKeyEvent(event, navNotes),
                child: NotesSearchBar(
                  onCreate: _createNote,
                  currentFilter: filter,
                  onFilterChanged: _setFilter,
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
                  selecting: _selecting,
                  onToggleSelecting: notes.isEmpty
                      ? null
                      : () => _toggleSelecting(navNotes),
                ),
              ),
        body: CallbackShortcuts(
          // Wraps every notesAsync state, so the selection shortcuts stay
          // reachable in the empty states too. Ctrl/Cmd+C and the bare keys
          // live in Focus.onKeyEvent below, which can return
          // KeyEventResult.ignored while a text field has focus.
          bindings: _buildListShortcuts(navNotes),
          child: Focus(
            focusNode: _listFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) => _handleListKeyEvent(
              node,
              event,
              navNotes,
              isTrash,
              currentNote,
            ),
            child: _buildNotesContent(
              notesAsync: notesAsync,
              isTrash: isTrash,
              hasQuery: hasQuery,
              query: query,
              l10n: l10n,
              tagsByNoteId: tagsByNoteId,
              currentNote: currentNote,
              selectedNoteTags: selectedNoteTags,
              activeStreamProvider: activeStreamProvider,
              navNotes: navNotes,
              focusMode: focusMode,
            ),
          ),
        ),
      ),
    );
  }

  /// Copies the full text of [note]: the live editor text for the open note,
  /// else read from the database (list rows only hold a preview, #639).
  Future<void> _copyNote(BuildContext context, Note note) async {
    final text = note.id == _selectedNoteId
        ? _editorController.text
        : (await _actions.getNote(note.id))?.content ?? note.content;
    if (!context.mounted) return;
    await copyWithFeedback(
      context,
      text: markdownToPlainText(text),
      target: 'note-${note.id}',
    );
  }

  /// Selection bindings of the list layer (#655): Ctrl/Cmd+A selects every
  /// note, Ctrl/Cmd+Shift+A clears the selection, Ctrl+M merges the ticked
  /// notes. Ctrl/Cmd+C lives in [_handleListKeyEvent].
  Map<ShortcutActivator, VoidCallback> _buildListShortcuts(List<Note> notes) {
    return <ShortcutActivator, VoidCallback>{
      commandActivator(LogicalKeyboardKey.keyA): () {
        if (isTextFieldFocused()) return;
        _selectAll(notes);
      },
      commandActivator(LogicalKeyboardKey.keyA, shift: true): () {
        if (isTextFieldFocused()) return;
        _leaveSelection();
      },
      // Ctrl+M on every platform, as in the history: Cmd+M minimises the
      // window on macOS.
      const SingleActivator(LogicalKeyboardKey.keyM, control: true): () {
        if (isTextFieldFocused()) return;
        if (ref.read(notesFilterProvider) == NotesFilter.trash) return;
        if (_selecting && _checkedIds.length >= 2) {
          unawaited(_mergeChecked(notes));
        }
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
    required L10n l10n,
    required Map<String, List<Tag>> tagsByNoteId,
    required Note? currentNote,
    required List<Tag> selectedNoteTags,
    required StreamProvider<List<Note>> activeStreamProvider,
    required List<Note> navNotes,
    bool focusMode = false,
  }) {
    return notesAsync.when(
      data: (notes) {
        if (notes.isEmpty) {
          if (hasQuery) {
            return WpEmptyState.searchNoMatches(
              key: const ValueKey('notes-search-empty'),
              query: query,
              testId: 'notes-search-clear',
              onClear: () {
                _searchController.clear();
                ref.read(notesSearchProvider.notifier).set('');
                setState(() {});
              },
            );
          }
          if (!isTrash && ref.watch(notesTagFilterProvider).isNotEmpty) {
            return WpEmptyState(
              key: const ValueKey('notes-tag-filter-empty'),
              icon: LucideIcons.tag,
              title: l10n.notesTagFilterEmptyTitle,
              hint: l10n.notesTagFilterEmptyHint,
              actionLabel: l10n.notesTagFilterReset,
              actionTestId: 'notes-tag-filter-reset',
              onAction: ref.read(notesTagFilterProvider.notifier).clear,
            );
          }
          // Per the WpEmptyState rule: the base state offers the area's
          // main action even though the header's "New note" button stays
          // visible — an empty list is where the user looks for it first,
          // and both carry the same label. The trash has nothing to start,
          // so its one way on is back to the notes.
          return WpEmptyState(
            icon: isTrash ? LucideIcons.trash2 : LucideIcons.stickyNote,
            title: isTrash ? l10n.notesTrashEmpty : l10n.notesEmptyTitle,
            hint: isTrash
                ? l10n.notesTrashEmptyHint(
                    ref
                            .watch(settingsProvider)
                            .value
                            ?.history
                            .historyAutoTrashDays ??
                        AppSettings.defaults.history.historyAutoTrashDays,
                  )
                : l10n.notesEmptyHint,
            actionLabel: isTrash ? l10n.historyShowAll : l10n.notesNewNote,
            actionTestId: isTrash ? 'notes-trash-show-all' : 'notes-empty-new',
            onAction: isTrash
                ? () => unawaited(_setFilter(NotesFilter.active))
                : _createNote,
          );
        }
        void addTag(String name) {
          if (currentNote != null) _addTag(currentNote, name);
        }

        void removeTag(String id) {
          if (currentNote != null) _removeTag(currentNote, id);
        }

        void exportCurrent() {
          if (currentNote != null) _exportNote(currentNote, selectedNoteTags);
        }

        final editorExtras = NoteEditorExtras(
          onSaveTitle: _saveTitle,
          onSaveVersionNow: () => unawaited(_saveVersionNow()),
          saveStatus: _saveStatus,
          onMarkSelection: _markSelection,
          onAddImage: () => unawaited(_addImage()),
          onShowVersions: () => unawaited(_showVersions()),
          onCreateSnippet: () => unawaited(_createSnippet()),
          onGoToParagraph: () => unawaited(_goToParagraph()),
          onSplitNote: () => unawaited(_splitNote()),
          onToggleFocusMode: isTrash
              ? null
              : () => unawaited(_toggleWritingFocus()),
          focusMode: focusMode,
          titleRevision: _titleRevision,
        );
        // Notes keep a flat list beside the editor: no view modes and no date
        // groups unless asked for; multi-select ticks rows (#655, internal-notes
        // §5.9).
        return WpCollectionSplit<Note>(
          selectedItem: currentNote,
          idOf: (note) => note.id,
          listBuilder: (context, selectedId) => NotesListView(
            notes: notes,
            tagsByNoteId: tagsByNoteId,
            isTrashView: isTrash,
            isSearch: hasQuery,
            selectedId: selectedId,
            focusedId: _focusedNoteId,
            selecting: _selecting,
            checkedIds: _checkedIds,
            onNoteTap: (note) => _handleNoteTap(note, navNotes),
            onCopy: (note) => unawaited(_copyNote(context, note)),
            onDuplicate: _duplicateNote,
            onFavoriteToggle: _toggleFavorite,
            onQuickNoteSet: _setQuickNote,
            onQuickNoteClear: _clearQuickNote,
            onRestore: _restoreNote,
            onDeleteForever: _deleteForever,
            onMoveToTrash: _moveToTrash,
          ),
          detailBuilder: (context, note) => NoteEditorPanel(
            note: note,
            tags: selectedNoteTags,
            controller: _editorController,
            focusNode: _editorFocusNode,
            scrollEditorToEnd: _scrollEditorToEndSignal,
            onClose: _closeEditor,
            onDuplicate: () => _duplicateNote(note),
            onToggleFavorite: () => _toggleFavorite(note),
            onQuickNoteSet: () => _setQuickNote(note),
            onQuickNoteClear: _clearQuickNote,
            onMoveToTrash: () => _moveToTrash(note),
            onRestore: () => _restoreNote(note),
            onDeleteForever: () => _deleteForever(note),
            onAddTag: addTag,
            onRemoveTag: removeTag,
            onExport: exportCurrent,
            onVoiceTranscript: _insertVoiceTranscript,
            extras: editorExtras,
          ),
          // The editor's controller and focus node are owned by this state
          // and outlive the panel, so the two panels a cross-fade keeps
          // mounted would both bind them (WpCollectionSplit.crossFadeDetail).
          crossFadeDetail: false,
          detailOnly: focusMode,
        );
      },
      loading: () => const WpListSkeleton(rowHeight: _notesSkeletonRowHeight),
      error: (e, _) => WpEmptyState(
        icon: LucideIcons.triangleAlert,
        title: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        actionTestId: 'notes-retry',
        onAction: () => ref.invalidate(activeStreamProvider),
      ),
    );
  }
}
