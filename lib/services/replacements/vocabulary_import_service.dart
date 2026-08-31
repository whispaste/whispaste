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
import 'text_replacement_matcher.dart' show fuzzyThresholdStandard;
import 'vocabulary_import_scanner.dart';

/// Files above this size are skipped -- a vocabulary source file is source
/// code, not a data dump; a huge match here is far more likely a generated
/// artifact than something worth scanning for identifiers.
const int vocabularyImportMaxFileSizeBytes = 2 * 1024 * 1024;

/// The standard fuzzy threshold applied to every imported entry (PRD.md
/// User Story 8: "eine sinnvolle Voreinstellung... Standard"). Matches the
/// UI's "Standard" step.
const double vocabularyImportDefaultFuzzyThreshold = fuzzyThresholdStandard;

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

/// Outcome of one import run (PRD.md User Story 15).
class VocabularyImportSummary {
  const VocabularyImportSummary({
    required this.found,
    required this.added,
    required this.skipped,
  });

  final int found;
  final int added;
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

  /// Scans [folderPath] and inserts every genuinely-new identifier as a
  /// fuzzy replacement entry (trigger == replacement == the identifier, so
  /// a mis-transcribed near-variant is corrected back to its exact
  /// spelling). Existing triggers (manual or previously imported) are never
  /// duplicated (PRD.md User Story 10/13).
  Future<VocabularyImportSummary> importFrom(
    String folderPath,
    HistoryDatabase db,
  ) async {
    final filesByPath = await _readSourceFiles(folderPath);
    final candidates = await extract(filesByPath);

    final existing = await db.readAllReplacements();
    final existingTriggers = <String>{for (final r in existing) ...r.triggers};
    final diff = computeImportDiff(candidates, existingTriggers);

    final now = DateTime.now();
    for (var i = 0; i < diff.toInsert.length; i++) {
      final term = diff.toInsert[i];
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

    return VocabularyImportSummary(
      found: candidates.length,
      added: diff.toInsert.length,
      skipped: diff.skipped,
    );
  }

  Future<Map<String, String>> _readSourceFiles(String folderPath) async {
    final dir = fileSystem.directory(folderPath);
    final result = <String, String>{};
    if (!await dir.exists()) return result;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
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
    return result;
  }
}

Future<String?> _defaultPickFolder({String? initialDirectory}) {
  return file_selector.getDirectoryPath(initialDirectory: initialDirectory);
}

Future<Set<String>> _defaultExtract(Map<String, String> filesByPath) =>
    compute(extractIdentifiers, filesByPath);
