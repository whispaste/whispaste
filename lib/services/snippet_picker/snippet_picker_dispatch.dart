/// Trigger dispatch and shared open path for the Snippet-Picker
/// (dictation-automations ticket 06; shared-open extraction ticket 26;
/// direct trigger postprocessing-2026 N3).
///
/// The picker has exactly one global trigger word
/// (`BehaviorSettings.snippetPickerTrigger`). A dictation that is the trigger
/// word alone opens the picker; "`<trigger> <name>`" inserts the matching
/// snippet directly or, when several titles match, opens the picker filtered
/// by the name. A dictation that names no snippet takes the normal pipeline.
/// Routing lives in `snippet_trigger_resolver.dart`.
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
        createdAt: row.row.createdAt,
        updatedAt: row.row.updatedAt,
        kind: row.row.kind,
        fields: row.fields,
      ),
  ];
}

/// What [dispatchSnippetTrigger] did with a dictation.
enum SnippetTriggerDispatch {
  /// Not routed: the dictation takes the normal pipeline (saved and pasted).
  none,

  /// A command, not content: the trigger word alone opened the picker, or a
  /// snippet was inserted directly. Nothing is saved or pasted.
  consumed,

  /// The picker opened for an ambiguous name. Nothing is pasted, but the
  /// dictation is still saved to the history so it is never lost.
  consumedKeepDictation,
}

/// Routes a dictation that may start with the trigger word, see
/// [resolveSnippetTrigger]. Never throws: any failure falls back to the
/// normal pipeline ([SnippetTriggerDispatch.none]), so the dictation is never
/// discarded.
///
/// [logId] is only used for log correlation (the voice path passes the
/// recording's session id).
///
/// [canKeepDictation] is false when nothing would keep the dictation (saving
/// recordings is off). An ambiguous name then takes the normal pipeline and
/// is pasted, instead of opening the picker and losing the text.
Future<SnippetTriggerDispatch> dispatchSnippetTrigger(
  Ref ref,
  String logId,
  String trigger,
  String transcript, {
  bool canKeepDictation = true,
}) async {
  if (!snippetTriggerPrefixMatches(trigger, transcript)) {
    return SnippetTriggerDispatch.none;
  }
  try {
    final items = await readSnippetItems(ref);
    final route = resolveSnippetTrigger(
      trigger: trigger,
      transcript: transcript,
      snippets: [for (final item in items) (id: item.id, title: item.title)],
    );
    switch (route) {
      case SnippetTriggerNone():
        return SnippetTriggerDispatch.none;
      case SnippetTriggerDirect(:final snippetId):
        final snippet = items.firstWhere((item) => item.id == snippetId);
        _log.info('[$logId] Snippet-Trigger: direct insert of ${snippet.id}');
        unawaited(
          ref
              .read(snippetPickerServiceProvider.notifier)
              .insertDirect(snippet)
              .catchError((Object error) {
                _log.warning('[$logId] Snippet direct insert failed: $error');
              }),
        );
        return SnippetTriggerDispatch.consumed;
      case SnippetTriggerPicker(:final query):
        if (query != null && !canKeepDictation) {
          _log.info('[$logId] Snippet-Trigger: ambiguous name, saving off');
          return SnippetTriggerDispatch.none;
        }
        final result = await openSnippetPicker(
          ref,
          logId,
          query: query ?? '',
          items: items,
        );
        if (result != SnippetPickerShowResult.shown) {
          return SnippetTriggerDispatch.none;
        }
        return query == null
            ? SnippetTriggerDispatch.consumed
            : SnippetTriggerDispatch.consumedKeepDictation;
    }
  } on Exception catch (e) {
    _log.warning('[$logId] Snippet-Trigger dispatch failed: $e');
    return SnippetTriggerDispatch.none;
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
