/// Orchestrates the user-facing export flow for [HistoryEntry] rows.
///
/// Responsibilities:
///   1. Show the format picker.
///   2. Map [HistoryEntry] → [ExportEntry] (tags JSON-decoded defensively).
///   3. Ask the native save dialog where the file goes (a cancel is silent).
///   4. Invoke [ExportService.export] with the chosen path.
///   5. Surface success/error as a notice on the page ([showWpPageNotice]).
///
/// The orchestration is exposed as a top-level function [exportEntries] for
/// call-sites in `HistoryPage` and `HistoryDetailPanel`. Internally it is
/// backed by [HistoryExporter], a class with injectable dependencies so unit
/// tests can substitute fakes for the picker, exporter, save dialog,
/// and notifier without spinning up real platform channels.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../core/data/database.dart' show HistoryEntry;
import '../../core/l10n/generated/app_localizations.dart';
import '../../features/history/data/export_service.dart';
import '../../widgets/export_format_picker.dart';
import '../../widgets/onboarding_hold.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_banner.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Orchestrate the export flow for [entries].
///
/// Behaviour:
/// - If [entries] is empty: no-op (no picker shown, no notice).
/// - If the picker or the save dialog is dismissed (returns `null`): no-op.
/// - On success: a notice names the save location (`"Exported to <fullPath>"`).
/// - On failure: an error notice names the next step (the raw error is hidden).
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
/// or `null` when the user cancels (not an error, so no notice).
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

/// Toaster seam — shows a page notice of the given [WpMessageType] (success
/// and info render as info, error as error).
typedef ToasterFn =
    void Function(BuildContext context, WpMessageType type, String message);

// ---------------------------------------------------------------------------
// HistoryExporter
// ---------------------------------------------------------------------------

/// Class form of [exportEntries] — accepts injectable dependencies for tests.
///
/// The default constructor wires production bindings:
/// [showWpExportFormatPicker], [pickExportSaveLocation], [ExportService.export],
/// and [showWpPageNotice]. Tests construct a [HistoryExporter] with fakes to
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
        WpMessageType.success,
        L10n.of(context).historyExportDone(fullPath),
      );
    } catch (e) {
      // The raw error (e.g. a FileSystemException) is not shown: the notice
      // names the next step instead (UIA-HIS-12).
      if (!context.mounted) return;
      toaster(
        context,
        WpMessageType.error,
        L10n.of(context).historyExportFailed,
      );
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

// ---------------------------------------------------------------------------
// Default notifier
// ---------------------------------------------------------------------------

void _defaultToaster(BuildContext context, WpMessageType type, String message) {
  showWpPageNotice(
    context,
    page: WpNoticePage.history,
    notice: WpPageNotice(
      id: type == WpMessageType.error ? 'export-failed' : 'export-done',
      message: message,
      tone: type == WpMessageType.error
          ? WpBannerTone.error
          : WpBannerTone.info,
    ),
  );
}
