/// Orchestrates the user-facing export flow for a single [Note].
///
/// 1:1 structure of `history_exporter.dart`, scoped down to one note at a
/// time (no multi-select for Notizen) and restricted to the txt/md formats
/// (`notesExportFormats`) — Notes have no structured metadata (duration,
/// language, model, cost) worth a CSV/JSON/DOCX export.
///
/// Responsibilities:
///   1. Show the format picker, pre-filtered to txt/md.
///   2. Map [Note] + its tags → [ExportEntry].
///   3. Ask the native save dialog where the file goes (a cancel is silent).
///   4. Invoke [ExportService.export] with the chosen path.
///   5. Surface success/error via [WpToast].
library;

import 'package:flutter/widgets.dart';

import '../../core/data/database.dart' show Note, Tag;
import '../../core/l10n/generated/app_localizations.dart';
import '../../features/history/data/export_service.dart';
import '../../features/notes/data/note_title.dart';
import '../../widgets/export_format_picker.dart';
import '../../widgets/toast.dart';
import '../history/history_exporter.dart'
    show
        ExportFn,
        ExportSaveLocationFn,
        ToasterFn,
        exportErrorMessage,
        pickExportSaveLocation;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

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
/// - On success: `WpToast` shows `"Exported to <fullPath>"` (success).
/// - On failure: `WpToast` shows the exception message (error).
Future<void> exportNote(BuildContext context, Note note, List<Tag> tags) {
  return const NotesExporter().exportNote(context, note, tags);
}

// ---------------------------------------------------------------------------
// Injectable seam (top-level typedef + function)
// ---------------------------------------------------------------------------

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
/// [ExportService.export], [pickExportSaveLocation], and [WpToast.show]. Tests
/// construct a [NotesExporter] with fakes to assert orchestration behaviour
/// without touching the filesystem or platform channels.
class NotesExporter {
  const NotesExporter({
    this.pickerFn = _pickNotesFormat,
    this.exporter = ExportService.export,
    this.saveLocationFn = pickExportSaveLocation,
    this.toaster = _defaultToaster,
  });

  final NotesExportFormatPickerFn pickerFn;
  final ExportFn exporter;
  final ExportSaveLocationFn saveLocationFn;
  final ToasterFn toaster;

  /// Run the export flow. See [exportNote] for behaviour contract.
  Future<void> exportNote(
    BuildContext context,
    Note note,
    List<Tag> tags,
  ) async {
    final format = await pickerFn(context);
    if (format == null) return;
    if (!context.mounted) return;

    final exportRow = _toExportEntry(note, tags, L10n.of(context));

    final filename = ExportService.defaultFilename([exportRow], format);
    final fullPath = await saveLocationFn(
      format: format,
      suggestedName: filename,
    );
    if (fullPath == null) return;
    if (!context.mounted) return;

    try {
      await exporter([exportRow], format, fullPath);
      if (!context.mounted) return;
      toaster(context, WpToastType.success, 'Exported to $fullPath');
    } catch (e) {
      if (!context.mounted) return;
      toaster(context, WpToastType.error, exportErrorMessage(e));
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
// Default toaster
// ---------------------------------------------------------------------------

void _defaultToaster(BuildContext context, WpToastType type, String message) {
  WpToast.show(context, message: message, type: type);
}
