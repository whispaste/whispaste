/// Trigger matching and shared open path for the Snippet-Picker
/// (dictation-automations ticket 06; shared-open extraction ticket 26).
///
/// The picker has exactly one global trigger word
/// (`BehaviorSettings.snippetPickerTrigger`), matched via the same
/// [normalizeForExactMatch] comparison used elsewhere for trigger phrases.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import '../../features/snippets/snippets_page.dart' show SnippetItem;
import '../exact_match_normalization.dart' show normalizeForExactMatch;
import 'snippet_picker_service.dart';

final _log = AppLogger('SnippetPickerDispatch');

/// Returns `true` when [transcript] exactly matches [trigger] after
/// [normalizeForExactMatch] normalization.
///
/// An empty (or whitespace-only) [trigger] means the feature is off and
/// never matches; likewise an empty normalized [transcript] never matches
/// (guards against matching on silence).
bool snippetPickerTriggerMatches(String trigger, String transcript) {
  final normalizedTrigger = normalizeForExactMatch(trigger);
  if (normalizedTrigger.isEmpty) return false;
  final normalizedTranscript = normalizeForExactMatch(transcript);
  if (normalizedTranscript.isEmpty) return false;
  return normalizedTrigger == normalizedTranscript;
}

/// Reads every snippet, opens the Snippet-Picker panel, and handles all
/// three [SnippetPickerShowResult] outcomes — including the
/// `info_snippet_picker_empty` signal on [SnippetPickerShowResult.emptyList].
///
/// Shared (ticket 26) by the voice-trigger path
/// (`RecordingOrchestrator._tryDispatchSnippetPicker`, which only checks the
/// trigger word and then calls this) and the systemwide Snippet-Picker
/// hotkey path (`RecordingOrchestrator.openSnippetPickerViaHotkey`). Neither
/// caller builds the item list or handles the three outcomes itself anymore
/// — that would be a second copy of this logic, not a shared one.
///
/// [logId] is only used for log correlation (the voice path passes the
/// recording's session id; the hotkey path has none, so it passes a fixed
/// label instead).
Future<SnippetPickerShowResult> openSnippetPicker(Ref ref, String logId) async {
  try {
    final db = ref.read(historyDatabaseProvider);
    final snippetRows = await db.readAllSnippets();
    final items = [
      for (final row in snippetRows)
        SnippetItem(id: row.id, title: row.title, body: row.body),
    ];

    final result = await ref
        .read(snippetPickerServiceProvider.notifier)
        .show(items: items);
    switch (result) {
      case SnippetPickerShowResult.shown:
        _log.info('[$logId] Snippet-Picker opened');
      case SnippetPickerShowResult.emptyList:
        // Matched/pressed but there is nothing to pick from. Without this
        // info signal that's indistinguishable from "nothing happened" for
        // the user.
        _log.info('[$logId] Snippet-Picker: no snippets exist');
        ref
            .read(recordingInfoProvider.notifier)
            .show('info_snippet_picker_empty');
      case SnippetPickerShowResult.unavailable:
        _log.info('[$logId] Snippet-Picker unavailable on this platform');
    }
    return result;
  } on Exception catch (e) {
    _log.warning('[$logId] Snippet-Picker dispatch failed: $e');
    return SnippetPickerShowResult.unavailable;
  }
}
