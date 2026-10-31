/// Fills an interactive snippet's fields from ONE spoken sentence
/// ("Absage an Frau Krüger, Termin Dienstag") instead of one guided recording
/// per field (`internal-notes`).
///
/// Two stages, both strict about never inventing text:
/// 1. [assignSpokenFieldsByName] — the field names act as anchors
///    ("Name Krüger Termin Dienstag"). Always available, no model.
/// 2. The Smart-Mode text model maps a natural sentence to the fields as
///    JSON; [parseModelFieldAssignment] keeps only values that appear word
///    for word in the sentence. Runs only on this path, never on the
///    dictation path, and only when the model is ready.
///
/// Whatever stays unassigned is left empty for the preview to mark.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../smart_mode/smart_mode_ffi_engine.dart' show smartModeEngineProvider;
import '../smart_mode/smart_mode_text_model.dart';

final _log = AppLogger('SpokenFields');

/// Words that may sit between a field name and its value ("Name ist
/// Krüger"), in every app language. Matched as whole words only.
const _connectorWords = {
  'ist', 'lautet', 'sind', 'gleich', // de
  'is', 'are', 'equals', // en
  'es', 'son', // es
  'é', 'são', // pt
  'это', // ru
  'הוא', 'היא', 'זה', // he
};

/// Punctuation trimmed from both ends of a value: a spoken pause becomes a
/// comma or full stop in the transcript, never part of the field.
final _edgePunctuation = RegExp(r'^[\s,;:.!?=\-–—…]+|[\s,;:.!?=\-–—…]+$');

/// Stage 1: assigns the text after each spoken field name to that field.
///
/// Matching ignores case and punctuation; names may come in any order. A
/// longer name wins over a shorter one it contains ("Nachname" over
/// "Name"). A snippet with a single field takes the whole sentence. A field
/// whose name was not spoken stays empty.
List<String> assignSpokenFieldsByName(List<String> names, String sentence) {
  if (names.isEmpty) return const [];
  if (names.length == 1) return [_clean(sentence)];

  final lower = sentence.toLowerCase();
  final taken = List<bool>.filled(sentence.length, false);
  final hits = <({int field, int start, int end})>[];
  final order = List<int>.generate(names.length, (i) => i)
    ..sort((a, b) => names[b].length.compareTo(names[a].length));
  for (final i in order) {
    final name = names[i].trim().toLowerCase();
    if (name.isEmpty) continue;
    final pattern = RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(name)}(?![\\p{L}\\p{N}])',
      unicode: true,
    );
    for (final m in pattern.allMatches(lower)) {
      if (taken.sublist(m.start, m.end).any((t) => t)) continue;
      for (var k = m.start; k < m.end; k++) {
        taken[k] = true;
      }
      hits.add((field: i, start: m.start, end: m.end));
      break;
    }
  }
  hits.sort((a, b) => a.start.compareTo(b.start));

  final values = List<String>.filled(names.length, '');
  for (var h = 0; h < hits.length; h++) {
    final end = h + 1 < hits.length ? hits[h + 1].start : sentence.length;
    values[hits[h].field] = _dropLeadingConnector(
      _clean(sentence.substring(hits[h].end, end)),
    );
  }
  return values;
}

String _clean(String value) => value.replaceAll(_edgePunctuation, '');

String _dropLeadingConnector(String value) {
  final space = value.indexOf(' ');
  if (space < 0) return value;
  final first = value.substring(0, space).toLowerCase();
  if (!_connectorWords.contains(first)) return value;
  return _clean(value.substring(space + 1));
}

/// System prompt for stage 2. The field names travel as a JSON list so a
/// name with quotes or commas cannot break the instruction.
String spokenFieldsSystemPrompt(List<String> names) =>
    'You fill the fields of a text template from one dictated sentence. '
    'Fields: ${jsonEncode(names)}. '
    'Reply with exactly one JSON object that maps each field name to the '
    'words of the sentence that belong to it. Copy those words exactly as '
    'they appear; never add, translate, correct or invent words. Use an '
    'empty string for a field the sentence says nothing about. Reply with '
    'the JSON object only.';

/// Stage 2 check: reads the model's JSON answer and keeps only what is
/// safe to show.
///
/// Returns null when the answer holds no JSON object at all. Keys that are
/// not field names are dropped; a value is kept only when it is a string
/// that occurs in [sentence] (ignoring case and runs of whitespace), so a
/// model cannot slip in words the user never said. Missing fields are
/// empty strings.
List<String>? parseModelFieldAssignment(
  String output,
  List<String> names,
  String sentence,
) {
  final start = output.indexOf('{');
  final end = output.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(output.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final byName = {
    for (final e in decoded.entries)
      e.key.toString().trim().toLowerCase(): e.value,
  };
  final haystack = _normalize(sentence);
  return [
    for (final name in names)
      switch (byName[name.trim().toLowerCase()]) {
        final String v
            when _clean(v).isNotEmpty &&
                haystack.contains(_normalize(_clean(v))) =>
          _clean(v),
        _ => '',
      },
  ];
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// How long stage 2 may take before stage 1's result is used instead. Covers
/// a cold load of the local model; the overlay shows that work is going on
/// and Escape cancels.
const kSpokenFieldsModelTimeout = Duration(seconds: 20);

/// Outcome of [SpokenFieldsAssigner.assign].
class SpokenFieldsResult {
  const SpokenFieldsResult({required this.values, required this.modelReady});

  /// One value per field name, in field order; empty when unassigned.
  final List<String> values;

  /// Whether a text model was available. Without one, the preview tells the
  /// user to speak the field names along.
  final bool modelReady;
}

/// Runs both stages: stage 1 first (instant); the model only when stage 1
/// left a field empty and the model is ready. Per field, a model value wins
/// over the stage-1 value; a model failure or timeout falls back to stage 1.
class SpokenFieldsAssigner {
  SpokenFieldsAssigner(this._ref);

  final Ref _ref;

  /// Overridable in tests instead of waiting [kSpokenFieldsModelTimeout].
  Duration timeout = kSpokenFieldsModelTimeout;

  Future<SpokenFieldsResult> assign(List<String> names, String sentence) async {
    final byName = assignSpokenFieldsByName(names, sentence);
    final modelReady =
        _ref.read(smartModeTextModelStatusProvider) ==
        SmartModeTextModelStatus.ready;
    if (!modelReady || byName.every((v) => v.isNotEmpty)) {
      return SpokenFieldsResult(values: byName, modelReady: modelReady);
    }

    final engine = _ref.read(smartModeEngineProvider);
    try {
      final output = await engine
          .run(
            systemPrompt: spokenFieldsSystemPrompt(names),
            userText: sentence,
          )
          .timeout(timeout);
      final fromModel = parseModelFieldAssignment(output, names, sentence);
      if (fromModel == null) {
        _log.info('Model answer held no field object, using field names');
        return SpokenFieldsResult(values: byName, modelReady: true);
      }
      return SpokenFieldsResult(
        values: [
          for (var i = 0; i < names.length; i++)
            fromModel[i].isNotEmpty ? fromModel[i] : byName[i],
        ],
        modelReady: true,
      );
    } catch (e) {
      // Timeout or engine error: stop the generation and keep stage 1.
      if (e is TimeoutException) unawaited(engine.cancel());
      _log.info('Model field assignment failed, using field names', e);
      return SpokenFieldsResult(values: byName, modelReady: true);
    }
  }
}

final spokenFieldsAssignerProvider = Provider<SpokenFieldsAssigner>(
  SpokenFieldsAssigner.new,
);
