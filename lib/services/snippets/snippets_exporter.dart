/// Export flow for a selection of snippets (Textbausteine multi-select).
///
/// Same shape as `notes_exporter.dart`: format picker (txt/md/json), native
/// save dialog (a cancel is silent), [ExportService.export], then a notice on
/// the Textbausteine page. A snippet has no duration, language or cost, so the
/// tabular formats (csv/docx) would be oddly shaped and are not offered.
library;

import 'package:flutter/widgets.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../features/history/data/export_service.dart';
import '../../widgets/export_format_picker.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_page_notice.dart';
import '../history/history_exporter.dart'
    show ExportFn, ExportSaveLocationFn, pickExportSaveLocation;

final _log = AppLogger('SnippetsExporter');

/// Formats offered for snippets.
const List<ExportFormat> snippetsExportFormats = [
  ExportFormat.txt,
  ExportFormat.md,
  ExportFormat.json,
];

/// What the exporter needs of a snippet (decouples it from the page's model).
typedef SnippetExportRow = ({
  String id,
  String title,
  String body,
  DateTime changedAt,
});

typedef SnippetsFormatPickerFn =
    Future<ExportFormat?> Function(BuildContext context);

typedef SnippetsNoticeFn =
    void Function(
      BuildContext context, {
      required bool failed,
      required String message,
    });

Future<ExportFormat?> _pickFormat(BuildContext context) =>
    showWpExportFormatPicker(context, formats: snippetsExportFormats);

/// Orchestrates the export of [rows]. Returns `true` when a file was written.
class SnippetsExporter {
  const SnippetsExporter({
    this.pickerFn = _pickFormat,
    this.exporter = ExportService.export,
    this.saveLocationFn = pickExportSaveLocation,
    this.notifier = _defaultNotifier,
  });

  final SnippetsFormatPickerFn pickerFn;
  final ExportFn exporter;
  final ExportSaveLocationFn saveLocationFn;
  final SnippetsNoticeFn notifier;

  Future<bool> exportSnippets(
    BuildContext context,
    List<SnippetExportRow> rows,
  ) async {
    if (rows.isEmpty) return false;
    final format = await pickerFn(context);
    if (format == null || !context.mounted) return false;

    final entries = [
      for (final r in rows)
        ExportEntry(
          id: r.id,
          title: r.title,
          text: r.body,
          timestamp: r.changedAt.toIso8601String(),
        ),
    ];
    final path = await saveLocationFn(
      format: format,
      suggestedName: ExportService.defaultFilename(entries, format),
    );
    if (path == null || !context.mounted) return false;

    try {
      await exporter(entries, format, path);
      if (!context.mounted) return true;
      notifier(
        context,
        failed: false,
        message: L10n.of(context).historyExportDone(path),
      );
      return true;
    } catch (e) {
      _log.warning('Snippets export failed: $e');
      if (!context.mounted) return false;
      notifier(
        context,
        failed: true,
        message: L10n.of(context).historyExportFailed,
      );
      return false;
    }
  }
}

void _defaultNotifier(
  BuildContext context, {
  required bool failed,
  required String message,
}) {
  showWpPageNotice(
    context,
    page: WpNoticePage.snippets,
    notice: WpPageNotice(
      id: failed ? 'snippets-export-failed' : 'snippets-export-done',
      message: message,
      tone: failed ? WpBannerTone.error : WpBannerTone.info,
      autoDismiss: failed ? null : const Duration(seconds: 4),
    ),
  );
}
