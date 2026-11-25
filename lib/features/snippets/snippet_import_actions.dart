// loam-ignore: circular-dependencies – the import reads and writes snippetsProvider, which lives in snippets_page.dart; moving the provider out is left until after the release
/// File import for snippets (#665).
///
/// Size check before reading, strict UTF-8 decode, parse, then a review page
/// that plans the write against the active snippets. Only the plan the user
/// confirms is written, in one transaction. The trash is never touched.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../services/snippets/snippet_file.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_page_notice.dart';
import 'snippet_import_preview_page.dart';
import 'snippets_page.dart';

const _snippetFileTypeGroup = XTypeGroup(
  label: 'Markdown / JSON',
  extensions: ['md', 'markdown', 'json'],
  uniformTypeIdentifiers: ['net.daringfireball.markdown', 'public.json'],
);

/// Whether [fileName] has an extension the import reads. Drag and drop uses
/// it to pick the first usable file of a drop.
bool isSnippetImportFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.md') ||
      lower.endsWith('.markdown') ||
      lower.endsWith('.json');
}

/// The active snippets as the import planner compares against them. Pass
/// only active snippets: the trash is never a conflict and never changed.
List<SnippetImportExisting> snippetImportExisting(List<SnippetItem> active) => [
  for (final s in active)
    (
      id: s.id,
      entry: SnippetFileEntry(
        title: s.title,
        body: s.body,
        kind: s.kind,
        fields: s.fields,
      ),
    ),
];

void _fail(BuildContext context, String id, String message, [String? next]) =>
    showWpPageNotice(
      context,
      page: WpNoticePage.snippets,
      notice: WpPageNotice(id: id, message: message, nextStep: next),
    );

void _result(BuildContext context, String id, String message) =>
    showWpPageNotice(
      context,
      page: WpNoticePage.snippets,
      notice: WpPageNotice(id: id, message: message, tone: WpBannerTone.info),
    );

/// Imports a snippet file. Without [file] a file dialog opens; with [file]
/// (a dropped file) that file is read directly.
Future<void> importSnippetsFile(
  BuildContext context,
  WidgetRef ref, {
  XFile? file,
}) async {
  final l10n = L10n.of(context);
  // Read the library before the dialog opens: an empty list would let
  // duplicates through.
  final List<SnippetItem> existing;
  try {
    existing = await ref.read(snippetsProvider.future);
  } on Object {
    if (context.mounted) {
      _fail(context, 'snippets-import-list-failed', l10n.errorGeneric);
    }
    return;
  }
  if (!context.mounted) return;
  final picked =
      file ?? await openFile(acceptedTypeGroups: const [_snippetFileTypeGroup]);
  if (picked == null || !context.mounted) return;

  final String text;
  try {
    if (await picked.length() > snippetFileMaxBytes) {
      if (!context.mounted) return;
      _fail(context, 'snippets-import-too-large', l10n.snippetsImportTooLarge);
      return;
    }
    text = utf8.decode(await picked.readAsBytes());
  } on Object {
    // Unreadable file or bytes that are not UTF-8: both are a file the
    // import cannot use, with the same next step.
    if (!context.mounted) return;
    _fail(
      context,
      'snippets-import-read-failed',
      l10n.snippetsImportReadError,
      l10n.snippetsImportNextPickFile,
    );
    return;
  }
  if (!context.mounted) return;

  final result = parseSnippetFile(text, snippetFileTypeFor(picked.name, text));
  final refusal = result.refusal;
  if (refusal != null) {
    _fail(context, 'snippets-import-refused', switch (refusal) {
      SnippetFileRefusal.unsupportedFormat => l10n.snippetsImportRefusedFormat,
      SnippetFileRefusal.unsupportedVersion =>
        l10n.snippetsImportRefusedVersion,
    }, l10n.snippetsImportNextPickFile);
    return;
  }
  if (result.entries.isEmpty && result.errors.isEmpty) {
    _fail(
      context,
      'snippets-import-nothing',
      l10n.snippetsImportNothing,
      l10n.snippetsImportNextPickFile,
    );
    return;
  }

  final confirmed = await Navigator.of(context).push<SnippetImportPlan>(
    MaterialPageRoute(
      builder: (_) => SnippetImportPreviewPage(
        result: result,
        existing: snippetImportExisting(existing),
      ),
    ),
  );
  if (confirmed == null || !context.mounted) return;
  final found = result.entries.length + result.errors.length;
  if (confirmed.writeCount > 0) {
    // One transaction: a failure stores none of the snippets.
    try {
      await ref
          .read(snippetsProvider.notifier)
          .importSnippets(confirmed.writes);
    } on Object {
      if (context.mounted) {
        _fail(context, 'snippets-import-write-failed', l10n.errorGeneric);
      }
      return;
    }
    if (!context.mounted) return;
  }
  _result(
    context,
    'snippets-import-result',
    l10n.snippetsImportResult(
      found,
      confirmed.writeCount,
      found - confirmed.writeCount,
    ),
  );
}
