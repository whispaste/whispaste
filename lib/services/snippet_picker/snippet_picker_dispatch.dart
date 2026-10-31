/// Trigger dispatch and shared open path for the Snippet-Picker
/// (dictation-automations ticket 06; shared-open extraction ticket 26;
/// direct trigger postprocessing-2026 N3).
///
/// The picker has exactly one global trigger word
/// (`BehaviorSettings.snippetPickerTrigger`). A dictation that is the trigger
/// word alone opens the picker; "`<trigger> <name>`" inserts the matching
/// snippet directly or opens the picker filtered by the name. Routing lives in
/// `snippet_trigger_resolver.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import '../../features/snippets/snippets_page.dart' show SnippetItem;
import 'snippet_picker_service.dart';
import 'snippet_trigger_resolver.dart';

final _log = AppLogger('SnippetPickerDispatch');

/// Reads every snippet as [SnippetItem]s, shared by the trigger path and the
/// systemwide hotkey path.
Future<List<SnippetItem>> readSnippetItems(Ref ref) async {
  final db = ref.read(historyDatabaseProvider);
  final snippetRows = await db.readAllSnippetsWithFields();
  return [
    for (final row in snippetRows)
      SnippetItem(
        id: row.row.id,
        title: row.row.title,
        body: row.row.body,
        kind: row.row.kind,
        fields: row.fields,
      ),
  ];
}

/// Routes a dictation that may start with the trigger word, see
/// [resolveSnippetTrigger]. Returns `true` when the dictation was consumed
/// (picker shown, or a snippet inserted); `false` sends it through the normal
/// pipeline. Never throws: any failure falls back to the normal pipeline, so
/// the dictation is never discarded.
///
/// [logId] is only used for log correlation (the voice path passes the
/// recording's session id).
Future<bool> dispatchSnippetTrigger(
  Ref ref,
  String logId,
  String trigger,
  String transcript,
) async {
  if (!snippetTriggerPrefixMatches(trigger, transcript)) return false;
  try {
    final items = await readSnippetItems(ref);
    final route = resolveSnippetTrigger(
      trigger: trigger,
      transcript: transcript,
      snippets: [for (final item in items) (id: item.id, title: item.title)],
    );
    switch (route) {
      case SnippetTriggerNone():
        return false;
      case SnippetTriggerDirect(:final snippetId):
        final snippet = items.firstWhere((item) => item.id == snippetId);
        _log.info('[$logId] Snippet-Trigger: direct insert of ${snippet.id}');
        unawaited(
          ref.read(snippetPickerServiceProvider.notifier).insertDirect(snippet),
        );
        return true;
      case SnippetTriggerPicker(:final query):
        final result = await openSnippetPicker(
          ref,
          logId,
          query: query ?? '',
          items: items,
        );
        return result == SnippetPickerShowResult.shown;
    }
  } on Exception catch (e) {
    _log.warning('[$logId] Snippet-Trigger dispatch failed: $e');
    return false;
  }
}

/// Reads every snippet, opens the Snippet-Picker panel, and handles all
/// three [SnippetPickerShowResult] outcomes — including the
/// `info_snippet_picker_empty` signal on [SnippetPickerShowResult.emptyList].
///
/// Shared (ticket 26) by the voice-trigger path ([dispatchSnippetTrigger])
/// and the systemwide Snippet-Picker hotkey path
/// (`RecordingOrchestrator.openSnippetPickerViaHotkey`). Neither caller builds
/// the item list or handles the three outcomes itself anymore — that would be
/// a second copy of this logic, not a shared one.
///
/// [query] pre-fills the panel's search field (empty = unfiltered). [items]
/// lets a caller that already read the snippets pass them in.
///
/// [logId] is only used for log correlation (the voice path passes the
/// recording's session id; the hotkey path has none, so it passes a fixed
/// label instead).
Future<SnippetPickerShowResult> openSnippetPicker(
  Ref ref,
  String logId, {
  String query = '',
  List<SnippetItem>? items,
}) async {
  try {
    final snippets = items ?? await readSnippetItems(ref);
    final result = await ref
        .read(snippetPickerServiceProvider.notifier)
        .show(items: snippets, query: query);
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
