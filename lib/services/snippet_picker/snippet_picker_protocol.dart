/// The message shapes shared by the main engine ([SnippetPickerService]) and
/// the picker render engine (`snippet_picker_render_entrypoint.dart`).
///
/// The native shells on all three platforms relay the item maps and the
/// selected id as opaque strings, so new picker modes need no native change:
/// - Items carry a [kSnippetPickerKindKey] that tells the render engine how
///   to show them. A list that starts with a [SnippetPickerItemKind.preview]
///   item is the field preview of "In einem Satz", not a snippet list.
/// - The selected id is either a snippet id, [sentenceSelectionId] (record
///   the interactive snippet in one sentence) or [fillSelectionId] (the
///   preview was confirmed with these field values).
library;

import 'dart:convert';

const kSnippetPickerKindKey = 'kind';

/// Set on the preview item when no text model is ready, so the render engine
/// shows the hint to speak the field names along.
const kSnippetPickerHintKey = 'hint';
const kSnippetPickerHintSpeakFieldNames = 'speakFieldNames';

enum SnippetPickerItemKind {
  /// A static snippet row.
  snippet,

  /// An interactive snippet row: also offers "In einem Satz".
  interactive,

  /// Head of a field preview: title = snippet title, body = template.
  preview,

  /// One field of a field preview: title = field name, body = value.
  field;

  static SnippetPickerItemKind parse(Object? raw) =>
      values.firstWhere((k) => k.name == raw, orElse: () => snippet);
}

const _sentencePrefix = 'sentence:';
const _fillPrefix = 'fill:';

String sentenceSelectionId(String snippetId) => '$_sentencePrefix$snippetId';

String fillSelectionId(List<String> values) =>
    '$_fillPrefix${jsonEncode(values)}';

/// What a selected id asks the main engine to do.
sealed class SnippetPickerSelection {
  const SnippetPickerSelection();

  /// Snippet ids are UUIDs, so they never start with one of the prefixes.
  static SnippetPickerSelection parse(String id) {
    if (id.startsWith(_sentencePrefix)) {
      return SentenceSelection(id.substring(_sentencePrefix.length));
    }
    if (id.startsWith(_fillPrefix)) {
      try {
        final decoded = jsonDecode(id.substring(_fillPrefix.length));
        if (decoded is List && decoded.every((v) => v is String)) {
          return FillSelection(decoded.cast<String>());
        }
      } on FormatException {
        // A broken fill id is treated as a cancel.
        return const FillSelection(null);
      }
      return const FillSelection(null);
    }
    return SnippetSelection(id);
  }
}

/// Insert this snippet (static) or start its guided recording (interactive).
class SnippetSelection extends SnippetPickerSelection {
  const SnippetSelection(this.snippetId);
  final String snippetId;
}

/// Record this interactive snippet in one sentence.
class SentenceSelection extends SnippetPickerSelection {
  const SentenceSelection(this.snippetId);
  final String snippetId;
}

/// The field preview was confirmed; [values] is null if the id was broken.
class FillSelection extends SnippetPickerSelection {
  const FillSelection(this.values);
  final List<String>? values;
}

/// The item list that opens the field preview.
List<Map<String, String>> fieldPreviewItems({
  required String title,
  required String template,
  required List<String> fieldNames,
  required List<String> values,
  required bool speakFieldNamesHint,
}) => [
  {
    'id': 'preview',
    'title': title,
    'body': template,
    kSnippetPickerKindKey: SnippetPickerItemKind.preview.name,
    kSnippetPickerHintKey: speakFieldNamesHint
        ? kSnippetPickerHintSpeakFieldNames
        : '',
  },
  for (var i = 0; i < fieldNames.length; i++)
    {
      'id': 'field:$i',
      'title': fieldNames[i],
      'body': values[i],
      kSnippetPickerKindKey: SnippetPickerItemKind.field.name,
    },
];
