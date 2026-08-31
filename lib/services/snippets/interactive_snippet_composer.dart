/// Composes an interactive snippet's collected field transcripts into the
/// single text that gets pasted/copied, exactly as if it were a normal
/// recording's result (PRD `.scratch/interactive-snippets/PRD.md`,
/// "Ausgabe-Format").
library;

/// Fixed MVP composition (not user-configurable, see PRD "Out of Scope"):
/// each field becomes a heading with the field's name, followed by its
/// dictated text, with a blank line between fields.
///
/// [fieldNames] and [fieldTranscripts] must be the same length and in field
/// order (index `i` of one corresponds to index `i` of the other).
String composeInteractiveSnippetText(
  List<String> fieldNames,
  List<String> fieldTranscripts,
) {
  assert(
    fieldNames.length == fieldTranscripts.length,
    'composeInteractiveSnippetText requires one transcript per field name',
  );
  return [
    for (var i = 0; i < fieldNames.length; i++)
      '${fieldNames[i]}\n${fieldTranscripts[i]}',
  ].join('\n\n');
}
