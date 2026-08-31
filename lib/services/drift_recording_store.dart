import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import 'recording_store.dart';
import 'replacements/text_replacement_matcher.dart';

/// Converts DB rows into the pure matcher's input shape.
List<TextReplacementRule> _rulesFrom(List<ReplacementWithTriggers> rows) => [
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

/// [RecordingStore] backed by the Drift SQLite database.
class DriftRecordingStore implements RecordingStore {
  const DriftRecordingStore(this._db);

  final HistoryDatabase _db;

  @override
  Future<SavedRecording> save(RecordingInput input) async {
    final now = DateTime.now();
    final id =
        '${now.millisecondsSinceEpoch}-'
        '${math.Random().nextInt(9999).toString().padLeft(4, '0')}';

    // 1. Apply text replacements (best-effort; non-fatal if it fails).
    var processedTranscript = input.transcript;
    if (input.applyTextReplacements) {
      try {
        final replacements = await _db.readAllReplacements();
        processedTranscript = applyTextReplacements(
          processedTranscript,
          _rulesFrom(replacements),
        );
      } on Exception {
        // Non-fatal: save raw transcript if replacements fail.
        processedTranscript = input.transcript;
      }
    }

    // 2. Derive title: trim, then cut at last word boundary within 60 chars.
    final trimmed = processedTranscript.trim();
    final String title;
    if (trimmed.length <= 60) {
      title = trimmed;
    } else {
      final cut = trimmed.substring(0, 60);
      final lastSpace = cut.lastIndexOf(' ');
      title = lastSpace > 20 ? '${cut.substring(0, lastSpace)}…' : '$cut…';
    }

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
        ),
      );
    }

    // 4. Record daily stat.
    await _db.recordDailyStat(
      timestamp: now,
      model: input.modelId,
      isLocal: input.isLocal,
      durationSec: input.audioDuration.inSeconds.toDouble(),
      processingDurationSec: input.processingDurationSec.toDouble(),
      wordCount: input.wordCount,
      costUsd: 0,
    );

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
