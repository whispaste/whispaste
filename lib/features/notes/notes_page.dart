import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/database.dart';
import '../../core/data/notes_providers.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import 'data/note_autosave.dart';
import 'data/notes_actions.dart';
import 'widgets/notes_split_view.dart';

/// Notes page — standalone sidebar area for free-form notes.
///
/// Master-detail layout mirroring [HistoryPage]'s split view, but deliberately
/// minimal (Ticket 02 scaffold): flat note list on the left, always-editable
/// plain-text editor on the right. No search, trash filter, tags, export, or
/// voice input yet — those hook in via later tickets.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  /// Editor controller + focus node live HERE, not in [NoteEditorPanel] —
  /// the panel rebuilds on every stream emit, and panel-owned controllers
  /// would lose cursor position and IME state on each rebuild.
  final TextEditingController _editorController = TextEditingController();
  final FocusNode _editorFocusNode = FocusNode();

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
    super.dispose();
  }

  void _onEditorChanged() {
    if (_syncingEditor) return;
    final id = _selectedNoteId;
    if (id == null) return;
    _autosave.schedule(id, _editorController.text);
  }

  /// Replaces the editor text without triggering an autosave schedule.
  void _setEditorText(String text) {
    _syncingEditor = true;
    _editorController.text = text;
    _editorController.selection = TextSelection.collapsed(offset: text.length);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final notesAsync = ref.watch(notesProvider);

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _NotesHeader(onCreate: _createNote),
          Expanded(
            child: notesAsync.when(
              data: (notes) {
                if (notes.isEmpty) {
                  // No action button here on purpose: the header's
                  // "New note" button is always visible and already offers
                  // the same action — a second identically labeled button
                  // would be redundant.
                  return WpEmptyState(
                    icon: LucideIcons.stickyNote,
                    title: l10n.notesEmptyTitle,
                    hint: l10n.notesEmptyHint,
                  );
                }
                Note? selectedNote;
                if (_selectedNoteId != null) {
                  final idx = notes.indexWhere((n) => n.id == _selectedNoteId);
                  selectedNote = idx >= 0 ? notes[idx] : null;
                }
                return NotesSplitView(
                  notes: notes,
                  isDark: isDark,
                  selectedNote: selectedNote,
                  editorController: _editorController,
                  editorFocusNode: _editorFocusNode,
                  onNoteTap: _selectNote,
                  onCloseEditor: _closeEditor,
                );
              },
              loading: () => _NotesSkeleton(isDark: isDark),
              error: (e, _) => WpEmptyState(
                icon: LucideIcons.triangleAlert,
                title: l10n.errorGeneric,
                actionLabel: l10n.actionRetry,
                onAction: () => ref.invalidate(notesProvider),
              ),
            ),
          ),
        ],
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
