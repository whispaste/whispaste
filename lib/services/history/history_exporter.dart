/// Orchestrates the user-facing export flow for [HistoryEntry] rows.
///
/// Responsibilities:
///   1. Show the format picker.
///   2. Map [HistoryEntry] → [ExportEntry] (tags JSON-decoded defensively).
///   3. Ask the native save dialog where the file goes (a cancel is silent).
///   4. Invoke [ExportService.export] with the chosen path.
///   5. Surface success/error via [WpToast].
///
/// The orchestration is exposed as a top-level function [exportEntries] for
/// call-sites in `HistoryPage` and `HistoryDetailPanel`. Internally it is
/// backed by [HistoryExporter], a class with injectable dependencies so unit
/// tests can substitute fakes for the picker, exporter, save dialog,
/// and toaster without spinning up real platform channels.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../core/data/database.dart' show HistoryEntry;
import '../../core/l10n/generated/app_localizations.dart';
import '../../features/history/data/export_service.dart';
import '../../widgets/export_format_picker.dart';
import '../../widgets/toast.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Orchestrate the export flow for [entries].
///
/// Behaviour:
/// - If [entries] is empty: no-op (no picker shown, no toast).
/// - If the picker or the save dialog is dismissed (returns `null`): no-op.
/// - On success: `WpToast` shows `"Exported to <fullPath>"` (success).
/// - On failure: `WpToast` shows the exception message (error).
Future<void> exportEntries(BuildContext context, List<HistoryEntry> entries) {
  return const HistoryExporter().exportEntries(context, entries);
}

// ---------------------------------------------------------------------------
// Injectable seams (top-level typedefs)
// ---------------------------------------------------------------------------

/// Picker seam — shows the export-format picker.
typedef ExportFormatPickerFn =
    Future<ExportFormat?> Function(BuildContext context);

/// Exporter seam — formats and persists [ExportEntry] rows.
typedef ExportFn =
    Future<int> Function(
      List<ExportEntry> entries,
      ExportFormat format,
      String path,
    );

/// Save-dialog seam — asks where the export file goes. Returns the chosen path,
/// or `null` when the user cancels (not an error, so no toast).
typedef ExportSaveLocationFn =
    Future<String?> Function({
      required ExportFormat format,
      required String suggestedName,
    });

/// Production save dialog: the native save panel, filtered to [format].
Future<String?> pickExportSaveLocation({
  required ExportFormat format,
  required String suggestedName,
}) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: [_exportTypeGroup(format)],
    suggestedName: suggestedName,
  );
  return location?.path;
}

/// Type filter for the save panel. Both `extensions` (Windows/Linux) and
/// `uniformTypeIdentifiers` (macOS) are set, see `settings_portability_controller`.
XTypeGroup _exportTypeGroup(ExportFormat format) => switch (format) {
  ExportFormat.txt => const XTypeGroup(
    label: 'Text',
    extensions: ['txt'],
    uniformTypeIdentifiers: ['public.plain-text'],
  ),
  ExportFormat.md => const XTypeGroup(
    label: 'Markdown',
    extensions: ['md'],
    uniformTypeIdentifiers: ['net.daringfireball.markdown'],
  ),
  ExportFormat.json => const XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  ),
  ExportFormat.csv => const XTypeGroup(
    label: 'CSV',
    extensions: ['csv'],
    uniformTypeIdentifiers: ['public.comma-separated-values-text'],
  ),
  ExportFormat.docx => const XTypeGroup(
    label: 'Word',
    extensions: ['docx'],
    uniformTypeIdentifiers: ['org.openxmlformats.wordprocessingml.document'],
  ),
};

/// Toaster seam — shows a [WpToast] of the given [WpToastType].
typedef ToasterFn =
    void Function(BuildContext context, WpToastType type, String message);

// ---------------------------------------------------------------------------
// HistoryExporter
// ---------------------------------------------------------------------------

/// Class form of [exportEntries] — accepts injectable dependencies for tests.
///
/// The default constructor wires production bindings:
/// [showWpExportFormatPicker], [pickExportSaveLocation], [ExportService.export],
/// and [WpToast.show]. Tests construct a [HistoryExporter] with fakes to
/// assert orchestration behaviour without touching the filesystem or platform
/// channels.
class HistoryExporter {
  const HistoryExporter({
    this.pickerFn = showWpExportFormatPicker,
    this.saveLocationFn = pickExportSaveLocation,
    this.exporter = ExportService.export,
    this.toaster = _defaultToaster,
  });

  final ExportFormatPickerFn pickerFn;
  final ExportSaveLocationFn saveLocationFn;
  final ExportFn exporter;
  final ToasterFn toaster;

  /// Run the export flow. See [exportEntries] for behaviour contract.
  Future<void> exportEntries(
    BuildContext context,
    List<HistoryEntry> entries,
  ) async {
    if (entries.isEmpty) return;

    // The picker and the save dialog sit inside the same error path as the
    // write itself (UIA-HIS-12): a failure there is reported, not thrown.
    try {
      final format = await pickerFn(context);
      if (format == null) return;
      if (!context.mounted) return;

      final exportRows = entries.map(_toExportEntry).toList(growable: false);

      final filename = ExportService.defaultFilename(exportRows, format);
      final fullPath = await saveLocationFn(
        format: format,
        suggestedName: filename,
      );
      if (fullPath == null) return;
      if (!context.mounted) return;

      await exporter(exportRows, format, fullPath);
      if (!context.mounted) return;
      toaster(
        context,
        WpToastType.success,
        L10n.of(context).historyExportDone(fullPath),
      );
    } catch (e) {
      // The raw error (e.g. a FileSystemException) is not shown: the toast
      // names the next step instead (UIA-HIS-12).
      if (!context.mounted) return;
      toaster(context, WpToastType.error, L10n.of(context).historyExportFailed);
    }
  }

  // ── Mapping ────────────────────────────────────────────────────────────

  static ExportEntry _toExportEntry(HistoryEntry e) {
    return ExportEntry(
      id: e.id,
      title: e.title,
      text: e.content,
      timestamp: e.timestamp.toIso8601String(),
      duration: e.durationSec,
      language: e.language,
      tags: _decodeTags(e.tags),
      pinned: e.pinned,
      model: e.model,
      isLocal: e.isLocal,
      costUsd: e.costUsd,
      projectName: '',
    );
  }

  /// Defensively decode the JSON-encoded `tags` field.
  ///
  /// Returns `[]` for empty strings, malformed JSON, or any non-`List<String>`
  /// shape. Never throws.
  static List<String> _decodeTags(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}

/// Best-effort extraction of a human-readable message from [error].
///
/// Falls back to `error.toString()` so the user always sees something.
/// Shared by the history and notes exporters.
String exportErrorMessage(Object error) {
  if (error is Exception) {
    // Strip the leading "Exception: " that Dart inserts on toString().
    final s = error.toString();
    const prefix = 'Exception: ';
    if (s.startsWith(prefix)) return s.substring(prefix.length);
    return s;
  }
  return error.toString();
}

// ---------------------------------------------------------------------------
// Default toaster
// ---------------------------------------------------------------------------

void _defaultToaster(BuildContext context, WpToastType type, String message) {
  WpToast.show(context, message: message, type: type);
}
