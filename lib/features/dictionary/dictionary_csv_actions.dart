/// CSV import and export for the replacement list.
///
/// Import: size check before reading, decode, parse, then a review page that
/// plans the write against the current list. Only the plan the user confirms
/// is written, in one transaction.
/// Export writes the current list to a file the user picks.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../services/dictionary/replacement_csv.dart';
import '../../services/dictionary/replacement_import_plan.dart';
import '../../widgets/toast.dart';
import '../replacements/replacements_page.dart';
import '../replacements/vocabulary_import_review_page.dart';
import 'dictionary_csv_preview_page.dart';

const _csvTypeGroup = XTypeGroup(
  label: 'CSV',
  extensions: ['csv'],
  uniformTypeIdentifiers: ['public.comma-separated-values-text'],
);

/// Reads the current list before the file dialog opens: an empty list would
/// let duplicates through (UIA-DIC-02). A failed read is reported and returns
/// null, which stops the import.
Future<List<Replacement>?> _readExisting(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    return await ref.read(replacementsProvider.future);
  } on Object {
    if (context.mounted) {
      WpToast.show(
        context,
        message: L10n.of(context).errorGeneric,
        type: WpToastType.error,
      );
    }
    return null;
  }
}

Future<void> importReplacementsCsv(BuildContext context, WidgetRef ref) async {
  final l10n = L10n.of(context);
  final existing = await _readExisting(context, ref);
  if (existing == null) return;
  final file = await openFile(acceptedTypeGroups: const [_csvTypeGroup]);
  if (file == null || !context.mounted) return;

  final String? text;
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
    text = decodeReplacementsCsvBytes(await file.readAsBytes());
  } on Object {
    if (!context.mounted) return;
    WpToast.show(
      context,
      message: l10n.dictionaryCsvImportReadError,
      type: WpToastType.error,
    );
    return;
  }
  if (!context.mounted) return;
  if (text == null) {
    WpToast.show(
      context,
      message: l10n.dictionaryCsvImportEncodingError,
      type: WpToastType.error,
    );
    return;
  }

  final result = parseReplacementsCsv(text);
  if (!context.mounted) return;
  final refusal = result.refusal;
  if (refusal != null) {
    WpToast.show(
      context,
      message: switch (refusal) {
        ReplacementCsvRefusal.unsupportedFormat =>
          l10n.dictionaryCsvRefusedFormat,
        ReplacementCsvRefusal.unsupportedType => l10n.dictionaryCsvRefusedType,
      },
      type: WpToastType.error,
    );
    return;
  }
  if (result.rows.isEmpty && result.errors.isEmpty) {
    WpToast.show(
      context,
      message: l10n.dictionaryCsvImportNothing,
      type: WpToastType.error,
    );
    return;
  }

  final confirmed = await Navigator.of(context).push<ReplacementImportPlan>(
    MaterialPageRoute(
      builder: (_) => DictionaryCsvPreviewPage(
        result: result,
        existing: [
          for (final r in existing)
            ReplacementImportExisting(
              id: r.id,
              triggers: r.triggers,
              replacement: r.replacement,
              matchMode: r.matchMode,
              fuzzyThreshold: r.fuzzyThreshold,
            ),
        ],
      ),
    ),
  );
  if (confirmed == null || confirmed.writeCount == 0 || !context.mounted) {
    return;
  }

  // The write is one transaction, so a failure stores none of the rows
  // (UIA-DIC-10); say so instead of leaving the user without feedback.
  try {
    await ref.read(replacementsProvider.notifier).applyImportPlan(confirmed);
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
    message: l10n.dictionaryCsvImportDone(confirmed.writeCount),
    type: WpToastType.success,
  );
}

/// The label an entry is listed under in the export selection. Entries with
/// the same label are one group and are exported together.
String _exportLabel(Replacement r) =>
    '${r.triggers.join(' | ')} → ${r.replacement}';

Future<void> exportReplacementsCsv(
  BuildContext context,
  List<Replacement> items,
) async {
  final l10n = L10n.of(context);
  final groups = <String, List<Replacement>>{};
  for (final r in items) {
    (groups[_exportLabel(r)] ??= []).add(r);
  }
  final labels = groups.keys.toList();
  final selected = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => VocabularyImportReviewPage(
        candidates: labels,
        initialSelection: labels.toSet(),
        title: l10n.dictionaryCsvExportSelectTitle,
        subtitleBuilder: l10n.dictionaryCsvExportSelectSubtitle,
        confirmLabelBuilder: l10n.dictionaryCsvExportConfirm,
      ),
    ),
  );
  if (selected == null || selected.isEmpty || !context.mounted) return;

  final chosen = [for (final label in selected) ...?groups[label]];
  if (chosen.length > replacementCsvMaxRows) {
    WpToast.show(
      context,
      message: l10n.dictionaryCsvExportTooMany(chosen.length),
      type: WpToastType.error,
    );
    return;
  }
  final location = await getSaveLocation(
    acceptedTypeGroups: const [_csvTypeGroup],
    suggestedName: 'whispaste-woerterbuch.csv',
  );
  if (location == null || !context.mounted) return;

  final fileName = location.path.split(RegExp(r'[\\/]')).last;
  final rows = [
    for (final r in chosen)
      ReplacementCsvRow(
        triggers: r.triggers,
        replacement: r.replacement,
        matchMode: r.matchMode,
        fuzzyThreshold: r.fuzzyThreshold,
      ),
  ];
  final text = encodeReplacementsCsv(
    rows,
    meta: ReplacementCsvMeta(
      name: sanitizeReplacementPackageName(
        fileName.replaceFirst(RegExp(r'\.csv$', caseSensitive: false), ''),
      ),
      created: DateTime.now(),
    ),
  );
  if (utf8.encode(text).length > replacementCsvMaxBytes) {
    if (!context.mounted) return;
    WpToast.show(
      context,
      message: l10n.dictionaryCsvExportTooMany(rows.length),
      type: WpToastType.error,
    );
    return;
  }
  await writeReplacementsCsv(context, location.path, text, rows.length);
}

/// Writes the encoded [text] of [count] entries to [path] and reports either
/// outcome in a toast. A failed write (folder gone, no permission, disk full)
/// is said out loud rather than letting the user believe the export worked
/// (UIA-DIC-09).
Future<void> writeReplacementsCsv(
  BuildContext context,
  String path,
  String text,
  int count,
) async {
  final l10n = L10n.of(context);
  try {
    await File(path).writeAsString(text);
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
    message: l10n.dictionaryCsvExportDone(count),
    type: WpToastType.success,
  );
}
