/// Orchestrates the vocabulary-import feature (PRD.md
/// `.scratch/vocabulary-fuzzy-replacements/PRD.md`): pick a folder, scan it
/// locally and offline for probable identifiers, and add each new one as a
/// fuzzy replacement entry (`origin: imported`).
library;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../../core/data/database.dart';
import 'text_replacement_matcher.dart'
    show fuzzyMinTriggerLength, fuzzyThresholdStrict;
import 'vocabulary_import_scanner.dart';

/// Files above this size are skipped -- a vocabulary source file is source
/// code, not a data dump; a huge match here is far more likely a generated
/// artifact than something worth scanning for identifiers.
const int vocabularyImportMaxFileSizeBytes = 2 * 1024 * 1024;

/// The fuzzy threshold applied to every imported entry. Deliberately
/// "Strict", not the UI's "Standard" default: an imported entry was never
/// reviewed by a human before being turned into a live replacement rule, so
/// it needs a wider safety margin than something a user typed in by hand.
/// (Incident: a scan of vendored/generated build output imported thousands
/// of noise tokens at the "Standard" threshold; several were one edit away
/// from ordinary short words and silently corrupted unrelated dictation --
/// see `.scratch/vocabulary-fuzzy-replacements/`.)
const double vocabularyImportDefaultFuzzyThreshold = fuzzyThresholdStrict;

/// Identifiers shorter than this are never imported -- short tokens are
/// exactly the ones a fuzzy match can confuse with an unrelated ordinary
/// word (a single edit away), so they carry the worst risk-to-value ratio
/// of anything the scanner finds. [fuzzyMinTriggerLength] alone is not
/// sufficient here: it stops a short trigger from firing but does not stop
/// it from being *imported* in the first place.
const int vocabularyImportMinIdentifierLength = fuzzyMinTriggerLength + 2;

/// Opens the native directory chooser. Returns the chosen path, or `null` if
/// the user cancels. Same shape as `AutosaveFolderPickFn`
/// (`settings_autosave_folder_chooser.dart`) -- kept as its own typedef here
/// rather than importing that file, since the two features share no other
/// coupling.
typedef VocabularyImportFolderPickFn =
    Future<String?> Function({String? initialDirectory});

/// Runs identifier extraction; the production default dispatches to
/// [compute] (a background isolate, PRD.md "Scan läuft asynchron/isoliert")
/// so a large project scan does not block the UI. Injectable so tests can
/// run it inline instead of paying real isolate spin-up cost.
typedef VocabularyExtractFn =
    Future<Set<String>> Function(Map<String, String> filesByPath);

/// Result of a scan: candidate identifiers that are not yet a replacement
/// trigger, ready for the user to pick from before anything is written to
/// the database. `candidates` is sorted alphabetically for a stable,
/// scrollable review list.
class VocabularyImportScanResult {
  const VocabularyImportScanResult({
    required this.candidates,
    required this.skipped,
  });

  final List<String> candidates;

  /// Candidates found during the scan that already match an existing
  /// trigger and were therefore excluded from [candidates] up front.
  final int skipped;
}

class VocabularyImportService {
  VocabularyImportService({
    FileSystem? fileSystem,
    this.pickFolder = _defaultPickFolder,
    VocabularyExtractFn? extract,
  }) : fileSystem = fileSystem ?? const LocalFileSystem(),
       extract = extract ?? _defaultExtract;

  final FileSystem fileSystem;
  final VocabularyImportFolderPickFn pickFolder;
  final VocabularyExtractFn extract;

  /// Scans [folderPath] for candidate identifiers without writing anything
  /// to the database -- the user reviews and picks a subset from
  /// [VocabularyImportScanResult.candidates] before [commit] runs. Existing
  /// triggers (manual or previously imported) are excluded up front, since
  /// re-offering them for import would just be noise in the review list.
  Future<VocabularyImportScanResult> scan(
    String folderPath,
    HistoryDatabase db,
  ) async {
    final filesByPath = await _readSourceFiles(folderPath);
    final rawCandidates = await extract(filesByPath);
    final candidates = rawCandidates
        .where((c) => c.length >= vocabularyImportMinIdentifierLength)
        .toSet();

    final existing = await db.readAllReplacements();
    final existingTriggers = <String>{for (final r in existing) ...r.triggers};
    final diff = computeImportDiff(candidates, existingTriggers);

    return VocabularyImportScanResult(
      candidates: diff.toInsert,
      skipped: diff.skipped,
    );
  }

  /// Writes exactly the user-selected [terms] as fuzzy replacement entries
  /// (trigger == replacement == the identifier, so a mis-transcribed
  /// near-variant is corrected back to its exact spelling). Nothing here is
  /// re-checked against existing triggers -- that already happened in
  /// [scan], and the list the user reviewed came from its result.
  Future<int> commit(List<String> terms, HistoryDatabase db) async {
    final now = DateTime.now();
    for (var i = 0; i < terms.length; i++) {
      final term = terms[i];
      await db.upsertReplacementWithTriggers(
        id: '${now.microsecondsSinceEpoch}_import_$i',
        triggers: [term],
        replacement: term,
        createdAt: now,
        matchMode: 'fuzzy',
        fuzzyThreshold: vocabularyImportDefaultFuzzyThreshold,
        origin: 'imported',
      );
    }
    return terms.length;
  }

  /// Walks [folderPath] manually rather than via `dir.list(recursive: true)`
  /// -- a flat recursive listing enumerates an ignored directory's entire
  /// subtree before this method ever sees the entries to filter them out.
  /// Pruning at each directory boundary instead means `.git`/`node_modules`/
  /// `build` (etc., see [vocabularyImportIgnoredDirNames]) are never opened
  /// at all, which is what makes pointing this at a real project's root a
  /// scan of megabytes rather than gigabytes.
  Future<Map<String, String>> _readSourceFiles(String folderPath) async {
    final result = <String, String>{};
    final root = fileSystem.directory(folderPath);
    if (!await root.exists()) return result;

    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on Exception {
        // Unreadable directory (permissions, race with deletion) -- skip it,
        // not the whole scan.
        continue;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          if (!vocabularyImportIgnoredDirNames.contains(
            p.basename(entity.path),
          )) {
            pending.add(entity);
          }
          continue;
        }
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!vocabularyImportSourceExtensions.contains(ext)) continue;
        try {
          final size = await entity.length();
          if (size > vocabularyImportMaxFileSizeBytes) continue;
          result[entity.path] = await entity.readAsString();
        } on Exception {
          // Unreadable or non-UTF8 (likely binary despite the extension) --
          // skip rather than fail the whole scan.
          continue;
        }
      }
    }
    return result;
  }
}

Future<String?> _defaultPickFolder({String? initialDirectory}) {
  return file_selector.getDirectoryPath(initialDirectory: initialDirectory);
}

Future<Set<String>> _defaultExtract(Map<String, String> filesByPath) =>
    compute(extractIdentifiers, filesByPath);
