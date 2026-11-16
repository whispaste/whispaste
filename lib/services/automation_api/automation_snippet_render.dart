/// Pure rendering rules for `POST /v1/snippets/render` (ticket / 8.1).
///
/// Rendering only produces text. Nothing here pastes, types or sends keys —
/// the insertion path stays the separate `POST /v1/snippets/insert` route.
library;

import '../snippets/interactive_snippet_composer.dart';

/// Outcome of [renderSnippetBody].
sealed class SnippetRenderOutcome {
  const SnippetRenderOutcome();
}

class SnippetRenderSuccess extends SnippetRenderOutcome {
  const SnippetRenderSuccess(this.text);
  final String text;
}

/// An interactive snippet needs a value for every field it declares.
class SnippetRenderMissingFields extends SnippetRenderOutcome {
  const SnippetRenderMissingFields(this.names);
  final List<String> names;
}

/// Values were sent for names the snippet does not declare (or any value
/// for a static snippet, which has no fields).
class SnippetRenderUnknownFields extends SnippetRenderOutcome {
  const SnippetRenderUnknownFields(this.names);
  final List<String> names;
}

/// Renders a snippet body with the given field [values].
///
/// [kind] is the stored snippet kind (`static` or `interactive`). Values are
/// substituted once, in declaration order, through the same composer the
/// guided recording uses, so a value that happens to contain a placeholder
/// is never expanded a second time.
SnippetRenderOutcome renderSnippetBody({
  required String kind,
  required String body,
  required List<String> fieldNames,
  required Map<String, String> values,
}) {
  if (kind != 'interactive') {
    if (values.isNotEmpty) {
      return SnippetRenderUnknownFields(values.keys.toList()..sort());
    }
    return SnippetRenderSuccess(body);
  }

  final declared = fieldNames.toSet();
  final unknown = values.keys.where((k) => !declared.contains(k)).toList()
    ..sort();
  if (unknown.isNotEmpty) return SnippetRenderUnknownFields(unknown);

  final missing = fieldNames.where((n) => !values.containsKey(n)).toList();
  if (missing.isNotEmpty) return SnippetRenderMissingFields(missing);

  // One pass over the template: a value that contains another placeholder
  // is inserted as plain text and never expanded again.
  final valueByPlaceholder = {
    for (final n in fieldNames) interactiveSnippetPlaceholder(n): values[n]!,
  };
  if (valueByPlaceholder.isEmpty) return SnippetRenderSuccess(body);
  final pattern = RegExp(valueByPlaceholder.keys.map(RegExp.escape).join('|'));
  return SnippetRenderSuccess(
    body.replaceAllMapped(pattern, (m) => valueByPlaceholder[m.group(0)!]!),
  );
}
