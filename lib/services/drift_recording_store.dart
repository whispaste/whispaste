import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import '../features/history/data/history_title.dart';
import 'recording_store.dart';
import 'replacements/text_replacement_matcher.dart';
import 'smart_mode/smart_mode_fact_guard.dart';

/// Converts DB rows into the pure matcher's input shape (also used by
/// the headless `--transcribe-file --replacements` mode).
List<TextReplacementRule> textReplacementRulesFrom(
  List<ReplacementWithTriggers> rows,
) => [
  for (final r in rows)
    TextReplacementRule(
      triggers: r.triggers,
      replacement: r.row.replacement,
      matchMode: r.row.matchMode == 'fuzzy'
          ? TextReplacementMatchMode.fuzzy
          : TextReplacementMatchMode.exact,
      fuzzyThreshold: r.row.fuzzyThreshold,
    ),
];

final _usageLog = AppLogger('DictionaryUsage');

/// [RecordingStore] backed by the Drift SQLite database.
/// Compiled replacement rules, reused while the rule list is unchanged.
final _replacementRulesCache = CompiledRulesCache();

class DriftRecordingStore implements RecordingStore {
  const DriftRecordingStore(this._db);

  final HistoryDatabase _db;

  /// Counts this save's changes per dictionary entry (matrix 4.5). Fire and
  /// forget: the write must never delay the save, and a failed counter
  /// update only loses a count, never the dictation.
  void _recordReplacementUsage(
    List<ReplacementWithTriggers> replacements,
    List<int> hits,
  ) {
    final usage = <String, int>{
      for (var i = 0; i < replacements.length; i++)
        if (hits[i] > 0) replacements[i].row.id: hits[i],
    };
    if (usage.isEmpty) return;
    unawaited(
      _db.addReplacementUsage(usage).catchError((Object error) {
        _usageLog.warning('Could not record replacement usage: $error');
      }),
    );
  }

  @override
  Future<List<String>> dictionaryTerms() async {
    try {
      final replacements = await _db.readAllReplacements();
      return dictionaryNameTerms([
        for (final r in replacements) r.row.replacement,
      ]);
    } on Exception catch (e) {
      // Content-free on purpose: the error text may echo dictionary entries.
      _usageLog.debug('Dictionary terms unavailable: ${e.runtimeType}');
      return const <String>[];
    }
  }

  @override
  Future<String> applyReplacements(String text) async {
    try {
      final replacements = await _db.readAllReplacements();
      final rules = textReplacementRulesFrom(replacements);
      final hits = List<int>.filled(rules.length, 0);
      final replaced = _replacementRulesCache
          .forRules(rules)
          .apply(text, hits: hits);
      _recordReplacementUsage(replacements, hits);
      return replaced;
    } on Exception {
      // Non-fatal: keep the text as it is if replacements fail.
      return text;
    }
  }

  @override
  Future<SavedRecording> save(RecordingInput input) async {
    final now = input.createdAt ?? DateTime.now();
    final id = input.entryId ?? newRecordingEntryId(now);

    // 1. Apply text replacements (best-effort; non-fatal if it fails).
    var processedTranscript = input.transcript;
    if (input.applyTextReplacements) {
      processedTranscript = await applyReplacements(processedTranscript);
    }

    // 2. Derive title (shared with the "Edit transcript" re-derivation in
    // HistoryDetailNotifier.updateContent, issue 02).
    final title = deriveHistoryTitle(processedTranscript);

    // 3. Save history entry. insertHistoryEntry (not upsertEntry) is the
    // real creation path — it also draws this entry's decorative color slot
    // atomically with the insert (see database.dart). Skipped for a quick
    // note (input.insertHistoryEntry == false): it already lives in Notes
    // and must not also appear in Verlauf.
    if (input.insertHistoryEntry) {
      await _db.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: Value(id),
          content: Value(processedTranscript),
          title: Value(title),
          timestamp: Value(now),
          durationSec: Value(input.audioDuration.inSeconds.toDouble()),
          language: Value(input.languageCode),
          model: Value(input.modelId),
          isLocal: Value(input.isLocal),
          source: const Value('dictation'),
          originalTranscript: Value(input.originalTranscript),
          targetApp: Value(input.targetApp),
          smartModeInput: Value(input.smartModeInput),
          smartModeApplied: Value(input.smartModeApplied),
          languageHint: Value(input.detectedLanguage ?? ''),
        ),
      );
    }

    // 4. Record daily stat.
    if (input.recordDailyStat) {
      await _db.recordDailyStat(
        timestamp: now,
        model: input.modelId,
        isLocal: input.isLocal,
        durationSec: input.audioDuration.inSeconds.toDouble(),
        processingDurationSec: input.processingDurationSec.toDouble(),
        wordCount: input.wordCount,
        costUsd: 0,
      );
    }

    // 5. Trim to max entries (0 = unlimited). Skipped along with the insert
    // above — nothing was added to trim for.
    final trimmedCount = input.insertHistoryEntry && input.historyMaxEntries > 0
        ? await _db.trimToMaxEntries(input.historyMaxEntries)
        : 0;

    return SavedRecording(
      entryId: id,
      processedTranscript: processedTranscript,
      trimmedCount: trimmedCount,
    );
  }
}

final recordingStoreProvider = Provider<RecordingStore>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return DriftRecordingStore(db);
});

/// Dictionary name terms for the Smart Mode fact guard. A seam so tests need
/// no database.
final factKnownTermsProvider = Provider<Future<List<String>> Function()>(
  (ref) =>
      () => ref.read(recordingStoreProvider).dictionaryTerms(),
);
