import '../dictionary/replacement_duplicates.dart';

/// One ready-made replacement: spoken trigger phrases (German and English
/// together, each a multi-word or compound phrase so ordinary speech does not
/// fire it) and the symbol that replaces them.
class SymbolTemplate {
  const SymbolTemplate(this.triggers, this.replacement);

  final List<String> triggers;
  final String replacement;
}

/// Spoken symbols that the sentence commands do not cover. The sentence marks
/// (comma, period, question mark, exclamation mark, colon) live in
/// `voice_punctuation.dart` and are deliberately not repeated here.
const symbolTemplatePack = <SymbolTemplate>[
  SymbolTemplate(['klammer auf', 'open bracket'], '('),
  SymbolTemplate(['klammer zu', 'close bracket'], ')'),
  SymbolTemplate(['semikolon', 'semicolon'], ';'),
  SymbolTemplate(['gedankenstrich', 'en dash'], '–'),
  SymbolTemplate(['schrägstrich', 'forward slash'], '/'),
  SymbolTemplate(['unterstrich', 'underscore'], '_'),
  SymbolTemplate(['prozentzeichen', 'percent sign'], '%'),
  SymbolTemplate(['und-zeichen', 'ampersand'], '&'),
  SymbolTemplate(['at-zeichen', 'at sign'], '@'),
  SymbolTemplate(['rautezeichen', 'hash sign'], '#'),
  SymbolTemplate(['euro-zeichen', 'euro sign'], '€'),
  SymbolTemplate(['gleichheitszeichen', 'equals sign'], '='),
  SymbolTemplate(['plus-zeichen', 'plus sign'], '+'),
];

/// What [planSymbolPack] decided for a list of existing trigger phrases.
class SymbolPackPlan {
  const SymbolPackPlan(this.toAdd, this.skipped);

  /// Templates that are new and can be written as replacement rows.
  final List<SymbolTemplate> toAdd;

  /// Templates left out because one of their triggers already exists.
  final int skipped;
}

/// Picks the templates that do not clash with [existingTriggers]. A template
/// is skipped as a whole when any of its trigger phrases is already in use,
/// comparing normalised keys (case and punctuation ignored), so running the
/// pack twice adds nothing the second time.
SymbolPackPlan planSymbolPack(
  Iterable<String> existingTriggers, {
  List<SymbolTemplate> templates = symbolTemplatePack,
}) {
  final taken = {for (final t in existingTriggers) normalizeTriggerKey(t)};
  final toAdd = <SymbolTemplate>[];
  var skipped = 0;
  for (final template in templates) {
    final keys = template.triggers.map(normalizeTriggerKey).toList();
    if (keys.any(taken.contains)) {
      skipped++;
      continue;
    }
    toAdd.add(template);
    taken.addAll(keys);
  }
  return SymbolPackPlan(toAdd, skipped);
}
