/// Orchestrates the user-facing export flow for one [Note] or a multi-select
/// of notes (#655, all of them in one file).
///
/// 1:1 structure of `history_exporter.dart`, restricted to the txt/md formats
/// (`notesExportFormats`) — Notes have no structured metadata (duration,
/// language, model, cost) worth a CSV/JSON/DOCX export.
///
/// Responsibilities:
///   1. Show the format picker, pre-filtered to txt/md.
///   2. Map [Note] + its tags → [ExportEntry].
///   3. Ask the native save dialog where the file goes (a cancel is silent).
///   4. Invoke [ExportService.export] with the chosen path.
///   5. Surface success/error as a notice at the editor ([showWpPageNotice]).
library;

import 'package:flutter/widgets.dart';

import '../../core/data/database.dart' show Note, Tag;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../features/history/data/export_service.dart';
import '../../features/notes/data/note_title.dart';
import '../../widgets/export_format_picker.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_notice_bar.dart';
import '../history/history_exporter.dart'
    show ExportFn, ExportSaveLocationFn, pickExportSaveLocation;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

final _log = AppLogger('NotesExporter');

/// Notes-only formats — txt/md. Unlike history entries, a note has no
/// duration/language/model/cost fields, so CSV/JSON/DOCX would just be an
/// oddly-shaped text export.
const List<ExportFormat> notesExportFormats = [
  ExportFormat.txt,
  ExportFormat.md,
];

/// Orchestrate the export flow for [note].
///
/// Behaviour mirrors [history_exporter.exportEntries]:
/// - If the picker or the save dialog is dismissed (returns `null`): no-op.
/// - On success: a notice at the editor names the save location.
/// - On failure: an error notice names the next step (the raw error is hidden).
Future<void> exportNote(BuildContext context, Note note, List<Tag> tags) {
  return const NotesExporter().exportNote(context, note, tags);
}

/// Orchestrate the export flow for several [notes] (multi-select, #655):
/// one format pick, one save dialog, one file with all notes in the given
/// order. Same cancel/success/failure contract as [exportNote]; the notice
/// goes to the page head, as no single editor owns it.
Future<void> exportNotes(
  BuildContext context,
  List<Note> notes,
  Map<String, List<Tag>> tagsByNoteId,
) {
  return const NotesExporter().exportNotes(context, notes, tagsByNoteId);
}

// ---------------------------------------------------------------------------
// Injectable seam (top-level typedef + function)
// ---------------------------------------------------------------------------

/// Notice seam — reports the result for note [noteId] at its editor, or at
/// the page head when [noteId] is `null` (a multi-note export).
typedef NotesNoticeFn =
    void Function(
      BuildContext context, {
      required String? noteId,
      required bool failed,
      required String message,
    });

/// Picker seam — shows the export-format picker, pre-filtered to txt/md.
typedef NotesExportFormatPickerFn =
    Future<ExportFormat?> Function(BuildContext context);

Future<ExportFormat?> _pickNotesFormat(BuildContext context) =>
    showWpExportFormatPicker(context, formats: notesExportFormats);

// ---------------------------------------------------------------------------
// NotesExporter
// ---------------------------------------------------------------------------

/// Class form of [exportNote] — accepts injectable dependencies for tests.
///
/// The default constructor wires production bindings: [_pickNotesFormat],
/// [ExportService.export], [pickExportSaveLocation], and [showWpPageNotice]. Tests
/// construct a [NotesExporter] with fakes to assert orchestration behaviour
/// without touching the filesystem or platform channels.
class NotesExporter {
  const NotesExporter({
    this.pickerFn = _pickNotesFormat,
    this.exporter = ExportService.export,
    this.saveLocationFn = pickExportSaveLocation,
    this.notifier = _defaultNotifier,
  });

  final NotesExportFormatPickerFn pickerFn;
  final ExportFn exporter;
  final ExportSaveLocationFn saveLocationFn;
  final NotesNoticeFn notifier;

  /// Run the export flow. See [exportNote] for behaviour contract.
  Future<void> exportNote(BuildContext context, Note note, List<Tag> tags) =>
      _export(context, [note], {note.id: tags}, noticeArea: note.id);

  /// Run the multi-note export flow. See [exportNotes].
  Future<void> exportNotes(
    BuildContext context,
    List<Note> notes,
    Map<String, List<Tag>> tagsByNoteId,
  ) {
    if (notes.isEmpty) return Future.value();
    return _export(context, notes, tagsByNoteId, noticeArea: null);
  }

  Future<void> _export(
    BuildContext context,
    List<Note> notes,
    Map<String, List<Tag>> tagsByNoteId, {
    required String? noticeArea,
  }) async {
    final format = await pickerFn(context);
    if (format == null) return;
    if (!context.mounted) return;

    final l10n = L10n.of(context);
    final rows = [
      for (final note in notes)
        _toExportEntry(note, tagsByNoteId[note.id] ?? const [], l10n),
    ];

    final filename = ExportService.defaultFilename(rows, format);
    final fullPath = await saveLocationFn(
      format: format,
      suggestedName: filename,
    );
    if (fullPath == null) return;
    if (!context.mounted) return;

    try {
      await exporter(rows, format, fullPath);
      if (!context.mounted) return;
      notifier(
        context,
        noteId: noticeArea,
        failed: false,
        message: L10n.of(context).historyExportDone(fullPath),
      );
    } catch (e) {
      _log.warning('Note export failed: $e');
      if (!context.mounted) return;
      // The raw error is not shown: the notice names the next step.
      notifier(
        context,
        noteId: noticeArea,
        failed: true,
        message: L10n.of(context).historyExportFailed,
      );
    }
  }

  // ── Mapping ────────────────────────────────────────────────────────────

  static ExportEntry _toExportEntry(Note note, List<Tag> tags, L10n l10n) {
    return ExportEntry(
      id: note.id,
      title: deriveNoteTitle(note.content) ?? l10n.notesUntitled,
      text: note.content,
      timestamp: note.updatedAt.toIso8601String(),
      tags: tags.map((t) => t.name).toList(growable: false),
      pinned: note.pinned,
    );
  }
}

// ---------------------------------------------------------------------------
// Default notifier
// ---------------------------------------------------------------------------

void _defaultNotifier(
  BuildContext context, {
  required String? noteId,
  required bool failed,
  required String message,
}) {
  if (!failed) {
    // A short confirmation stands at the bottom like every other (#1903).
    showWpConfirmation(context, id: 'notes-export-done', message: message);
    return;
  }
  showWpPageNotice(
    context,
    page: WpNoticePage.notes,
    notice: WpPageNotice(
      id: 'notes-export-failed',
      message: message,
      area: noteId,
    ),
  );
}
