import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import '../data/history_detail_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/toast.dart';
import 'voice_note_button.dart';

// ---------------------------------------------------------------------------
// Inline notes section (progressive disclosure)
// ---------------------------------------------------------------------------

class HistoryNotesSection extends ConsumerStatefulWidget {
  const HistoryNotesSection({super.key, required this.entryId, required this.isDark});
  final String entryId;
  final bool isDark;

  @override
  ConsumerState<HistoryNotesSection> createState() => HistoryNotesSectionState();
}

class HistoryNotesSectionState extends ConsumerState<HistoryNotesSection> {
  final _controller = TextEditingController();
  final _editController = TextEditingController();
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
    super.dispose();
  }

  void _addNote() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    db.upsertNote(EntryNotesCompanion(
      id: Value(now.millisecondsSinceEpoch.toString()),
      entryId: Value(widget.entryId),
      content: Value(text),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    _controller.clear();
    setState(() => _isAdding = false);
  }

  Future<void> _deleteNote(String noteId, String noteContent) async {
    // Capture all context-dependent values before async gap
    final l10n = L10n.of(context);
    final savedNote = noteContent;
    
    // Delete the note
    await ref.read(historyDatabaseProvider).deleteNote(noteId);
    
    // Show undo toast (using captured overlay, not context after await)
    if (mounted) {
      WpToast.show(
        context,
        message: l10n.historyNoteDeleted,
        type: WpToastType.info,
        duration: const Duration(seconds: 4),
        actionLabel: l10n.undo,
        onAction: () {
          ref.read(historyDatabaseProvider).upsertNote(
            EntryNotesCompanion(
              id: Value(noteId),
              entryId: Value(widget.entryId),
              content: Value(savedNote),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
        },
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final notes = ref.watch(entryNotesProvider(widget.entryId));
    final textPrimary =
        widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final borderColor = widget.isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final surfaceElevated = widget.isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;

    return notes.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (noteList) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(LucideIcons.stickyNote, size: 14, color: textMuted),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  noteList.isEmpty
                      ? l10n.historyAddNote
                      : '${l10n.historyNotes} (${noteList.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const Spacer(),
                VoiceNoteButton(
                  entryId: widget.entryId,
                  isDark: widget.isDark,
                ),
                const SizedBox(width: WpSpacing.xxs),
                if (!_isAdding)
                  Tooltip(
                    message: l10n.historyAddNote,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _isAdding = true),
                        child: Icon(LucideIcons.plus, size: 16, color: accent),
                      ),
                    ),
                  ),
              ],
            ),
            // Add note input
            if (_isAdding) ...[
              const SizedBox(height: WpSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: WpRadius.borderSm,
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: TextStyle(fontSize: 13, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: l10n.historyNotePlaceholder,
                          hintStyle: TextStyle(color: textMuted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: WpSpacing.sm,
                            vertical: WpSpacing.xs,
                          ),
                        ),
                        onSubmitted: (_) => _addNote(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.check, size: 16, color: accent),
                      onPressed: _addNote,
                      splashRadius: 16,
                      padding: const EdgeInsets.all(WpSpacing.xs),
                      constraints: const BoxConstraints(),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: textMuted),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _isAdding = false);
                      },
                      splashRadius: 16,
                      padding: const EdgeInsets.all(WpSpacing.xs),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: WpSpacing.xxs),
                  ],
                ),
              ),
            ],
            // Existing notes
            for (final note in noteList) ...[
              const SizedBox(height: WpSpacing.xs),
              _NoteItem(
                note: note,
                isEditing: _editingNoteId == note.id,
                editController: _editController,
                isDark: widget.isDark,
                accent: accent,
                textPrimary: textPrimary,
                textMuted: textMuted,
                surfaceElevated: surfaceElevated,
                borderColor: borderColor,
                onSave: () => _saveEditedNote(note.id),
                onCancel: _cancelEditing,
                onStartEdit: () => _startEditing(note.id, note.content),
                onDelete: () => _deleteNote(note.id, note.content),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Single note item with hover state
// ---------------------------------------------------------------------------

class _NoteItem extends StatefulWidget {
  const _NoteItem({
    required this.note,
    required this.isEditing,
    required this.editController,
    required this.isDark,
    required this.accent,
    required this.textPrimary,
    required this.textMuted,
    required this.surfaceElevated,
    required this.borderColor,
    required this.onSave,
    required this.onCancel,
    required this.onStartEdit,
    required this.onDelete,
  });

  final EntryNote note;
  final bool isEditing;
  final TextEditingController editController;
  final bool isDark;
  final Color accent;
  final Color textPrimary;
  final Color textMuted;
  final Color surfaceElevated;
  final Color borderColor;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onStartEdit;
  final VoidCallback onDelete;

  @override
  State<_NoteItem> createState() => _NoteItemState();
}

class _NoteItemState extends State<_NoteItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _hovered ? Duration.zero : WpMotion.hoverOut,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: _hovered && !widget.isEditing
              ? hoverBg
              : widget.surfaceElevated,
          borderRadius: WpRadius.borderSm,
          border: Border.all(
            color: widget.isEditing ? widget.accent : widget.borderColor,
          ),
        ),
        child: widget.isEditing
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.editController,
                      autofocus: true,
                      style: TextStyle(
                          fontSize: 13, color: widget.textPrimary),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: WpSpacing.xxs,
                        ),
                      ),
                      onSubmitted: (_) => widget.onSave(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.check,
                        size: 14, color: widget.accent),
                    onPressed: widget.onSave,
                    padding: const EdgeInsets.all(WpSpacing.xxs),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14, color: widget.textMuted),
                    onPressed: widget.onCancel,
                    padding: const EdgeInsets.all(WpSpacing.xxs),
                    constraints: const BoxConstraints(),
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
                              fontSize: 13, color: widget.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.yMd()
                              .add_Hm()
                              .format(widget.note.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: widget.textMuted),
                        ),
                      ],
                    ),
                  ),
                  // Show action icons on hover
                  AnimatedOpacity(
                    opacity: _hovered ? 1.0 : 0.0,
                    duration: _hovered ? Duration.zero : WpMotion.hoverOut,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: widget.onStartEdit,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: WpSpacing.xs),
                              child: Icon(LucideIcons.pencil,
                                  size: 13, color: widget.textMuted),
                            ),
                          ),
                        ),
                        const SizedBox(width: WpSpacing.xxs),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: widget.onDelete,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: WpSpacing.xxs),
                              child: Icon(LucideIcons.x,
                                  size: 14, color: widget.textMuted),
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