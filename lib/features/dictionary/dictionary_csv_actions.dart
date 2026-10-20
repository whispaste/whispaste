/// CSV import and export for the replacement list.
///
/// Import: size check before reading, parse, then a review page. Only the
/// rows the user confirms there are added, appended to the existing list.
/// Export writes the current list to a file the user picks.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../services/dictionary/replacement_csv.dart';
import '../../services/dictionary/replacement_duplicates.dart';
import '../../widgets/toast.dart';
import '../replacements/replacements_page.dart';
import 'dictionary_csv_preview_page.dart';

const _csvTypeGroup = XTypeGroup(
  label: 'CSV',
  extensions: ['csv'],
  uniformTypeIdentifiers: ['public.comma-separated-values-text'],
);

Future<void> importReplacementsCsv(BuildContext context, WidgetRef ref) async {
  final l10n = L10n.of(context);
  // Duplicate detection needs the current triggers. If they cannot be read,
  // stop before the file dialog: an empty list would let duplicates through
  // (UIA-DIC-02).
  final List<Replacement> existing;
  try {
    existing = await ref.read(replacementsProvider.future);
  } on Object {
    if (!context.mounted) return;
    WpToast.show(context, message: l10n.errorGeneric, type: WpToastType.error);
    return;
  }
  final file = await openFile(acceptedTypeGroups: const [_csvTypeGroup]);
  if (file == null || !context.mounted) return;

  final String text;
  try {
    if (await file.length() > replacementCsvMaxBytes) {
      if (!context.mounted) return;
      WpToast.show(
        context,
        message: l10n.dictionaryCsvImportTooLarge,
        type: WpToastType.error,
      );
      return;
    }
    text = await file.readAsString();
  } on Object {
    if (!context.mounted) return;
    WpToast.show(
      context,
      message: l10n.dictionaryCsvImportReadError,
      type: WpToastType.error,
    );
    return;
  }

  final result = parseReplacementsCsv(text);
  if (!context.mounted) return;
  if (result.rows.isEmpty && result.errors.isEmpty) {
    WpToast.show(
      context,
      message: l10n.dictionaryCsvImportNothing,
      type: WpToastType.error,
    );
    return;
  }

  final existingKeys = {
    for (final r in existing)
      for (final t in r.triggers) normalizeTriggerKey(t),
  };
  final confirmed = await Navigator.of(context).push<List<ReplacementCsvRow>>(
    MaterialPageRoute(
      builder: (_) => DictionaryCsvPreviewPage(
        result: result,
        existingTriggerKeys: existingKeys,
      ),
    ),
  );
  if (confirmed == null || confirmed.isEmpty || !context.mounted) return;

  // The write is one transaction, so a failure stores none of the rows
  // (UIA-DIC-10); say so instead of leaving the user without feedback.
  try {
    await ref.read(replacementsProvider.notifier).addAll([
      for (final row in confirmed)
        (
          triggers: row.triggers,
          replacement: row.replacement,
          matchMode: row.matchMode,
          fuzzyThreshold: row.fuzzyThreshold,
        ),
    ]);
  } catch (_) {
    if (context.mounted) {
      WpToast.show(
        context,
        message: l10n.errorGeneric,
        type: WpToastType.error,
      );
    }
    return;
  }
  if (!context.mounted) return;
  WpToast.show(
    context,
    message: l10n.dictionaryCsvImportDone(confirmed.length),
    type: WpToastType.success,
  );
}

Future<void> exportReplacementsCsv(
  BuildContext context,
  List<Replacement> items,
) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [_csvTypeGroup],
    suggestedName: 'whispaste-woerterbuch.csv',
  );
  if (location == null || !context.mounted) return;

  final rows = [
    for (final r in items)
      ReplacementCsvRow(
        triggers: r.triggers,
        replacement: r.replacement,
        matchMode: r.matchMode,
        fuzzyThreshold: r.fuzzyThreshold,
      ),
  ];
  await writeReplacementsCsv(context, location.path, rows);
}

/// Writes [rows] to [path] and reports either outcome in a toast. A failed
/// write (folder gone, no permission, disk full) is said out loud rather than
/// letting the user believe the export worked (UIA-DIC-09).
Future<void> writeReplacementsCsv(
  BuildContext context,
  String path,
  List<ReplacementCsvRow> rows,
) async {
  final l10n = L10n.of(context);
  try {
    await File(path).writeAsString(encodeReplacementsCsv(rows));
  } on FileSystemException {
    if (!context.mounted) return;
    WpToast.show(
      context,
      message: l10n.dictionaryCsvExportFailed,
      type: WpToastType.error,
    );
    return;
  }
  if (!context.mounted) return;
  WpToast.show(
    context,
    message: l10n.dictionaryCsvExportDone(rows.length),
    type: WpToastType.success,
  );
}
