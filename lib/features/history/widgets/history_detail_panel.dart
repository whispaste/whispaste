import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/navigation/page_state.dart'
    show activePageProvider, notesEditorTargetProvider;
import '../../help/help_shortcuts.dart';
import '../../../core/recording/recording_helpers.dart'
    show displayNameForModel;
import '../../../core/text/markdown_plain_text.dart';
import '../../../core/text/text_undo.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../notes/data/note_autosave.dart';
import 'history_note_link.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/entry_version_rules.dart';
import 'package:whispaste/core/data/tag_suggestions.dart';

import '../../../core/config/command_shortcut.dart';
import '../../../core/config/settings_provider.dart';
import '../../../services/history/history_exporter.dart' as history_exporter;
import '../../../services/paste/auto_paste_blocklist.dart';
import '../../../services/pending_audio/kept_until_format.dart';
import '../../../services/pending_audio/pending_audio_providers.dart';
import '../../../services/pending_audio/pending_audio_queue.dart'
    show PendingRetryOutcome;
import '../../../services/recording_orchestrator.dart'
    show recordingOrchestratorProvider;
import '../../dictionary/term_store.dart';
import '../../../services/dictionary/contact_terms.dart';
import '../../dictionary/correction_term_offer.dart';
import '../../../services/replacements/correction_learning_service.dart';
import '../../../services/replacements/correction_signal.dart';
import '../../notes/data/notes_actions.dart';
import '../data/history_detail_provider.dart';
import '../data/history_title.dart';
import '../data/providers.dart' show historySearchProvider;
import 'smart_mode_undo_actions.dart';
import 'highlighted_text.dart';
import 'transcript_versions_dialog.dart';
import 'transcript_audio_section.dart';
import 'history_notes_section.dart';
import '../../../services/audio/encryption/recording_vault.dart';
import '../../../services/audio/retranscribe_entry.dart';
import '../../../services/dictation_text_steps.dart';
import '../../../services/drift_recording_store.dart';
import '../../../services/transcription/transcriber.dart';
import '../../../widgets/wp_editor_pane.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_head_actions.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/find_replace.dart';
import '../../../widgets/tag_input.dart';
import '../../../widgets/smart_mode_language_picker.dart';
import '../../../widgets/wp_save_status.dart';
import '../../../widgets/markdown_toolbar.dart' show WpMarkdownFormatting;
import '../../snippets/snippets_page.dart' show insertSnippetAtCursor;
import '../../../widgets/wp_text_editor.dart';
import '../../../widgets/wp_notice_bar.dart';
import '../../../widgets/wp_app_icon.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_markdown_view.dart';
import '../../../widgets/editor_text_view_scope.dart';
import '../../../widgets/wp_text_field.dart';
import 'tag_management_dialog.dart';
import '../../../core/utils/focus_helpers.dart';
import '../../../core/data/content_metadata_providers.dart';
import '../../../widgets/pending_retry_message.dart';
import '../../../widgets/wp_copy_feedback.dart';

import '../../../widgets/wp_page_notice.dart';
import 'history_write_failure.dart';
import '../../links/entry_link_picker.dart' show pickEntryLinkText;
import '../../links/entry_links_section.dart';
import '../../../core/text/entry_link.dart' show EntryLinkKind;
import '../../../services/smart_mode/editor_smart_action.dart';
import '../../smart_actions/editor_smart_action_flow.dart';
import '../../../widgets/wp_banner.dart';
import '../../../services/smart_mode/smart_mode_presets.dart'
    show SmartModePreset, SmartModeTargetLanguage, parseReprocessInstruction;
import '../../../services/smart_mode/smart_mode_retroactive_service.dart'
    show SmartModeRetroactiveFailureReason;

/// Signature of the export-entries seam used by [HistoryDetailPanel].
///
/// Defaults to the top-level [history_exporter.exportEntries]. Tests inject a
/// fake to assert that the overflow "Export…" menu item invokes the exporter
/// with the expected entry list, without spinning up real platform channels.
typedef HistoryDetailPanelExportFn =
    Future<void> Function(BuildContext context, List<HistoryEntry> entries);

/// Wraps [child] in the panel's standard [Tooltip] — but only when [message]
/// is non-null.
///
/// A tooltip that names an action is a promise. In the trash view neither the
/// title nor the transcript can be edited, so the promise has to disappear
/// rather than be blanked: `Tooltip(message: '')` still builds a tooltip, pops
/// an empty card on hover and leaves an empty `tooltip` on the semantics node.
/// One helper for both call sites so the two read-only affordances behave
/// identically.
Widget _tooltipIf(String? message, {required Widget child}) => message == null
    ? child
    : Tooltip(
        message: message,
        waitDuration: WpMotion.tooltipWait,
        child: child,
      );

// ---------------------------------------------------------------------------
// Detail panel — opens on entry selection (ChatGPT/Notion detail view)
// ---------------------------------------------------------------------------

final _correctionLog = AppLogger('HistoryDetailPanel');

class HistoryDetailPanel extends ConsumerStatefulWidget {
  const HistoryDetailPanel({
    super.key,
    required this.entry,
    required this.onClose,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    this.onDuplicate,
    this.onCopyMarkdown,
    this.isTrashView = false,
    this.isArchiveView = false,
    this.exportFn = history_exporter.exportEntries,
  });

  final HistoryEntry entry;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDuplicate;
  final VoidCallback? onCopyMarkdown;
  final bool isTrashView;
  final bool isArchiveView;

  /// Injection seam for the export flow.
  ///
  /// Defaults to the production [history_exporter.exportEntries]. Widget tests
  /// substitute a fake to assert the overflow "Export…" item invokes the
  /// exporter with `[entry]` without touching the filesystem or platform
  /// channels.
  final HistoryDetailPanelExportFn exportFn;

  @override
  ConsumerState<HistoryDetailPanel> createState() => _HistoryDetailPanelState();
}

class _HistoryDetailPanelState extends ConsumerState<HistoryDetailPanel> {
  String _tagSearchQuery = '';
  bool _isEditingTranscript = false;
  bool _showOriginal = false;
  late TextEditingController _transcriptController;

  /// Undo per entry: switching entries parks it, discarding forgets it (#651).
  late TextUndoController _transcriptUndo;

  /// Saves the open transcript edit after a short pause (#634), like the note
  /// editor. The text reaches the database a moment after the last key, so a
  /// crash, an entry switch or a mis-click cannot lose it.
  /// Goes through the one text write path (#676): a failed write leaves a
  /// local backup and an app-wide notice. No merge here: the stored
  /// transcript is the trimmed text, which is not a change made elsewhere.
  late final NoteAutosave _draftSave = NoteAutosave(
    onSave: _persistDraft,
    kind: 'recording',
  );

  /// What the open edit shows as saved: nothing yet, saving, saved or failed.
  final ValueNotifier<WpSaveStatus> _draftStatus = ValueNotifier(
    WpSaveStatus.idle,
  );

  /// The text the database holds for the open edit; skips writes that would
  /// change nothing and tells the final save whether a write is still due.
  String _lastPersisted = '';

  /// The next write of the open session starts a new version (#650).
  bool _versionBreakPending = false;

  /// Text last handed to [_draftSave]; a cursor move must not reschedule.
  String _lastScheduled = '';

  /// Set while the panel itself replaces the controller text.
  bool _syncingEditor = false;
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  final FocusNode _panelFocusNode = FocusNode();
  final FocusNode _editorFocusNode = FocusNode();

  /// What the reader has selected in the transcript's read view, for Ctrl/Cmd+C.
  String? _readSelection;
  final FocusNode _titleFocusNode = FocusNode();
  final GlobalKey<_TagSectionState> _tagSectionKey =
      GlobalKey<_TagSectionState>();
  final GlobalKey<HistoryNotesSectionState> _notesSectionKey =
      GlobalKey<HistoryNotesSectionState>();

  @override
  void initState() {
    super.initState();
    // Highlight-capable so the toolbar's find bar can tint its hits: a
    // TextField only paints a *selection* while focused, and while the user is
    // typing a query the focus is in the find field, not here.
    _transcriptController = WpFindHighlightController(
      text: widget.entry.content,
    );
    _transcriptController.addListener(_onTranscriptChanged);
    _transcriptUndo = TextUndoController(_transcriptController)
      ..open(widget.entry.id, () {});
    _editorFocusNode.addListener(_onEditorFocusChanged);
    _titleController = TextEditingController(text: widget.entry.title);
    // Auto-focus panel so its shortcuts AND ancestor list shortcuts both work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFocusNode.requestFocus();
    });
  }

  /// Saves the transcript edit that is open when the panel moves to another
  /// entry or goes away, so typed text is not lost (UIA-HIS-02). Deferred:
  /// both callers run during a rebuild or dispose, where a provider write is
  /// rejected.
  Future<void> Function(String)? _saveOpenEdit;

  String _savedBeforeEdit = '';

  /// Learns from the session's edit; prepared when the session opens, because
  /// the panel may be gone (no usable `ref`) when the session ends.
  void Function(String before, String after)? _learnFromEdit;

  /// Shows the write-failure notice without a context; prepared when the edit
  /// opens, because the panel may be gone when the final write fails.
  VoidCallback? _reportWriteFailure;

  void _flushOpenEdit() {
    final save = _saveOpenEdit;
    final report = _reportWriteFailure;
    final learn = _learnFromEdit;
    final before = _savedBeforeEdit;
    _saveOpenEdit = null;
    _learnFromEdit = null;
    // The pending pause timer is replaced by the write below.
    _resetDraftSave();
    final text = _transcriptController.text.trim();
    if (!_isEditingTranscript || save == null) return;
    // Moving to the next recording or leaving the page ends the session as
    // well as leaving the field does, so the correction is learned here too
    // (#1969). Before, only a blur inside the panel learned, and the
    // learning log stayed empty for the usual "fix it, click the next one".
    if (text != before) learn?.call(before, text);
    if (text == _lastPersisted) return;
    // The panel is going away or another entry opens, so there is no status
    // to show. A failing write is logged and reported as the page notice, so
    // the loss is not silent; it is never thrown into the zone.
    Future.microtask(() async {
      try {
        await save(text);
      } catch (e, st) {
        _correctionLog.warning('Final write of the transcript failed', e, st);
        try {
          report?.call();
        } catch (e2, st2) {
          _correctionLog.warning('Write-failure notice failed', e2, st2);
        }
      }
    });
  }

  void _onTranscriptChanged() {
    if (_syncingEditor) return;
    // Typing without a focus event first (paste by a test, dictation into
    // the field) opens the session too.
    _openSession();
    if (!_isEditingTranscript) return;
    final text = _transcriptController.text;
    if (text == _lastScheduled) return;
    setState(() => _lastScheduled = text);
    _draftSave.schedule(entry.id, text);
  }

  /// Focus opens the session; leaving the field saves at once (the pause
  /// timer is not waited for) and ends it.
  void _onEditorFocusChanged() {
    if (_editorFocusNode.hasFocus) {
      _openSession();
    } else {
      unawaited(_endSession());
    }
  }

  /// Drops the pending pause write; otherwise a later flush (focus left,
  /// next edit, app blur) would write that old text again.
  void _resetDraftSave() {
    unawaited(_draftSave.discardAll());
  }

  /// Writes the open edit; called by [_draftSave] after the pause and on
  /// every flush. A failed write keeps the editor and the text (UIA-HIS-05)
  /// and shows "not saved" until the next write works.
  Future<void> _persistDraft(String entryId, String raw) async {
    final save = _saveOpenEdit;
    final text = raw.trim();
    if (save == null) return;
    if (text == _lastPersisted) {
      // Nothing to write; a failed status no longer holds once the field is
      // back at what the database has.
      if (_draftStatus.value == WpSaveStatus.failed) {
        _draftStatus.value = WpSaveStatus.saved;
      }
      return;
    }
    _draftStatus.value = WpSaveStatus.saving;
    try {
      await save(text);
    } catch (e, st) {
      _correctionLog.warning('Autosave of the transcript failed', e, st);
      // The write may finish after the panel is gone; its notifier is then
      // disposed and must not be touched.
      if (!mounted) rethrow;
      // The text may have been typed back to what the database holds; then
      // nothing is unsaved and "not saved" would be wrong.
      _draftStatus.value = _transcriptController.text.trim() == _lastPersisted
          ? WpSaveStatus.saved
          : WpSaveStatus.failed;
      // The writer keeps the text, backs it up and retries.
      rethrow;
    }
    if (!mounted) return;
    _lastPersisted = text;
    _draftStatus.value = WpSaveStatus.saved;
  }

  @override
  void didUpdateWidget(covariant HistoryDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id) {
      _flushOpenEdit();
      _isEditingTranscript = false;
      _draftStatus.value = WpSaveStatus.idle;
      _syncingEditor = true;
      _transcriptUndo.open(
        widget.entry.id,
        () => _transcriptController.text = widget.entry.content,
      );
      _syncingEditor = false;
      _titleController.text = widget.entry.title;
      _isEditingTitle = false;
      // Collapsed by default for every entry (ticket 12) — a reader who
      // expanded it for one entry should not have it silently stay open
      // when the selection moves to the next one.
      _showOriginal = false;
    } else {
      // Sync fields that changed externally (Finding #3 — dual mutation path)
      if (!_isEditingTitle) {
        _titleController.text = widget.entry.title;
      }
      // Only a changed entry text is synced, and never while a session is
      // open: a stale entry after the session ended must not overwrite what
      // was just typed.
      if (!_isEditingTranscript && widget.entry.content != old.entry.content) {
        _syncingEditor = true;
        // A smart action or another window changed the text: an undo step,
        // so the next edit can still take it back.
        _transcriptUndo.runCommand(
          () => _transcriptController.text = widget.entry.content,
        );
        _syncingEditor = false;
      }
    }
  }

  @override
  void dispose() {
    _flushOpenEdit();
    _editorFocusNode.removeListener(_onEditorFocusChanged);
    _transcriptController.removeListener(_onTranscriptChanged);
    _transcriptUndo.dispose();
    _transcriptController.dispose();
    _draftStatus.dispose();
    _titleController.dispose();
    _panelFocusNode.dispose();
    _editorFocusNode.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  HistoryEntry get entry => widget.entry;
  VoidCallback get onClose => widget.onClose;
  VoidCallback get onCopy => widget.onCopy;
  VoidCallback get onPin => widget.onPin;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback get onArchive => widget.onArchive;
  VoidCallback get onRestore => widget.onRestore;
  VoidCallback? get onDuplicate => widget.onDuplicate;
  VoidCallback? get onCopyMarkdown => widget.onCopyMarkdown;
  bool get isTrashView => widget.isTrashView;
  bool get isArchiveView => widget.isArchiveView;

  /// Tag management left the tag row for the head's "…" menu (#1498), so
  /// the "Add tag" chip fits on the toolbar row; the suggestions reload after
  /// a rename or delete there.
  Future<void> _manageTags() async {
    final modified = await showTagManagementDialog(
      context: context,
      db: ref.read(historyDatabaseProvider),
    );
    if (modified) _tagSectionKey.currentState?.reloadSuggestions();
  }

  void _exportEntry() {
    // Fire-and-forget: the exporter manages its own progress and notices.
    widget.exportFn(context, [entry]);
  }

  /// Copies this entry's text into a new Notiz and offers to open it. The
  /// notice's action captures the notifiers, not [ref], so it still works
  /// after the detail panel has been closed.
  Future<void> _takeAsNote() async {
    final notes = ref.read(notesActionsProvider);
    final note = await notes.createFromEntry(entry.id, entry.content);
    if (!mounted) return;
    final l10n = L10n.of(context);
    final editorTarget = ref.read(notesEditorTargetProvider.notifier);
    final activePage = ref.read(activePageProvider.notifier);
    showWpPageNotice(
      context,
      page: WpNoticePage.history,
      notice: WpPageNotice(
        id: 'taken-as-note',
        message: l10n.historyTakenAsNote,
        tone: WpBannerTone.info,
        area: entry.id,
        action: (_) => WpButton(
          testId: 'history-notice-open-note',
          label: l10n.historyOpenNote,
          variant: WpButtonVariant.ghost,
          onPressed: () {
            editorTarget.set(note.id);
            activePage.setPage('notes');
          },
        ),
      ),
    );
  }

  /// After a saved correction, offers the corrected word for the dictionary
  /// in one step (issue #587). Nothing is offered for a rewrite or for words
  /// the dictionary already holds. The action captures the notifiers, not
  /// [ref], so it still works after the panel has been closed.
  void _offerDictionaryTerms(String before, String after) {
    final container = ProviderScope.containerOf(context, listen: false);
    final notices = ref.read(
      wpPageNoticeProvider(WpNoticePage.history).notifier,
    );
    final term = termToOfferAfterCorrection(
      before: before,
      after: after,
      vocabulary: ref.read(settingsProvider).value?.stt.customVocabulary ?? '',
    );
    if (term == null) return;
    final l10n = L10n.of(context);
    final entryId = entry.id;
    showWpPageNotice(
      context,
      page: 'history',
      notice: WpPageNotice(
        id: 'add-term',
        message: l10n.historyTermOffer(term),
        tone: WpBannerTone.info,
        area: entryId,
        action: (actionContext) => WpButton(
          testId: 'history-notice-add-term',
          label: l10n.historyTermOfferAction,
          variant: WpButtonVariant.ghost,
          onPressed: () async {
            // A term is a term entry in the dictionary (#1969).
            await addDictionaryTerms(container, [term]);
            if (!actionContext.mounted) return;
            // The confirmation stands in the notice bar (#1903); the offer
            // it answers leaves the entry.
            showWpConfirmation(
              actionContext,
              id: 'history-add-term',
              message: l10n.historyTermAdded,
            );
            notices.dismiss();
          },
        ),
      ),
    );
  }

  /// Feeds a manual transcript edit into the same correction-learning
  /// pipeline voice `correct:`/`korrektur:` commands use (ticket 01) --
  /// gated by the same settings toggle, and fire-and-forget like the other
  /// telemetry/persistence side effects in this panel: the edit itself is
  /// already saved by the time this runs, so nothing here should block or
  /// fail the save.
  void _recordManualEditCorrectionSignal(String before, String after) =>
      _learnerForSession()(before, after);

  /// The learning step of one edit session, with everything it needs read
  /// now, so it still works after the panel went away.
  void Function(String, String) _learnerForSession() {
    final correctionLearningEnabled =
        ref.read(
          settingsProvider.select(
            (s) => s.value?.behavior.correctionLearningEnabled,
          ),
        ) ??
        true;
    final service = ref.read(correctionLearningServiceProvider);
    final db = ref.read(historyDatabaseProvider);
    return (before, after) {
      if (!correctionLearningEnabled) return;
      unawaited(
        service
            .recordSignal(
              CorrectionSignal(
                sourceText: before,
                targetText: after,
                timestamp: DateTime.now(),
                source: CorrectionSignalSource.manualEdit,
              ),
              db,
            )
            // Learning is a side effect of a save that already succeeded: a
            // failure here is logged and must never surface as an unhandled
            // async error.
            .catchError((Object e, StackTrace st) {
              _correctionLog.warning(
                'Recording correction signal failed',
                e,
                st,
              );
              return 0;
            }),
      );
    };
  }

  /// Opens the editing session of this entry (#1498): the first focus in the
  /// field starts it, so there is no mode to switch and no button to press.
  /// One session is exactly one stored version: the first write of a session
  /// adds it, every autosave after that updates it. The session ends when the
  /// field loses focus, the selection moves to another entry or the panel
  /// goes away; the next focus starts a new one. Focus alone writes nothing.
  void _openSession() {
    if (_isEditingTranscript || isTrashView) return;
    // Captured now: a panel that is switching or going away has no usable
    // `ref` any more, and the detail notifier may already be disposed by
    // then. The database outlives both (UIA-HIS-02).
    final db = ref.read(historyDatabaseProvider);
    final entryId = entry.id;
    final titleEdited = entry.titleEdited;
    final startText = entry.content;
    var step = EditSessionStep.start;
    var baselined = false;
    _versionBreakPending = false;
    _saveOpenEdit = (text) async {
      final derived = deriveHistoryTitle(text);
      if (_versionBreakPending) {
        // A Smart Mode action replaces text typed in this session (#650):
        // its result is a version of its own, the typed one stays.
        _versionBreakPending = false;
        step = EditSessionStep.start;
      }
      if (step == EditSessionStep.start && !baselined) {
        baselined = true;
        // The text about to be overwritten stays restorable (#635): the
        // original transcript is a version of its own, written only when the
        // session really changes something.
        await db.recordEntryBaseline(entryId, startText);
      }
      await db.updateEntry(
        entryId,
        HistoryEntriesCompanion(
          content: Value(text),
          // Same title rule as `HistoryDetailNotifier.updateContent`.
          title: titleEdited || derived.isEmpty
              ? const Value.absent()
              : Value(derived),
        ),
      );
      final outcome = await recordTypedTranscriptVersion(
        db,
        entryId,
        text,
        session: step,
      );
      switch (outcome) {
        case EntryVersionOutcome.stored || EntryVersionOutcome.merged:
          step = EditSessionStep.continued;
        case EntryVersionOutcome.collapsed:
          // Typed back to the previous version: the next change is new.
          step = EditSessionStep.start;
        case EntryVersionOutcome.unchanged ||
            EntryVersionOutcome.tooLarge ||
            null:
          break;
      }
    };
    final notices = ref.read(
      wpPageNoticeProvider(WpNoticePage.history).notifier,
    );
    final failedNotice = historyWriteFailedNotice(
      L10n.of(context).historyWriteFailed,
      entryId: entryId,
    );
    _reportWriteFailure = () => notices.show(failedNotice);
    _learnFromEdit = _learnerForSession();
    _savedBeforeEdit = startText;
    _lastPersisted = startText;
    _lastScheduled = startText;
    _draftStatus.value = WpSaveStatus.idle;
    _isEditingTranscript = true;
  }

  /// Ends the session after the last write: the field lost focus. A failed
  /// write keeps the session (and the typed text) open until it works.
  Future<void> _endSession() async {
    if (!_isEditingTranscript) return;
    final saved = await _draftSave.flush();
    if (!mounted || !_isEditingTranscript || _editorFocusNode.hasFocus) return;
    if (!saved || _draftStatus.value == WpSaveStatus.failed) return;
    final before = _savedBeforeEdit;
    final after = _lastPersisted;
    _saveOpenEdit = null;
    _learnFromEdit = null;
    setState(() => _isEditingTranscript = false);
    if (after != before) {
      _recordManualEditCorrectionSignal(before, after);
      _offerDictionaryTerms(before, after);
    }
  }

  /// Ctrl/Cmd+S and Enter-submit: writes the pending text at once and says
  /// "Saved" as soon as it is stored (#1498).
  /// Ctrl/Cmd+Shift+P (#672): plays the kept audio from the sentence at the
  /// caret, or at the text selected in the reading view, else from the first
  /// sentence.
  Future<void> _playSentenceAtCaret() async {
    final text = _transcriptController.text;
    final selection = _transcriptController.selection;
    var offset = selection.isValid ? selection.baseOffset : -1;
    final read = _readSelection;
    if ((offset < 0 || !_editorFocusNode.hasFocus) &&
        read != null &&
        read.trim().isNotEmpty) {
      final at = text.indexOf(read.trim());
      if (at >= 0) offset = at;
    }
    await playTranscriptSentenceAt(
      context,
      ref,
      entryId: widget.entry.id,
      text: text,
      offset: offset < 0 ? 0 : offset,
    );
  }

  Future<void> _saveNow() async {
    if (!_isEditingTranscript) return;
    final saved = await _draftSave.flush();
    if (!mounted || !saved) return;
    if (_draftStatus.value != WpSaveStatus.failed) {
      _draftStatus.value = WpSaveStatus.saved;
    }
  }

  void _startTitleEdit() {
    if (isTrashView) return;
    _titleController.text = entry.title;
    setState(() => _isEditingTitle = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _titleFocusNode.requestFocus(),
    );
  }

  Future<void> _saveTitle() async {
    final newTitle = _titleController.text.trim();
    final entryId = entry.id;
    final changed = newTitle != entry.title;
    setState(() => _isEditingTitle = false);
    _panelFocusNode.requestFocus();
    if (!changed) return;
    try {
      await ref
          .read(historyDetailProvider(entryId).notifier)
          .updateTitle(newTitle);
    } catch (e) {
      if (mounted) showHistoryWriteFailed(context, entryId: entryId);
    }
  }

  /// Whether the original (pre-Smart-Mode/pre-Replacements) transcript
  /// (ticket 12) should be offered as a disclosure at all — only when one
  /// was captured *and* it actually differs from the final [content]. An
  /// entry where Smart Mode/Replacements made no change, or a pre-ticket-12
  /// entry with no captured original, shows nothing extra.
  bool get _hasOriginalDiff {
    final original = entry.originalTranscript;
    return original != null && original != entry.content;
  }

  void _toggleShowOriginal() => setState(() => _showOriginal = !_showOriginal);

  /// Smart Mode on the selection or the paragraph at the caret (#650). The
  /// text typed so far is written first and stays a version; the result is
  /// the next one.
  void _runSmartAction(EditorSmartAction action) => unawaited(
    runEditorSmartAction(
      context,
      ref,
      controller: _transcriptController,
      action: action,
      lockKey: entry.id,
      languageCode: entry.language.isNotEmpty ? entry.language : null,
      beforeApply: () async {
        if (!_isEditingTranscript) return;
        await _draftSave.flush();
        _versionBreakPending = true;
      },
    ),
  );

  /// Opens the Textbaustein chooser and inserts the pick at the caret of the
  /// transcript being edited (#664).
  void _insertSnippet() => unawaited(
    insertSnippetAtCursor(
      context: context,
      ref: ref,
      controller: _transcriptController,
      focusNode: _editorFocusNode,
    ),
  );

  /// Date and time for the head. The year only when it is not the current
  /// one: the head is narrow, and "12 Nov 2026, 13:17" cost the title most
  /// of a 520 px window (#1498).
  String _headTimestamp(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final at = entry.timestamp;
    final date = at.year == DateTime.now().year
        ? DateFormat.MMMd(locale)
        : DateFormat.yMMMd(locale);
    return date.add_Hm().format(at);
  }

  String get _durationLabel {
    final secs = entry.durationSec.round();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
  }

  /// Copies whichever version (raw or edited) is currently displayed —
  /// additive to the header's Copy button, which always copies raw content
  /// (ticket 05: that existing, tested behavior is deliberately left alone).
  void _copyDisplayedVersion(String displayedContent) {
    unawaited(
      copyWithFeedback(
        context,
        // Plain text by default (#644); the overflow menu offers Markdown.
        text: markdownToPlainText(displayedContent),
        target: 'history-${widget.entry.id}',
        category: 'history',
      ),
    );
  }

  /// Name of a mode as the user picked it, e.g. "Translate (English)" (#680).
  String _modeLabel(
    L10n l10n,
    SmartModePreset preset,
    SmartModeTargetLanguage? targetLanguage,
  ) {
    final name = switch (preset) {
      SmartModePreset.cleanup => l10n.smartModePresetCleanup,
      SmartModePreset.concise => l10n.smartModePresetConcise,
      SmartModePreset.translate => l10n.smartModePresetTranslate,
      SmartModePreset.off => preset.name,
    };
    if (targetLanguage == null) return name;
    return '$name (${smartModeTargetLanguageLabel(l10n, targetLanguage)})';
  }

  /// [_modeLabel] of a stored reprocessing instruction; null when unknown.
  String? _instructionLabel(L10n l10n, String? instruction) {
    final parsed = parseReprocessInstruction(instruction);
    if (parsed == null) return null;
    return _modeLabel(l10n, parsed.preset, parsed.targetLanguage);
  }

  void _announce(String message) {
    if (!mounted) return;
    announce(View.of(context), message, Directionality.of(context));
  }

  /// Undoes the shown reprocessing result; the previous one, or the original,
  /// is shown again (#680).
  Future<void> _undoReprocess() async {
    final l10n = L10n.of(context);
    final undone = await ref
        .read(historyDetailProvider(entry.id).notifier)
        .undoReprocess();
    if (!mounted) return;
    if (undone) {
      _announce(l10n.historyReprocessUndone);
    } else {
      showWpPageNotice(
        context,
        page: WpNoticePage.history,
        notice: WpPageNotice(
          id: 'smart-mode-busy',
          message: l10n.smartModeBusyRetry,
          tone: WpBannerTone.info,
          area: entry.id,
        ),
      );
    }
  }

  Future<void> _applySmartModePreset(SmartModePreset preset) async {
    SmartModeTargetLanguage? targetLanguage;
    if (preset == SmartModePreset.translate) {
      targetLanguage = await showWpSmartModeTargetLanguagePicker(context);
      if (targetLanguage == null) return;
    }
    if (!mounted) return;
    final l10n = L10n.of(context);
    final mode = _modeLabel(l10n, preset, targetLanguage);
    // Keyboard and screen-reader users hear that the run started (#680).
    _announce(l10n.historyReprocessRunning(mode));
    final result = await ref
        .read(historyDetailProvider(entry.id).notifier)
        .applyPreset(preset, targetLanguage: targetLanguage);
    if (!mounted) return;
    switch (result) {
      case HistoryPresetApplicationSuccess():
        // The result is a version of its own; the notice offers its undo and
        // is announced (#680).
        showWpNotice(
          context,
          WpNotice(
            id: 'history-reprocess-done',
            kind: WpNoticeKind.undo,
            message: l10n.historyReprocessDone(mode),
            actionLabel: l10n.smartModeUndoAction,
            actionTestId: 'history-reprocess-undo-notice',
            onAction: () => unawaited(_undoReprocess()),
          ),
        );
      case HistoryPresetApplicationBusy():
        showWpPageNotice(
          context,
          page: WpNoticePage.history,
          notice: WpPageNotice(
            id: 'smart-mode-busy',
            message: l10n.smartModeBusyRetry,
            tone: WpBannerTone.info,
            area: entry.id,
          ),
        );
      case HistoryPresetApplicationFailure(:final reason):
        final message = switch (reason) {
          SmartModeRetroactiveFailureReason.modelMissing =>
            l10n.historySmartModeFailedModelMissing,
          SmartModeRetroactiveFailureReason.timeout =>
            l10n.historySmartModeFailedTimeout,
          SmartModeRetroactiveFailureReason.checkTimedOut =>
            l10n.smartModeCheckTimedOut,
          SmartModeRetroactiveFailureReason.engineError ||
          SmartModeRetroactiveFailureReason.blankResult ||
          SmartModeRetroactiveFailureReason.factsChanged =>
            l10n.historySmartModeFailedGeneric,
        };
        showWpPageNotice(
          context,
          page: WpNoticePage.history,
          notice: WpPageNotice(
            id: 'smart-mode-failed',
            message: message,
            area: entry.id,
          ),
        );
    }
  }

  void _showShortcutHelp() {
    final l10n = L10n.of(context);
    showWpDialog<void>(
      context: context,
      title: l10n.historyShortcutHelp,
      content: const _ShortcutHelpContent(),
      actions: [
        WpDialogAction(
          label: l10n.historyClose,
          testId: 'shortcut-help-close',
          role: WpDialogActionRole.primary,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final detailAsync = ref.watch(historyDetailProvider(entry.id));
    final detailState = detailAsync.asData?.value;
    final tags = detailState?.tags ?? [];
    final hasEditedVersion = detailState?.hasEditedVersion ?? false;
    final viewingEditedVersion = detailState?.viewingEditedVersion ?? false;
    final applyingPreset = detailState?.applyingPreset ?? false;
    final displayedContent = detailState?.displayedContent ?? entry.content;
    final reprocessMode = _instructionLabel(
      l10n,
      detailState?.reprocessInstruction,
    );
    final undoReprocessTooltip = reprocessMode == null || applyingPreset
        ? null
        : l10n.historyReprocessUndo(reprocessMode);
    final metadata = _isEditingTranscript
        ? ref.watch(contentMetadataPreviewProvider(_lastScheduled)).value
        : ref
              .watch(
                contentMetadataProvider((
                  kind: viewingEditedVersion
                      ? ContentKind.recordingEdited
                      : ContentKind.recording,
                  id: entry.id,
                )),
              )
              .value;

    final zone = _DetailTranscriptZone(
      tags: _TagSection(
        key: _tagSectionKey,
        entryId: entry.id,
        tags: tags,
        isTrashView: isTrashView,
        content: entry.content,
        searchQuery: _tagSearchQuery,
        onSearchChanged: (q) => setState(() => _tagSearchQuery = q),
      ),
      entry: entry,
      isTrashView: isTrashView,
      transcriptController: _transcriptController,
      onInsertSnippet: _insertSnippet,
      onSmartAction: isTrashView ? null : _runSmartAction,
      editorFocusNode: _editorFocusNode,
      onReadSelectionChanged: (text) => _readSelection = text,
      // From the background metadata index, so a very
      // long transcript is not recounted on every build.
      wordCount: metadata?.wordCount,
      onSaveTranscript: _saveNow,
      draftStatus: _draftStatus,
      displayedContent: displayedContent,
      hasEditedVersion: hasEditedVersion,
      viewingEditedVersion: viewingEditedVersion,
      onToggleViewingEdited: hasEditedVersion
          ? () => ref
                .read(historyDetailProvider(entry.id).notifier)
                .setViewingEditedVersion(!viewingEditedVersion)
          : null,
      onCopyDisplayed: () => _copyDisplayedVersion(displayedContent),
      undoReprocessTooltip: undoReprocessTooltip,
      onUndoReprocess: undoReprocessTooltip == null
          ? null
          : () => unawaited(_undoReprocess()),
      onShowVersions: () => unawaited(
        showTranscriptVersionsDialog(context: context, entryId: entry.id),
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isEditingTitle) {
            setState(() => _isEditingTitle = false);
            _panelFocusNode.requestFocus();
          } else {
            onClose();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (!isTextFieldFocused()) _startTitleEdit();
        },
        commandActivator(LogicalKeyboardKey.keyS): () {
          if (_isEditingTitle) {
            _saveTitle();
          } else {
            unawaited(_saveNow());
          }
        },
        commandActivator(LogicalKeyboardKey.enter): () {
          if (_isEditingTitle) {
            _saveTitle();
          } else {
            unawaited(_saveNow());
          }
        },
        // Plays the recording from the sentence at the caret (#672).
        commandActivator(LogicalKeyboardKey.keyP, shift: true): () {
          if (!isTrashView) unawaited(_playSentenceAtCaret());
        },
        // Formatting keys and Ctrl/Cmd+S inside the transcript come from the
        // shared editor block (WpTextEditor), bound around its field only.
        // Shortcut help overlay: "?" on every layout, German Shift+ß too.
        ...shortcutOverviewKeys(() {
          if (!isTextFieldFocused()) _showShortcutHelp();
        }),
      },
      child: Focus(
        focusNode: _panelFocusNode,
        // Ctrl/Cmd+C lives here, not in the CallbackShortcuts above: that would
        // consume the key and keep the title and transcript fields from
        // copying their own selection (ignored lets the field handle it).
        // In the read view a selected passage is copied as selected (#638);
        // with nothing selected the key keeps copying the whole entry.
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.keyC ||
              !commandOnlyPressed() ||
              _editorFocusNode.hasFocus ||
              _isEditingTitle) {
            return KeyEventResult.ignored;
          }
          final selected = _readSelection;
          if (selected != null && selected.isNotEmpty) {
            unawaited(Clipboard.setData(ClipboardData(text: selected)));
          } else {
            onCopy();
          }
          return KeyEventResult.handled;
        },
        child: WpEditorPane(
          head: WpCopyAnchor(
            target: 'history-${widget.entry.id}',
            child: _DetailPanelHeader(
              entry: entry,
              isTrashView: isTrashView,
              isEditingTitle: _isEditingTitle,
              titleController: _titleController,
              titleFocusNode: _titleFocusNode,
              timestamp: _headTimestamp(context),
              onStartTitleEdit: _startTitleEdit,
              onSaveTitle: _saveTitle,
              onCopy: onCopy,
              onPin: onPin,
              onDelete: onDelete,
              onArchive: onArchive,
              onRestore: onRestore,
              onDuplicate: onDuplicate,
              onCopyMarkdown: onCopyMarkdown,
              onExport: _exportEntry,
              onTakeAsNote: _takeAsNote,
              onManageTags: isTrashView ? null : _manageTags,
              onClose: onClose,
              applyingPreset: applyingPreset,
              onApplyPreset: isTrashView ? null : _applySmartModePreset,
            ),
          ),
          // No rule between header and content: the gap already separates
          // them. Insets, scroll and the right edge on the search bar's line
          // come from the shared pane (#1498), as in notes and snippets.
          notices: [
            WpPageNoticeSlot(page: WpNoticePage.history, area: entry.id),
            SmartModeUndoRow(entryId: entry.id, fallback: entry),
            if (!isTrashView) HistoryNoteLink(entryId: entry.id),
            // Back after a jump, links to and from this recording (#660).
            // Links are written into the raw transcript, the editable one.
            if (!isTrashView)
              EntryLinksSection(
                key: ValueKey('history-detail-links-${entry.id}'),
                entry: (kind: ContentKind.recording, id: entry.id),
                testId: 'history-detail',
              ),
          ],
          // ── Context zone: metadata ──
          meta: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailMetaChips(entry: entry, durationLabel: _durationLabel),
              _KeptUntilNotice(entryId: entry.id),
            ],
          ),
          // The recording scrolls as one: chips, transcript, edit bar,
          // original and annotations (#1498). The edit bar, the original
          // and the annotations are the pane's extras below the editor.
          bodyMode: WpEditorPaneBody.scroll,
          // ── Content zone: transcript ──
          // The tags share the editor's toolbar row where the width allows,
          // as in notes (#1498), so the head stays a thin band above the
          // text.
          editor: zone,
          extras: [
            if (!isTrashView) zone.editBar(),
            // ── Transcript and audio (#672) ── sentences with their place in
            // the kept recording; renders nothing without audio.
            if (!isTrashView)
              TranscriptAudioSection(
                entryId: entry.id,
                text: _transcriptController,
              ),
            // ── Original transcript disclosure (ticket 12) ──
            // Final text stays the primary view; the original is
            // secondary/collapsed by default rather than shown in
            // side-by-side raw/final panes — this is WhisPaste's own
            // "final text first" stance.
            if (_hasOriginalDiff)
              _OriginalTranscriptDisclosure(
                originalText: entry.originalTranscript!,
                expanded: _showOriginal,
                onToggle: _toggleShowOriginal,
              ),
            // ── Notes section ──
            HistoryNotesSection(key: _notesSectionKey, entryId: entry.id),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shortcut help — body of the keyboard cheat sheet dialog
// ---------------------------------------------------------------------------

/// Content of the shortcut help [showWpDialog]: two labelled groups of
/// key-cap rows. Colors come from the theme (surface, border, radius and
/// title typography are the dialog's) — this body only owns the key caps.
class _ShortcutHelpContent extends StatelessWidget {
  const _ShortcutHelpContent();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final groupStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.historyShortcutGeneral, style: groupStyle),
        const SizedBox(height: WpSpacing.xs),
        _ShortcutRow(keyLabel: 'Esc', description: l10n.historyShortcutClose),
        const SizedBox(height: WpSpacing.sm),
        Text(l10n.historyShortcutListGroup, style: groupStyle),
        const SizedBox(height: WpSpacing.xs),
        _ShortcutRow(
          keyLabel: '↑ ↓ / J K',
          description: l10n.historyShortcutMoveFocus,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel(enterKey, l10n: l10n),
          description: l10n.historyShortcutOpenEntry,
        ),
        _ShortcutRow(
          keyLabel: l10n.shortcutKeyEnter,
          description: l10n.historyShortcutCopyEntry,
        ),
        _ShortcutRow(
          keyLabel: l10n.shortcutKeyDelete,
          description: l10n.historyShortcutDeleteEntry,
        ),
        _ShortcutRow(keyLabel: 'F', description: l10n.historyShortcutPin),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('A', l10n: l10n),
          description: l10n.historyShortcutSelectAll,
        ),
        _ShortcutRow(
          keyLabel: l10n.shortcutKeyEscape,
          description: l10n.historyShortcutClearSelection,
        ),
        const SizedBox(height: WpSpacing.sm),
        Text(l10n.historyShortcutEditing, style: groupStyle),
        const SizedBox(height: WpSpacing.xs),
        _ShortcutRow(
          keyLabel: 'F2',
          description: l10n.historyShortcutEditTitle,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('E', l10n: l10n),
          description: l10n.historyShortcutToggleEdit,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('S', l10n: l10n),
          description: l10n.historyShortcutSave,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel(enterKey, l10n: l10n),
          description: l10n.historyShortcutSave,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('B', l10n: l10n),
          description: l10n.historyShortcutBold,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('I', l10n: l10n),
          description: l10n.historyShortcutItalic,
        ),
        _ShortcutRow(
          keyLabel: WpMarkdownFormatting.insertSnippetShortcutLabel(l10n),
          description: l10n.historyShortcutInsertSnippet,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('C', l10n: l10n),
          description: l10n.historyShortcutCopy,
        ),
        _ShortcutRow(
          keyLabel: commandShortcutLabel('P', shift: true, l10n: l10n),
          description: l10n.historyShortcutPlaySentence,
        ),
        _ShortcutRow(
          keyLabel: l10n.shortcutKeyEscape,
          description: l10n.historyShortcutDiscardEdit,
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keyLabel, required this.description});

  final String keyLabel;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // Hairline step: the key-cap chip hugs its caption text;
            // xxs would double the height of this deliberately tight cap.
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: WpSpacing.xxxs,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: WpRadius.borderSm,
            ),
            child: Text(
              keyLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                letterSpacing: 0,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(child: Text(description, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel header (type glyph + title/edit + timestamp + action buttons)
// ---------------------------------------------------------------------------

/// Square extent of one [HistoryDetailAction]: its icon plus padding on each
/// side. The header measures against it to decide whether its actions still
class _DetailPanelHeader extends StatelessWidget {
  const _DetailPanelHeader({
    required this.entry,
    required this.isTrashView,
    required this.isEditingTitle,
    required this.titleController,
    required this.titleFocusNode,
    required this.timestamp,
    required this.onStartTitleEdit,
    required this.onSaveTitle,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.onDuplicate,
    required this.onCopyMarkdown,
    required this.onExport,
    required this.onTakeAsNote,
    required this.onManageTags,
    required this.onClose,
    required this.applyingPreset,
    required this.onApplyPreset,
  });

  final HistoryEntry entry;
  final bool isTrashView;
  final bool isEditingTitle;
  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final String timestamp;
  final VoidCallback onStartTitleEdit;
  final VoidCallback onSaveTitle;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDuplicate;
  final VoidCallback? onCopyMarkdown;
  final VoidCallback onExport;
  final VoidCallback onTakeAsNote;

  /// Opens tag management, `null` in the trash view.
  final VoidCallback? onManageTags;
  final VoidCallback onClose;

  /// Whether a retroactive Smart Mode preset application is in flight for
  /// this entry (ticket 05) — disables the overflow menu's preset items.
  final bool applyingPreset;

  /// Applies a Smart Mode preset retroactively to this entry, or `null` in
  /// the trash view where the action is not offered.
  final void Function(SmartModePreset preset)? onApplyPreset;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textPrimary = WpColors.textPrimary;
    final textSecondary = WpColors.textSecondary;
    // One head row in every editor (#1498): the title, read or edited in
    // the heading style, then the timestamp inline and muted. A second line
    // for the date made this head taller than the note's and the snippet's.
    final titleWidget = isEditingTitle
        ? WpTextField(
            controller: titleController,
            focusNode: titleFocusNode,
            variant: WpTextFieldVariant.heading,
            hintText: l10n.historyTitlePlaceholder,
            onSubmitted: (_) => onSaveTitle(),
            onEditingComplete: onSaveTitle,
          )
        : Semantics(
            button: !isTrashView,
            onTapHint: isTrashView ? null : l10n.historyEditTitle,
            onTap: isTrashView ? null : onStartTitleEdit,
            child: _tooltipIf(
              isTrashView ? null : l10n.historyEditTitle,
              child: WpFocusRing(
                focusNode: titleFocusNode,
                radius: WpRadius.sm,
                child: InkWell(
                  onDoubleTap: isTrashView ? null : onStartTitleEdit,
                  focusNode: titleFocusNode,
                  borderRadius: WpRadius.borderSm,
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  mouseCursor: isTrashView
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  // The heading field's own inset, so the text does not
                  // jump sideways when edit mode opens.
                  child: Padding(
                    padding: WpTextField.headingContentPadding,
                    child: HighlightedText(
                      text: entry.title.isNotEmpty
                          ? entry.title
                          : l10n.historyUntitled,
                      // Read view and edit view of the same title: one
                      // style, so opening edit mode never resizes the text.
                      style: WpTextField.styleFor(
                        WpTextFieldVariant.heading,
                        color: textPrimary,
                      ),
                      // One line with an ellipsis, as in notes and snippets;
                      // the full title is one click away in the edit field.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          );

    // Actions stay on the title's row, as before.
    // Domain actions first, then "…", then close: the order of all three
    // editors, each in an equal slot (#1498).
    final domainActions = <Widget>[
      HistoryDetailAction(
        testId: 'history-detail-copy',
        icon: LucideIcons.copy,
        tooltip:
            '${l10n.historyCopyText} '
            // Cmd on macOS, as the copy key itself (#1845).
            '(${commandShortcutLabel('C', l10n: l10n)})',
        onTap: onCopy,
      ),
      if (isTrashView) ...[
        HistoryDetailAction(
          testId: 'history-detail-restore',
          icon: LucideIcons.undo2,
          tooltip: l10n.historyRestore,
          onTap: onRestore,
        ),
        HistoryDetailAction(
          testId: 'history-detail-delete-forever',
          icon: LucideIcons.trash2,
          tooltip: l10n.historyDeleteForever,
          onTap: onDelete,
          isDestructive: true,
        ),
      ] else
        WpFavouriteStar.head(
          testId: 'history-detail-pin',
          isFavourite: entry.pinned,
          onToggle: onPin,
          shortcut: 'F',
        ),
      if (!isTrashView)
        HistoryDetailAction(
          testId: 'history-detail-take-as-note',
          key: const ValueKey('history-detail-take-as-note'),
          icon: LucideIcons.stickyNote,
          tooltip: l10n.historyTakeAsNote,
          onTap: onTakeAsNote,
        ),
    ];
    final actionsRow = WpHeadActions(
      actions: domainActions,
      menu: _DetailOverflowMenu(
        entry: entry,
        textSecondary: textSecondary,
        onCopyMarkdown: onCopyMarkdown,
        onDuplicate: onDuplicate,
        onExport: onExport,
        onArchive: onArchive,
        onDelete: onDelete,
        onManageTags: onManageTags,
        applyingPreset: applyingPreset,
        onApplyPreset: onApplyPreset,
        isTrashView: isTrashView,
      ),
      close: HistoryDetailAction(
        testId: 'history-detail-close',
        icon: LucideIcons.x,
        tooltip: '${l10n.historyClose} (Esc)',
        onTap: onClose,
      ),
    );

    // No leading type glyph (#1498): no editor head carries a leading mark,
    // so the title starts on the same edge in all three editors.
    return WpEditorHead(
      title: titleWidget,
      // The time keeps its width, the title shortens first (#1498).
      meta: timestamp,
      actions: actionsRow,
    );
  }
}

// ---------------------------------------------------------------------------
// Overflow popup menu (secondary header actions)
// ---------------------------------------------------------------------------

class _DetailOverflowMenu extends ConsumerWidget {
  const _DetailOverflowMenu({
    required this.entry,
    required this.textSecondary,
    required this.onCopyMarkdown,
    required this.onDuplicate,
    required this.onExport,
    required this.onArchive,
    required this.onDelete,
    required this.onManageTags,
    required this.applyingPreset,
    required this.onApplyPreset,
    required this.isTrashView,
  });

  final HistoryEntry entry;
  final Color textSecondary;
  final VoidCallback? onCopyMarkdown;
  final VoidCallback? onDuplicate;
  final VoidCallback onExport;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onManageTags;
  final bool applyingPreset;
  final void Function(SmartModePreset preset)? onApplyPreset;
  final bool isTrashView;

  /// Transcribes the retained audio again and replaces the text only after
  /// the user has seen the new one and agreed (#586).
  Future<void> _retranscribe(
    BuildContext context,
    WidgetRef ref,
    L10n l10n,
  ) async {
    // One run at a time: a second tap on the menu item would start a second
    // transcription on the same engine.
    if (_retranscribing.contains(entry.id)) return;
    _retranscribing.add(entry.id);
    try {
      await _retranscribeOnce(context, ref, l10n);
    } finally {
      _retranscribing.remove(entry.id);
    }
  }

  static final Set<String> _retranscribing = {};

  Future<void> _retranscribeOnce(
    BuildContext context,
    WidgetRef ref,
    L10n l10n,
  ) async {
    final db = ref.read(historyDatabaseProvider);
    // Bound to this entry: it shows in the entry's detail, not in a toast
    // (#455), and the result below replaces it.
    showWpPageNotice(
      context,
      page: WpNoticePage.history,
      notice: WpPageNotice(
        id: 'retranscribe-busy',
        message: l10n.historyRetranscribeBusy,
        tone: WpBannerTone.info,
        area: entry.id,
      ),
    );
    final result = await transcribeEntryAudio(
      db: db,
      transcriber: ref.read(transcriberProvider),
      vault: ref.read(recordingVaultProvider),
      entryId: entry.id,
    );
    if (!context.mounted) return;
    // The work is done: the busy line goes, an error below takes its place.
    final notices = ref.read(
      wpPageNoticeProvider(WpNoticePage.history).notifier,
    );
    if (ref.read(wpPageNoticeProvider(WpNoticePage.history))?.id ==
        'retranscribe-busy') {
      notices.dismiss();
    }
    final raw = result.text;
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    // The same text steps as a dictation: filler words, spoken punctuation,
    // written forms and the dictionary.
    final text = raw == null
        ? null
        : await DictationTextSteps.fromSettings(settings).apply(
            raw,
            languageCode: entry.language.isNotEmpty
                ? entry.language
                : settings.sttLanguageCode,
            applyReplacements: ref
                .read(recordingStoreProvider)
                .applyReplacements,
            terms: localVocabularyTerms(
              settings.stt.customVocabulary,
              ref.read(contactTermsProvider),
            ),
          );
    if (!context.mounted) return;
    if (text == null) {
      _showRetranscribeFailed(context, l10n);
      return;
    }
    final replace = await showWpConfirmDialog(
      context: context,
      title: l10n.historyRetranscribeConfirmTitle,
      message: l10n.historyRetranscribeConfirmMessage(text),
      confirmLabel: l10n.historyRetranscribeReplace,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!replace) return;
    try {
      await applyRetranscript(db, entry.id, text, previousText: entry.content);
    } on Object catch (e, st) {
      _correctionLog.error('Replacing the retranscribed text failed', e, st);
      if (!context.mounted) return;
      _showRetranscribeFailed(context, l10n);
    }
  }

  /// The failure stays at the entry until it is closed; the message names
  /// the cause and the next step.
  void _showRetranscribeFailed(BuildContext context, L10n l10n) {
    showWpPageNotice(
      context,
      page: WpNoticePage.history,
      notice: WpPageNotice(
        id: 'retranscribe-failed',
        message: l10n.historyRetranscribeFailed,
        area: entry.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // "Turn off auto-paste in this app": offered when the recording's target
    // app is known and not on the block list yet (see internal-notes §2.7).
    final target = entry.targetApp?.trim();
    final blocklist =
        ref.watch(settingsProvider).value?.behavior.autoPasteBlocklist ?? '';
    final offerAutoPasteOff =
        target != null &&
        target.isNotEmpty &&
        !autoPasteBlocklistContains(blocklist, target);
    final hasAudio = ref.watch(entryHasAudioProvider(entry.id)).value ?? false;
    return WpHeadMenuButton<String>(
      key: const ValueKey('history-detail-menu'),
      testId: 'history-detail-menu',
      tooltip: l10n.historyMoreActions,
      onSelected: (value) {
        switch (value) {
          case 'markdown':
            onCopyMarkdown?.call();
          case 'duplicate':
            onDuplicate?.call();
          case 'preset_cleanup':
            onApplyPreset?.call(SmartModePreset.cleanup);
          case 'preset_concise':
            onApplyPreset?.call(SmartModePreset.concise);
          case 'preset_translate':
            onApplyPreset?.call(SmartModePreset.translate);
          case 'export':
            onExport();
          case 'manage_tags':
            onManageTags?.call();
          case 'auto_paste_off':
            if (target == null) break;
            ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWith(
                    autoPasteBlocklist: autoPasteBlocklistWith(
                      s.behavior.autoPasteBlocklist,
                      target,
                    ),
                  ),
                );
          case 'retranscribe':
            unawaited(_retranscribe(context, ref, l10n));
          case 'archive':
            onArchive();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => [
        if (onCopyMarkdown != null)
          PopupMenuItem(
            value: 'markdown',
            child: WpMenuRow(
              icon: LucideIcons.fileText,
              label: l10n.historyCopyAsMarkdown,
            ),
          ),
        if (onDuplicate != null)
          PopupMenuItem(
            value: 'duplicate',
            child: WpMenuRow(
              icon: LucideIcons.files,
              label: l10n.historyDuplicate,
            ),
          ),
        if (onApplyPreset != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text(
              l10n.historyApplySmartModePreset,
              style: TextStyle(
                fontSize: WpTypography.caption,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ),
          PopupMenuItem(
            value: 'preset_cleanup',
            enabled: !applyingPreset,
            child: WpMenuRow(
              icon: LucideIcons.sparkles,
              label: l10n.smartModePresetCleanup,
            ),
          ),
          PopupMenuItem(
            value: 'preset_concise',
            enabled: !applyingPreset,
            child: WpMenuRow(
              icon: LucideIcons.minimize2,
              label: l10n.smartModePresetConcise,
            ),
          ),
          PopupMenuItem(
            value: 'preset_translate',
            enabled: !applyingPreset,
            child: WpMenuRow(
              icon: LucideIcons.languages,
              label: l10n.smartModePresetTranslate,
            ),
          ),
        ],
        if (!isTrashView)
          PopupMenuItem(
            key: const ValueKey('history-detail-menu-retranscribe'),
            value: 'retranscribe',
            enabled: hasAudio,
            child: WpMenuRow(
              icon: LucideIcons.refreshCw,
              label: hasAudio
                  ? l10n.historyRetranscribe
                  : l10n.historyRetranscribeNoAudio,
            ),
          ),
        if (onManageTags != null)
          PopupMenuItem(
            key: const ValueKey('history-detail-manage-tags'),
            value: 'manage_tags',
            child: Semantics(
              identifier: 'history-detail-manage-tags',
              child: WpMenuRow(
                icon: LucideIcons.tags,
                label: l10n.historyManageTags,
              ),
            ),
          ),
        PopupMenuItem(
          key: const ValueKey('history-detail-menu-export'),
          value: 'export',
          child: WpMenuRow(
            icon: LucideIcons.download,
            label: l10n.historyExportAction,
          ),
        ),
        if (offerAutoPasteOff)
          PopupMenuItem(
            key: const ValueKey('history-detail-menu-auto-paste-off'),
            value: 'auto_paste_off',
            child: WpMenuRow(
              icon: LucideIcons.ban,
              label: l10n.historyAutoPasteOffForApp,
            ),
          ),
        if (!isTrashView)
          PopupMenuItem(
            value: 'archive',
            child: WpMenuRow(
              icon: entry.archived
                  ? LucideIcons.archiveRestore
                  : LucideIcons.archive,
              label: entry.archived
                  ? l10n.historyUnarchive
                  : l10n.historyArchive,
            ),
          ),
        // Destructive entry is set apart by a divider so it is never read as
        // one more equal-weight sibling of Archivieren (UX-012). Deleting is
        // a soft delete with an undo toast outside the trash view.
        if (!isTrashView) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            key: const ValueKey('history-detail-menu-delete'),
            value: 'delete',
            child: WpMenuRow(
              icon: LucideIcons.trash2,
              label: l10n.actionDelete,
              isDestructive: true,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Meta chips row (duration, language, storage, model)
// ---------------------------------------------------------------------------

class _DetailMetaChips extends ConsumerWidget {
  const _DetailMetaChips({required this.entry, required this.durationLabel});

  final HistoryEntry entry;
  final String durationLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref
        .watch(
          contentMetadataProvider((kind: ContentKind.recording, id: entry.id)),
        )
        .value
        ?.characterCount;
    final l10n = L10n.of(context);
    return Wrap(
      spacing: WpSpacing.sm,
      runSpacing: WpSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MetaChip(icon: LucideIcons.clock, label: durationLabel),
        if (entry.language.isNotEmpty)
          _MetaChip(
            icon: LucideIcons.globe,
            label: entry.language.toUpperCase(),
          ),
        _MetaChip(
          icon: entry.isLocal ? LucideIcons.hardDrive : LucideIcons.cloud,
          label: entry.isLocal ? l10n.historyOnDevice : l10n.statusCloud,
        ),
        if (entry.model.isNotEmpty) ...[
          () {
            final modelName = displayNameForModel(entry.model, l10n);
            return Tooltip(
              message: '${l10n.historyModel}: $modelName',
              child: _MetaChip(
                icon: LucideIcons.cpu,
                label: modelName.length > 25
                    ? '${modelName.substring(0, 25)}…'
                    : modelName,
              ),
            );
          }(),
        ],
        // Character count (ticket 12) — "at a glance" length, so a reader
        // does not have to open/scroll the transcript just to gauge it.
        // Counts the final [HistoryEntry.content], the same source of
        // truth the raw/edited toggle above treats as "raw".
        // Left out while the index has not counted yet: a bare dash there
        // read as a stray line (#1498).
        if (count != null)
          _MetaChip(
            icon: LucideIcons.textCursorInput,
            label: l10n.historyCharacterCount(count),
          ),
        // Target app (ticket 12) — which app/window this dictation was
        // pasted into. `null` for quick notes, template fields, Linux, or
        // any entry where no target was captured (including every
        // pre-ticket-12 entry) — the chip simply does not render then.
        if (entry.targetApp != null && entry.targetApp!.isNotEmpty)
          Tooltip(
            message: l10n.historyPastedInto(entry.targetApp!),
            child: _TargetAppChip(identifier: entry.targetApp!),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript zone (view/edit mode + edit status bar)
// ---------------------------------------------------------------------------

class _DetailTranscriptZone extends StatelessWidget {
  const _DetailTranscriptZone({
    required this.entry,
    required this.isTrashView,
    required this.transcriptController,
    required this.editorFocusNode,
    required this.onInsertSnippet,
    this.onSmartAction,
    required this.onReadSelectionChanged,
    required this.wordCount,
    required this.onSaveTranscript,
    required this.draftStatus,
    required this.displayedContent,
    required this.hasEditedVersion,
    required this.viewingEditedVersion,
    required this.onToggleViewingEdited,
    required this.onCopyDisplayed,
    required this.undoReprocessTooltip,
    required this.onUndoReprocess,
    required this.onShowVersions,
    required this.tags,
  });

  final HistoryEntry entry;
  final bool isTrashView;

  /// The entry's tags, in the editor's toolbar row.
  final Widget tags;

  final TextEditingController transcriptController;
  final FocusNode editorFocusNode;
  final VoidCallback onInsertSnippet;

  /// Smart Mode on the selection (#650); null in the trash.
  final ValueChanged<EditorSmartAction>? onSmartAction;

  /// Reports what is selected in the read view (null when nothing is).
  final ValueChanged<String?> onReadSelectionChanged;

  /// Word count from the metadata index; null while it is still being built.
  final int? wordCount;
  final VoidCallback onSaveTranscript;
  final ValueListenable<WpSaveStatus> draftStatus;

  /// The text to show in read mode — raw or edited, per
  /// [viewingEditedVersion] (ticket 05). Edit mode always edits the raw
  /// [HistoryEntry.content], never this.
  final String displayedContent;

  /// Whether this entry has a Smart-Mode-edited version to toggle to.
  final bool hasEditedVersion;

  /// Whether [displayedContent] is currently the edited version.
  final bool viewingEditedVersion;

  /// Flips [viewingEditedVersion]. `null` when [hasEditedVersion] is `false`
  /// — there is nothing to toggle to.
  final VoidCallback? onToggleViewingEdited;

  /// Copies [displayedContent] — the version currently on screen, which may
  /// differ from the header's Copy button (always raw).
  final VoidCallback onCopyDisplayed;

  /// Name of the undo for the shown reprocessing result, with its mode
  /// (#680); null when the shown edited version is no stored result.
  final String? undoReprocessTooltip;

  /// Undoes the shown reprocessing result (#680); null without one.
  final VoidCallback? onUndoReprocess;

  /// Opens the version list of the transcript (#635).
  final VoidCallback onShowVersions;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textPrimary = WpColors.textPrimary;
    final viewKind = viewingEditedVersion
        ? ContentKind.recordingEdited
        : ContentKind.recording;

    // No reading-width cap any more (#1498): the surface spans the pane
    // between the page insets, as in Notes and Snippets, so all three
    // editors share one left and one right edge.
    return
    // The shared editor block (#638). Its toolbar stands above the
    // transcript in reading and in editing alike — disabled while
    // reading — so opening the editor moves no control. Editing starts
    // from the edit pill below or Ctrl/Cmd+E; a click into the text no
    // longer does, because the read view is now selectable and a click
    // there places a selection.
    WpTextEditor(
      testId: 'history-editor',
      controller: transcriptController,
      focusNode: editorFocusNode,
      variant: WpTextFieldVariant.passage,
      // Written directly; only the stored edited version and the trash
      // are read-only.
      editable: !isTrashView && !viewingEditedVersion,
      saveStatus: draftStatus,
      onSave: onSaveTranscript,
      // Caret and place per entry and per version (#678);
      // the edited version is read-only and keeps its own place.
      viewMemory: (kind: viewKind, id: entry.id),
      semanticsLabel: l10n.historyEditTranscript,
      autofocus: true,
      onSubmitted: (_) => onSaveTranscript(),
      onInsertSnippet: onInsertSnippet,
      // `[[` opens the link chooser (#660).
      onPickLink: isTrashView
          ? null
          : () => pickEntryLinkText(
              context,
              except: (kind: EntryLinkKind.recording, id: entry.id),
            ),
      onSmartAction: onSmartAction,
      // Nothing in the trash can be edited: no bar, no mode to switch.
      showToolbar: !isTrashView,
      toolbarTrailing: tags,
      readText: displayedContent,
      externalWordCount: true,
      wordCount: wordCount,
      readView: Semantics(
        container: true,
        identifier: 'history-transcript-read',
        child: SelectionArea(
          onSelectionChanged: (content) =>
              onReadSelectionChanged(content?.plainText),
          // Same *material* and metrics as the edit field (Ticket 16):
          // the field's own resting box from the same spec, with its
          // 12 dp inset, so the paragraph neither changes substance nor
          // shifts sideways when editing starts. No hover lift any more:
          // the lift said "click to write here", and the click now
          // selects.
          child: WpTextFieldSurface(
            variant: WpTextFieldVariant.passage,
            liftsOnHover: false,
            // Rendered Markdown with tickable checklists (#643). An
            // empty transcript renders a zero-width space, so it shows
            // the same empty card the edit view draws.
            child: Consumer(
              builder: (context, ref, _) => WpMarkdownView(
                testId: 'history-transcript',
                source: displayedContent,
                // The editors' line spacing (#648).
                style: WpEditorText.styleOf(
                  context,
                  WpTextField.styleFor(
                    WpTextFieldVariant.passage,
                    color: textPrimary,
                  ),
                ),
                highlight: ref.watch(historySearchProvider),
                // Only the raw transcript is ticked: the AI version is
                // a stored result, and nothing in the trash changes.
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The edit bar under the transcript (edit, versions, raw/edited, copy).
  /// It is one of the pane's extras, so the pane sets its gap (#1498); the
  /// trash view shows none.
  Widget editBar() => _TranscriptEditBar(
    hasEditedVersion: hasEditedVersion,
    viewingEditedVersion: viewingEditedVersion,
    onToggleViewingEdited: onToggleViewingEdited,
    onCopyDisplayed: onCopyDisplayed,
    undoReprocessTooltip: undoReprocessTooltip,
    onUndoReprocess: onUndoReprocess,
    onShowVersions: onShowVersions,
  );
}

// ---------------------------------------------------------------------------
// Original transcript disclosure (ticket 12) — collapsed by default, shown
// only when the entry has a captured original that differs from the final
// text. Deliberately a secondary, collapsible affordance rather than a
// side-by-side pane: the final text is always the primary view here.
// ---------------------------------------------------------------------------

class _OriginalTranscriptDisclosure extends StatelessWidget {
  const _OriginalTranscriptDisclosure({
    required this.originalText,
    required this.expanded,
    required this.onToggle,
  });

  final String originalText;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final textPrimary = WpColors.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: expanded
              ? l10n.historyHideOriginalTranscript
              : l10n.historyShowOriginalTranscript,
          child: InkWell(
            onTap: onToggle,
            borderRadius: WpRadius.borderSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: WpIconSize.xs,
                    color: textMuted,
                  ),
                  const SizedBox(width: WpSpacing.xxs),
                  Text(
                    expanded
                        ? l10n.historyHideOriginalTranscript
                        : l10n.historyShowOriginalTranscript,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: WpSpacing.xxs),
            padding: const EdgeInsets.all(WpSpacing.sm),
            decoration: BoxDecoration(
              color: WpColors.surfaceMutedFill,
              borderRadius: WpRadius.borderMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.historyOriginalTranscriptLabel,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxs),
                SelectableText(
                  originalText,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
// ---------------------------------------------------------------------------
// The bar under the
// transcript (versions, raw/edited, copy). There is no edit or save button:
// the text is written directly and saved by itself (#1498).
// ---------------------------------------------------------------------------

class _TranscriptEditBar extends StatelessWidget {
  const _TranscriptEditBar({
    required this.hasEditedVersion,
    required this.viewingEditedVersion,
    required this.onToggleViewingEdited,
    required this.onCopyDisplayed,
    required this.undoReprocessTooltip,
    required this.onUndoReprocess,
    required this.onShowVersions,
  });

  final bool hasEditedVersion;
  final bool viewingEditedVersion;
  final VoidCallback? onToggleViewingEdited;
  final VoidCallback onCopyDisplayed;
  final String? undoReprocessTooltip;
  final VoidCallback? onUndoReprocess;
  final VoidCallback onShowVersions;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      spacing: WpSpacing.xs,
      runSpacing: WpSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasEditedVersion) ...[
          _RawEditedToggle(
            viewingEditedVersion: viewingEditedVersion,
            onToggle: onToggleViewingEdited,
          ),
          HistoryDetailAction(
            testId: 'history-detail-copy-displayed',
            icon: LucideIcons.copy,
            tooltip: l10n.historyCopyText,
            onTap: onCopyDisplayed,
          ),
          if (viewingEditedVersion &&
              undoReprocessTooltip != null &&
              onUndoReprocess != null)
            Semantics(
              container: true,
              identifier: 'history-detail-reprocess-undo',
              child: HistoryDetailAction(
                testId: 'history-detail-reprocess-undo-button',
                icon: LucideIcons.undo2,
                tooltip: undoReprocessTooltip!,
                onTap: onUndoReprocess!,
              ),
            ),
        ],
        Semantics(
          container: true,
          identifier: 'history-detail-versions',
          child: HistoryDetailAction(
            testId: 'history-detail-versions-button',
            icon: LucideIcons.history,
            tooltip: l10n.historyVersions,
            onTap: onShowVersions,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Raw/edited view toggle (ticket 05) — a two-segment pill, same visual
// family as the edit/save pill it sits next to.
// ---------------------------------------------------------------------------

class _RawEditedToggle extends StatelessWidget {
  const _RawEditedToggle({
    required this.viewingEditedVersion,
    required this.onToggle,
  });

  final bool viewingEditedVersion;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = WpColors.accent;
    final textMuted = WpColors.textMuted;

    Widget segment(String label, bool selected) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: WpRadius.borderFull,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: WpTypography.small,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? accent : textMuted,
        ),
      ),
    );

    return Material(
      color: WpColors.surfaceMutedFill,
      borderRadius: WpRadius.borderFull,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            selected: !viewingEditedVersion,
            label: l10n.historyViewRaw,
            child: InkWell(
              borderRadius: WpRadius.borderFull,
              onTap: viewingEditedVersion ? onToggle : null,
              child: segment(l10n.historyViewRaw, !viewingEditedVersion),
            ),
          ),
          Semantics(
            button: true,
            selected: viewingEditedVersion,
            label: l10n.historyViewEdited,
            child: InkWell(
              borderRadius: WpRadius.borderFull,
              onTap: viewingEditedVersion ? null : onToggle,
              child: segment(l10n.historyViewEdited, viewingEditedVersion),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel action button
// ---------------------------------------------------------------------------

/// One header or toolbar action of the detail panel. A thin name for the
/// shared [WpIconButton.ghost], so the panel's actions have the same size,
/// edge and spacing as the note editor's and the markdown toolbar's
/// (#1498 F-header-actions) instead of a hand-drawn look of their own.
class HistoryDetailAction extends StatelessWidget {
  const HistoryDetailAction({
    super.key,
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.onTap,
    this.isDestructive = false,
    this.activeColor,
    this.testId,
  }) : assert(icon != null || faIcon != null, 'Provide icon or faIcon');

  final IconData? icon;
  final FaIconData? faIcon;
  final String tooltip;
  final VoidCallback onTap;

  /// Paints the glyph in the error colour, so the action that destroys the
  /// entry reads apart from its neighbours.
  final bool isDestructive;

  /// When set, overrides the icon color (the pinned star).
  final Color? activeColor;

  /// Stable id, `history-detail-<action>`.
  final String? testId;

  @override
  Widget build(BuildContext context) => WpIconButton.ghost(
    compact: true,
    icon: faIcon == null ? icon : null,
    faIcon: faIcon,
    tooltip: tooltip,
    onPressed: onTap,
    testId: testId,
    color: activeColor ?? (isDestructive ? WpColors.error : null),
  );
}

// ---------------------------------------------------------------------------
// Detail metadata row
// ---------------------------------------------------------------------------

class HistoryDetailMetaRow extends StatelessWidget {
  const HistoryDetailMetaRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textSecondary = WpColors.textSecondary;
    final textPrimary = WpColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      child: Row(
        children: [
          Icon(icon, size: WpIconSize.xs, color: textSecondary),
          const SizedBox(width: WpSpacing.sm),
          Text(
            label,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: textSecondary,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact inline metadata chip for the detail panel.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = WpColors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: WpIconSize.xxs, color: fg),
        const SizedBox(width: WpSpacing.xxs),
        Text(
          label,
          style: TextStyle(fontSize: WpTypography.caption, color: fg),
        ),
      ],
    );
  }
}

/// The target app as a meta chip: its icon (system icon or category tile)
/// and readable name, resolved when the chip is shown.
class _TargetAppChip extends ConsumerWidget {
  const _TargetAppChip({required this.identifier});

  final String identifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WpAppIcon(identifier: identifier, size: WpIconSize.sm),
        const SizedBox(width: WpSpacing.xxs),
        Text(
          watchAppName(ref, identifier),
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: WpColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tag section — connects WpTagInput to HistoryDetailNotifier
// ---------------------------------------------------------------------------

class _TagSection extends ConsumerStatefulWidget {
  const _TagSection({
    super.key,
    required this.entryId,
    required this.tags,
    required this.content,
    required this.searchQuery,
    required this.onSearchChanged,
    this.isTrashView = false,
  });

  /// Trashed entries keep their tags visible but cannot change them.
  final bool isTrashView;

  final String entryId;
  final List<Tag> tags;
  final String content;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  @override
  ConsumerState<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends ConsumerState<_TagSection> {
  List<Tag> _suggestions = [];
  Map<String, int> _suggestionCounts = {};
  final GlobalKey<WpTagInputState> _tagInputKey = GlobalKey<WpTagInputState>();

  /// Reloads the suggestions after tag management changed the tag set.
  void reloadSuggestions() => _loadSuggestions();

  /// Called by keyboard shortcut (T) to enter tag add mode.
  void focusTagInput() {
    _tagInputKey.currentState?.enterAddMode();
  }

  @override
  void didUpdateWidget(covariant _TagSection old) {
    super.didUpdateWidget(old);
    if (old.searchQuery != widget.searchQuery) {
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    final result = await loadTagSuggestions(
      ref.read(historyDatabaseProvider),
      widget.searchQuery,
    );
    if (!mounted) return;
    setState(() {
      _suggestions = result.tags;
      _suggestionCounts = result.counts;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(historyDetailProvider(widget.entryId).notifier);
    final l10n = L10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WpTagInput(
          key: _tagInputKey,
          readOnly: widget.isTrashView,
          tags: widget.tags,
          hintText: l10n.historyAddTag,
          searchHintText: l10n.historySearchTags,
          suggestions: _suggestions,
          suggestionCounts: _suggestionCounts,
          // No label or gear in front of the chips (#1498): the "Add tag"
          // chip names the row itself and keeps it narrow enough to share the
          // toolbar row; tag management lives in the head's "…" menu.
          onSearchChanged: (q) {
            widget.onSearchChanged(q);
            _loadSuggestions();
          },
          onAdd: (name) => notifier.addTag(name),
          onRemove: (tagId) {
            final tag = widget.tags.where((t) => t.id == tagId).firstOrNull;
            final tagName = tag?.name ?? '';
            notifier.removeTag(tagId);
            if (tag != null) {
              showWpNotice(
                context,
                WpNotice(
                  id: 'history-tag-removed',
                  kind: WpNoticeKind.undo,
                  message: l10n.historyTagRemoved,
                  actionLabel: l10n.undo,
                  onAction: () => notifier.addTag(tagName),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Kept-until notice (failed recording whose audio is still parked)
// ---------------------------------------------------------------------------

/// Shows until when the audio of a failed, parked recording is kept, and the
/// two next steps beside it: retry it, or discard its audio. Reads the same
/// record and the same date text as Settings → Privacy, and uses the same
/// queue actions there.
class _KeptUntilNotice extends ConsumerStatefulWidget {
  const _KeptUntilNotice({required this.entryId});

  final String entryId;

  @override
  ConsumerState<_KeptUntilNotice> createState() => _KeptUntilNoticeState();
}

class _KeptUntilNoticeState extends ConsumerState<_KeptUntilNotice> {
  /// Set while a retry or a discard runs, so a second tap cannot start the
  /// same work twice on one kept recording.
  bool _busy = false;

  Future<void> _retry(L10n l10n) async {
    setState(() => _busy = true);
    PendingRetryOutcome? outcome;
    try {
      outcome = await ref
          .read(recordingOrchestratorProvider.notifier)
          .retryKeptDictation(entryId: widget.entryId);
    } finally {
      if (mounted) {
        ref.invalidate(pendingRetryListProvider);
        setState(() => _busy = false);
      }
    }
    final message = pendingRetryMessage(l10n, outcome);
    if (mounted && message != null) {
      showWpPageNotice(
        context,
        page: WpNoticePage.history,
        notice: WpPageNotice(
          id: 'retry-failed',
          message: message,
          area: widget.entryId,
        ),
      );
    }
  }

  /// Asks first: the parked audio is deleted from the device and cannot be
  /// transcribed again afterwards (UX-099). Same confirmation as the recovery
  /// banner.
  Future<void> _discard(L10n l10n) async {
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.recoveryDiscardConfirm,
      message: l10n.pendingAudioDiscardConfirmMessage,
      confirmLabel: l10n.recoveryDiscard,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(pendingAudioQueueProvider).discard(widget.entryId);
    } finally {
      if (mounted) {
        ref.invalidate(pendingRetryListProvider);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parked = (ref.watch(pendingRetryListProvider).value ?? const [])
        .where((e) => e.entryId == widget.entryId);
    if (parked.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pendingAudioKeptUntil(
              formatKeptUntil(locale, parked.first.expiresAt),
            ),
            key: const ValueKey('history-detail-kept-until'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: WpSpacing.sm),
          Wrap(
            spacing: WpSpacing.buttonGap,
            runSpacing: WpSpacing.sm,
            children: [
              WpButton(
                testId: 'history-detail-kept-retry',
                label: l10n.actionRetry,
                variant: WpButtonVariant.secondary,
                onPressed: _busy ? null : () => _retry(l10n),
              ),
              WpButton(
                testId: 'history-detail-kept-discard',
                label: l10n.recoveryDiscard,
                variant: WpButtonVariant.ghost,
                tone: WpButtonTone.danger,
                onPressed: _busy ? null : () => _discard(l10n),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
