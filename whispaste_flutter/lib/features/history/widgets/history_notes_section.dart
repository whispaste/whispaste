import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
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
  bool _isAdding = false;

  /// Called by keyboard shortcut (N) to start adding a new note.
  void startAddingNote() {
    setState(() => _isAdding = true);
  }

  @override
  void dispose() {
    _controller.dispose();
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
    // Capture context dependencies before async gap
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    
    // Save the note content for undo
    final savedNote = noteContent;
    
    // Delete the note
    await ref.read(historyDatabaseProvider).deleteNote(noteId);
    
    // Show undo snackbar
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.historyNoteDeleted),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () {
              // Restore the note
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
          ),
        ),
      );
    }
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
                  GestureDetector(
                    onTap: () => setState(() => _isAdding = true),
                    child: Icon(LucideIcons.plus, size: 16, color: accent),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: WpRadius.borderSm,
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.content,
                            style:
                                TextStyle(fontSize: 13, color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat.yMd().add_Hm().format(note.createdAt),
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteNote(note.id, note.content),
                      child: Padding(
                        padding: const EdgeInsets.only(left: WpSpacing.xs),
                        child:
                            Icon(LucideIcons.x, size: 14, color: textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
