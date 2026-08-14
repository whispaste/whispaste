import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import 'number_transforms.dart';
import 'recording_store.dart';

/// Turns a trigger phrase into a regex fragment that matches regardless of
/// which non-letter/non-digit glue dictation put between its words: a single
/// space, a doubled space (e.g. from a stray extra space when the trigger
/// itself was typed/dictated), a hyphen, an em/en dash, or any run of those.
/// Mirrors the `[^\p{L}\p{N}]+` normalization already used for Snippet-Picker
/// exact-match triggers in `exact_match_normalization.dart` — same
/// dictation-inconsistency problem, so the same tolerance.
String _flexibleTriggerPattern(String trigger) {
  final parts = trigger
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((p) => p.isNotEmpty)
      .map(RegExp.escape);
  return parts.join(r'[^\p{L}\p{N}]+');
}

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
        for (final r in replacements) {
          if (r.triggers.isEmpty) continue;
          // All of a replacement's triggers are matched in one alternation
          // pass against the untouched transcript segment — matching them
          // one at a time would let a later trigger match text just
          // inserted by an earlier one (e.g. triggers "omw"/"way" both
          // firing on replacement "on my way").
          final sortedTriggers = [...r.triggers]
            ..sort((a, b) => b.length.compareTo(a.length));
          final alternation = sortedTriggers
              .map(_flexibleTriggerPattern)
              .join('|');
          // Boundaries are "not a letter/digit" rather than an explicit
          // punctuation whitelist, so quotes, parens, dashes, and other
          // punctuation around the trigger don't block the match (only a
          // literal space/line-start/line-end used to be accepted).
          final pattern = RegExp(
            r'(?<![\p{L}\p{N}])(?:' + alternation + r')(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          );
          // Collapse accidental doubled spaces in the authored replacement
          // text (e.g. a stray extra space typed/dictated into the field) —
          // but only runs of the plain space character, so an intentionally
          // multi-line replacement (e.g. a signature) keeps its newlines.
          final replacementText = r.row.replacement.replaceAll(
            RegExp(' {2,}'),
            ' ',
          );
          processedTranscript = processedTranscript.replaceAll(
            pattern,
            replacementText,
          );
        }
      } on Exception {
        // Non-fatal: save raw transcript if replacements fail.
        processedTranscript = input.transcript;
      }
    }

    // 2. Zahlen-Modus: digits-only transform, after replacements (which
    // match on number words) but before the title/persist step below, so
    // the persisted history entry already reflects it (D1). All-or-nothing
    // — falls back to the replacement-applied text unchanged if the
    // transcript isn't fully convertible.
    if (input.numericOnlyMode) {
      processedTranscript =
          toNumericOnly(processedTranscript) ?? processedTranscript;
    }

    // 3. Derive title: trim, then cut at last word boundary within 60 chars.
    final trimmed = processedTranscript.trim();
    final String title;
    if (trimmed.length <= 60) {
      title = trimmed;
    } else {
      final cut = trimmed.substring(0, 60);
      final lastSpace = cut.lastIndexOf(' ');
      title = lastSpace > 20 ? '${cut.substring(0, lastSpace)}…' : '$cut…';
    }

    // 4. Save history entry. insertHistoryEntry (not upsertEntry) is the
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

    // 5. Record daily stat.
    await _db.recordDailyStat(
      timestamp: now,
      model: input.modelId,
      isLocal: input.isLocal,
      durationSec: input.audioDuration.inSeconds.toDouble(),
      processingDurationSec: input.processingDurationSec.toDouble(),
      wordCount: input.wordCount,
      costUsd: 0,
    );

    // 6. Trim to max entries (0 = unlimited). Skipped along with the insert
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
