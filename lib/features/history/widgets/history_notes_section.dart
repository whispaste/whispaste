import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/text/markdown_plain_text.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

import 'package:whispaste/core/data/database.dart';

import '../data/providers.dart';
import '../data/history_detail_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/wp_notice_bar.dart';
import '../../../widgets/wp_discoverability_hint.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_text_field.dart';
import 'voice_note_button.dart';
import '../../../widgets/wp_copy_feedback.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_error_notice.dart';
import 'history_write_failure.dart';

// ---------------------------------------------------------------------------
// Inline notes section (progressive disclosure)
//
// Actions always visible (reduced opacity); hit areas ≥ 48px,
// interactive icons ≥ 20px.
// ---------------------------------------------------------------------------

class HistoryNotesSection extends ConsumerStatefulWidget {
  const HistoryNotesSection({super.key, required this.entryId});
  final String entryId;

  @override
  ConsumerState<HistoryNotesSection> createState() =>
      HistoryNotesSectionState();
}

class HistoryNotesSectionState extends ConsumerState<HistoryNotesSection> {
  final _controller = TextEditingController();
  final _editController = TextEditingController();
  final _addKeyboardFocusNode = FocusNode();
  bool _isAdding = false;
  String? _editingNoteId;

  /// Called by keyboard shortcut (N) to start adding a new note.
  void startAddingNote() {
    setState(() => _isAdding = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _editController.dispose();
    _addKeyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    try {
      await db.upsertNote(
        EntryNotesCompanion(
          id: Value(now.millisecondsSinceEpoch.toString()),
          entryId: Value(widget.entryId),
          content: Value(text),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    } catch (_) {
      // Keep the text in the input so the user can retry (UIA-HIS-05).
      if (mounted) {
        showHistoryWriteFailed(context, entryId: widget.entryId);
      }
      return;
    }
    if (!mounted) return;
    _controller.clear();
    setState(() => _isAdding = false);
  }

  Future<void> _deleteNote(
    String noteId,
    String noteContent,
    DateTime noteCreatedAt,
  ) async {
    final l10n = L10n.of(context);
    final savedNote = noteContent;

    await ref.read(historyDatabaseProvider).deleteNote(noteId);

    if (mounted) {
      // Captured now: the undo can outlive this section (another entry
      // selected), and a disposed ref must not be touched then.
      final db = ref.read(historyDatabaseProvider);
      final entryId = widget.entryId;
      showWpNotice(
        context,
        WpNotice(
          id: 'history-note-deleted',
          kind: WpNoticeKind.undo,
          message: l10n.historyNoteDeleted,
          actionLabel: l10n.undo,
          onAction: () => db.upsertNote(
            EntryNotesCompanion(
              id: Value(noteId),
              entryId: Value(entryId),
              content: Value(savedNote),
              // Keep the original date, so the note returns to its place
              // in the timeline (UIA-HIS-24).
              createdAt: Value(noteCreatedAt),
              updatedAt: Value(DateTime.now()),
            ),
          ),
        ),
      );
    }
  }

  void _startEditing(String noteId, String content) {
    _editController.text = content;
    setState(() => _editingNoteId = noteId);
  }

  void _saveEditedNote(String noteId) {
    final newContent = _editController.text.trim();
    if (newContent.isEmpty) return;
    ref
        .read(historyDetailProvider(widget.entryId).notifier)
        .updateNote(noteId, newContent);
    setState(() => _editingNoteId = null);
  }

  void _cancelEditing() {
    setState(() => _editingNoteId = null);
  }

  void _copyNote(String id, String noteContent) {
    unawaited(
      copyWithFeedback(
        context,
        text: markdownToPlainText(noteContent),
        target: 'history-note-$id',
        category: 'history_note',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final notes = ref.watch(entryNotesProvider(widget.entryId));
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;
    final accent = WpColors.accent;
    final borderColor = WpColors.borderSubtle;
    // Card material for both the add-note row and every saved note below it
    // — the notes are plates inside the detail panel, and `surfaceElevated`
    // was the last opaque fill left in this panel.
    final cardFill = WpColors.cardFill;

    return notes.when(
      loading: () => const SizedBox.shrink(),
      // A failed load must not look like "no notes" (#1635): say so and
      // offer to try again.
      error: (_, _) => WpErrorNotice(
        key: const ValueKey('history-notes-load-error'),
        cause: l10n.historyNotesLoadFailed,
        action: WpButton(
          testId: 'history-notes-retry',
          label: l10n.actionRetry,
          variant: WpButtonVariant.secondary,
          size: WpButtonSize.dense,
          onPressed: () => ref.invalidate(entryNotesProvider(widget.entryId)),
        ),
      ),
      data: (noteList) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — clickable to start adding a note
            Row(
              children: [
                Expanded(
                  // loam-ignore: a11y-interactive-semantics – merged via outer MergeSemantics
                  child: _AddNoteHeaderTapTarget(
                    isAdding: _isAdding,
                    noteListLength: noteList.length,
                    onTap: () => setState(() => _isAdding = true),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                VoiceNoteButton(entryId: widget.entryId),
                const SizedBox(width: WpSpacing.xxs),
                if (!_isAdding)
                  Tooltip(
                    message: l10n.historyAddNote,
                    child: InkWell(
                      onTap: () => setState(() => _isAdding = true),
                      borderRadius: WpRadius.borderSm,
                      child: Padding(
                        padding: const EdgeInsets.all(WpSpacing.xs),
                        child: Icon(
                          LucideIcons.plus,
                          size: WpIconSize.md,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Add note input
            if (_isAdding) ...[
              const SizedBox(height: WpSpacing.sm),
              // Same row as a note being edited, and for the same reason:
              // this is a note being authored. One border colour for that one
              // state — see `_NoteItem`.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cardFill,
                  borderRadius: WpRadius.borderSm,
                  border: Border.all(color: accent),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: KeyboardListener(
                        focusNode: _addKeyboardFocusNode,
                        onKeyEvent: (event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _addNote();
                          }
                        },
                        child: WpTextField(
                          controller: _controller,
                          variant: WpTextFieldVariant.embedded,
                          autofocus: true,
                          hintText: l10n.historyNotePlaceholder,
                          minLines: 1,
                          // Same ceiling as editing an existing note: the
                          // same kind of text does not get a different amount
                          // of room depending on whether it is new.
                          maxLines: 5,
                        ),
                      ),
                    ),
                    WpIconButton.ghost(
                      testId: 'history-note-add-save',
                      icon: LucideIcons.check,
                      color: accent,
                      tooltip: l10n.actionSave,
                      onPressed: _addNote,
                    ),
                    WpIconButton.ghost(
                      testId: 'history-note-add-cancel',
                      icon: LucideIcons.x,
                      tooltip: l10n.actionCancel,
                      onPressed: () {
                        _controller.clear();
                        setState(() => _isAdding = false);
                      },
                    ),
                    const SizedBox(width: WpSpacing.xxs),
                  ],
                ),
              ),
              WpDiscoverabilityHint(
                hintId: 'voice_note_prefixes',
                text: l10n.historyVoiceNoteHint,
              ),
            ],
            // Existing notes
            for (final note in noteList) ...[
              const SizedBox(height: WpSpacing.xs),
              WpCopyAnchor(
                target: 'history-note-${note.id}',
                child: _NoteItem(
                  key: ValueKey(note.id),
                  note: note,
                  isEditing: _editingNoteId == note.id,
                  editController: _editController,
                  accent: accent,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  cardFill: cardFill,
                  borderColor: borderColor,
                  onSave: () => _saveEditedNote(note.id),
                  onCancel: _cancelEditing,
                  onStartEdit: () => _startEditing(note.id, note.content),
                  onDelete: () =>
                      _deleteNote(note.id, note.content, note.createdAt),
                  onCopy: () => _copyNote(note.id, note.content),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Single note item — actions always visible.
// ---------------------------------------------------------------------------

class _NoteItem extends StatefulWidget {
  const _NoteItem({
    super.key,
    required this.note,
    required this.isEditing,
    required this.editController,
    required this.accent,
    required this.textPrimary,
    required this.textMuted,
    required this.cardFill,
    required this.borderColor,
    required this.onSave,
    required this.onCancel,
    required this.onStartEdit,
    required this.onDelete,
    required this.onCopy,
  });

  final EntryNote note;
  final bool isEditing;
  final TextEditingController editController;
  final Color accent;
  final Color textPrimary;
  final Color textMuted;
  final Color cardFill;
  final Color borderColor;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onStartEdit;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  @override
  State<_NoteItem> createState() => _NoteItemState();
}

class _NoteItemState extends State<_NoteItem> {
  bool _hovered = false;
  final _editKeyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _editKeyboardFocusNode.dispose();
    super.dispose();
  }

  String _formatNoteTimestamp(EntryNote note) {
    final fmt = DateFormat.yMd().add_Hm();
    final created = fmt.format(note.createdAt);
    final diff = note.updatedAt.difference(note.createdAt);
    if (diff.inSeconds.abs() > 2) {
      return '$created · ✎ ${fmt.format(note.updatedAt)}';
    }
    return created;
  }

  @override
  Widget build(BuildContext context) {
    // The card material's hover rung, the same one `WpListTileSurface`
    // lifts a card row to — not `surfaceVariant`, which was an opaque tile
    // colour from the old system.
    final hoverBg = WpColors.cardFillElevated;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: WpMotion.durationFor(
          context,
          _hovered ? Duration.zero : WpMotion.hoverOut,
        ),
        // Read mode insets the row itself; edit mode hands that job to the
        // field, whose own 12/14 inset then lands the text on exactly the
        // line it occupied a moment earlier. Padding on both would double it
        // and shift the note as edit mode opens.
        padding: widget.isEditing
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.sm + 2,
              ),
        decoration: BoxDecoration(
          color: _hovered && !widget.isEditing ? hoverBg : widget.cardFill,
          borderRadius: WpRadius.borderSm,
        ),
        // Painted over the row rather than around it — the same reason
        // WpTextField paints its own stroke this way: a decoration border
        // insets what the container holds, so this row would stand 2 dp
        // taller than the identical add-note row above it, and its text 1 dp
        // further in.
        foregroundDecoration: BoxDecoration(
          borderRadius: WpRadius.borderSm,
          border: Border.all(
            color: widget.isEditing ? widget.accent : widget.borderColor,
          ),
        ),
        child: widget.isEditing
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: KeyboardListener(
                      focusNode: _editKeyboardFocusNode,
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          widget.onSave();
                        }
                      },
                      child: WpTextField(
                        controller: widget.editController,
                        variant: WpTextFieldVariant.embedded,
                        semanticsLabel: L10n.of(context).historyEditNote,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 5,
                      ),
                    ),
                  ),
                  WpIconButton.ghost(
                    testId: 'history-note-edit-save',
                    icon: LucideIcons.check,
                    color: widget.accent,
                    tooltip: L10n.of(context).actionSave,
                    onPressed: widget.onSave,
                  ),
                  WpIconButton.ghost(
                    testId: 'history-note-edit-cancel',
                    icon: LucideIcons.x,
                    tooltip: L10n.of(context).actionCancel,
                    onPressed: widget.onCancel,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.note.content,
                          style: TextStyle(
                            fontSize: WpTypography.body,
                            color: widget.textPrimary,
                          ),
                        ),
                        const SizedBox(height: WpSpacing.xxxs),
                        Text(
                          _formatNoteTimestamp(widget.note),
                          style: TextStyle(
                            fontSize: WpTypography.small,
                            color: widget.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions always visible — opacity increases on hover
                  AnimatedOpacity(
                    opacity: _hovered ? 1.0 : 0.35,
                    duration: WpMotion.durationFor(
                      context,
                      _hovered ? Duration.zero : WpMotion.hoverOut,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: L10n.of(context).notesCopy,
                          button: true,
                          child: Tooltip(
                            message: L10n.of(context).notesCopy,
                            excludeFromSemantics: true,
                            child: InkWell(
                              onTap: widget.onCopy,
                              borderRadius: WpRadius.borderSm,
                              child: Padding(
                                padding: const EdgeInsets.all(WpSpacing.xs),
                                child: Icon(
                                  LucideIcons.copy,
                                  size: WpIconSize.sm,
                                  color: widget.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Semantics(
                          label: L10n.of(context).actionEdit,
                          button: true,
                          child: Tooltip(
                            message: L10n.of(context).actionEdit,
                            excludeFromSemantics: true,
                            child: InkWell(
                              onTap: widget.onStartEdit,
                              borderRadius: WpRadius.borderSm,
                              child: Padding(
                                padding: const EdgeInsets.all(WpSpacing.xs),
                                child: Icon(
                                  LucideIcons.pencil,
                                  size: WpIconSize.sm,
                                  color: widget.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Semantics(
                          label: L10n.of(context).actionDelete,
                          button: true,
                          child: Tooltip(
                            message: L10n.of(context).actionDelete,
                            excludeFromSemantics: true,
                            child: InkWell(
                              onTap: widget.onDelete,
                              borderRadius: WpRadius.borderSm,
                              child: Padding(
                                padding: const EdgeInsets.all(WpSpacing.xs),
                                child: Icon(
                                  LucideIcons.x,
                                  size: WpIconSize.sm,
                                  color: widget.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddNoteHeaderTapTarget extends StatefulWidget {
  const _AddNoteHeaderTapTarget({
    required this.isAdding,
    required this.noteListLength,
    required this.onTap,
  });

  final bool isAdding;
  final int noteListLength;
  final VoidCallback onTap;

  @override
  State<_AddNoteHeaderTapTarget> createState() =>
      _AddNoteHeaderTapTargetState();
}

class _AddNoteHeaderTapTargetState extends State<_AddNoteHeaderTapTarget> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'AddNoteHeader');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textSecondary = WpColors.textSecondary;

    return MergeSemantics(
      child: Semantics(
        button: !widget.isAdding,
        label: l10n.historyAddNote,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: widget.isAdding ? null : widget.onTap,
            focusNode: _focusNode,
            borderRadius: WpRadius.borderSm,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Row(
              children: [
                // `textSecondary`, not the accent — same correction as the
                // tag section's glyph directly above it (Ticket 32, B3):
                // the section label is inert, and the two controls that
                // *are* operable (microphone, "+") sit on the same line and
                // keep the accent to themselves.
                Icon(
                  LucideIcons.stickyNote,
                  size: WpIconSize.sm,
                  color: textSecondary,
                ),
                const SizedBox(width: WpSpacing.xs),
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(
                      widget.noteListLength == 0
                          ? l10n.historyAddNote
                          : '${l10n.historyNotes} (${widget.noteListLength})',
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
