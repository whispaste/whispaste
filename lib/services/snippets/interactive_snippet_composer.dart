/// Composes an interactive snippet's collected field transcripts into the
/// single text that gets pasted/copied, exactly as if it were a normal
/// recording's result (originally `.scratch/interactive-snippets/PRD.md`,
/// "Ausgabe-Format" — a fixed heading-per-field layout; superseded by a
/// user-authored template so fields can be placed anywhere in the user's own
/// wording instead).
library;

/// The placeholder token a template must contain for [fieldName]'s dictated
/// text to end up in the composed output.
String interactiveSnippetPlaceholder(String fieldName) => '{{$fieldName}}';

/// Legacy fixed layout (`fieldName`, newline, placeholder, blank-line-
/// separated between fields) — used both as the auto-generated template for
/// snippets
/// created before templates existed (drift schema v23 migration, keeps their
/// composed output byte-for-byte unchanged) and as a reference shape for the
/// editor's own starting point.
String legacyInteractiveSnippetTemplate(List<String> fieldNames) {
  return [
    for (final name in fieldNames)
      '$name\n${interactiveSnippetPlaceholder(name)}',
  ].join('\n\n');
}

/// Substitutes each `{{fieldName}}` placeholder in [template] with its
/// corresponding transcript.
///
/// [fieldNames] and [fieldTranscripts] must be the same length and in field
/// order (index `i` of one corresponds to index `i` of the other). A field
/// name with no matching placeholder in the template simply contributes
/// nothing to the output — the editor validates that every field is
/// referenced before allowing a save, so this does not guard against it.
String composeInteractiveSnippetText({
  required String template,
  required List<String> fieldNames,
  required List<String> fieldTranscripts,
}) {
  assert(
    fieldNames.length == fieldTranscripts.length,
    'composeInteractiveSnippetText requires one transcript per field name',
  );
  var result = template;
  for (var i = 0; i < fieldNames.length; i++) {
    result = result.replaceAll(
      interactiveSnippetPlaceholder(fieldNames[i]),
      fieldTranscripts[i],
    );
  }
  return result;
}
