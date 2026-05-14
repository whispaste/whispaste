/// Orchestrates the user-facing export flow for [HistoryEntry] rows.
///
/// Responsibilities:
///   1. Show the format picker.
///   2. Map [HistoryEntry] → [ExportEntry] (tags JSON-decoded defensively).
///   3. Resolve the output directory (Downloads, falling back to Documents).
///   4. Invoke [ExportService.export] with the resolved path.
///   5. Surface success/error via [WpToast].
///
/// The orchestration is exposed as a top-level function [exportEntries] for
/// call-sites in `HistoryPage` and `HistoryDetailPanel`. Internally it is
/// backed by [HistoryExporter], a class with injectable dependencies so unit
/// tests can substitute fakes for the picker, exporter, path resolver, and
/// toaster without spinning up real platform channels.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/data/database.dart' show HistoryEntry;
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
/// - If the picker is dismissed (returns `null`): no-op.
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

/// Path resolver seam — resolves the directory the export file lives in.
typedef PathResolverFn = Future<Directory?> Function();

/// Toaster seam — shows a [WpToast] of the given [WpToastType].
typedef ToasterFn =
    void Function(BuildContext context, WpToastType type, String message);

// ---------------------------------------------------------------------------
// HistoryExporter
// ---------------------------------------------------------------------------

/// Class form of [exportEntries] — accepts injectable dependencies for tests.
///
/// The default constructor wires production bindings:
/// [showExportFormatPicker], [ExportService.export], [getDownloadsDirectory] /
/// [getApplicationDocumentsDirectory], and [WpToast.show]. Tests construct
/// a [HistoryExporter] with fakes to assert orchestration behaviour without
/// touching the filesystem or platform channels.
class HistoryExporter {
  const HistoryExporter({
    this.pickerFn = showExportFormatPicker,
    this.exporter = ExportService.export,
    this.downloadsDirFn = getDownloadsDirectory,
    this.documentsDirFn = getApplicationDocumentsDirectory,
    this.toaster = _defaultToaster,
  });

  final ExportFormatPickerFn pickerFn;
  final ExportFn exporter;
  final PathResolverFn downloadsDirFn;
  final PathResolverFn documentsDirFn;
  final ToasterFn toaster;

  /// Run the export flow. See [exportEntries] for behaviour contract.
  Future<void> exportEntries(
    BuildContext context,
    List<HistoryEntry> entries,
  ) async {
    if (entries.isEmpty) return;

    final format = await pickerFn(context);
    if (format == null) return;
    if (!context.mounted) return;

    final exportRows = entries.map(_toExportEntry).toList(growable: false);

    final dir = await downloadsDirFn() ?? await documentsDirFn();
    final dirPath = dir?.path ?? '.';
    final filename = ExportService.defaultFilename(exportRows, format);
    final fullPath = '$dirPath/$filename';

    try {
      await exporter(exportRows, format, fullPath);
      if (!context.mounted) return;
      toaster(context, WpToastType.success, 'Exported to $fullPath');
    } catch (e) {
      if (!context.mounted) return;
      toaster(context, WpToastType.error, _exceptionMessage(e));
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

  /// Best-effort extraction of a human-readable message from [error].
  ///
  /// Falls back to `error.toString()` so the user always sees something.
  static String _exceptionMessage(Object error) {
    if (error is Exception) {
      // Strip the leading "Exception: " that Dart inserts on toString().
      final s = error.toString();
      const prefix = 'Exception: ';
      if (s.startsWith(prefix)) return s.substring(prefix.length);
      return s;
    }
    return error.toString();
  }
}

// ---------------------------------------------------------------------------
// Default toaster
// ---------------------------------------------------------------------------

void _defaultToaster(BuildContext context, WpToastType type, String message) {
  WpToast.show(context, message: message, type: type);
}
