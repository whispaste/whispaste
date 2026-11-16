/// Function words that never make a useful correction candidate on their own
/// (issue #144: "keine reinen Stoppwörter in allen App-Sprachen").
///
/// One union over every app language (de, en, es, he, pt, ru) on purpose: a
/// candidate is dropped when all of its words are function words in any of
/// them, so "der" -> "die" is rejected in German, and "the" -> "a" in English.
/// Entries are lowercase. The list is deliberately short -- it guards against
/// the common noise, it is not a linguistic resource.
library;

const Set<String> correctionStopwords = {
  // German
  'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einer', 'eines',
  'einem', 'einen', 'und', 'oder', 'aber', 'ist', 'sind', 'war', 'waren',
  'bin', 'bist', 'sein', 'seine', 'seiner', 'ich', 'du', 'er', 'sie', 'es',
  'wir', 'ihr', 'mich', 'dich', 'uns', 'euch', 'mir', 'dir', 'ihm', 'ihn',
  'nicht', 'kein', 'keine', 'auch', 'noch', 'nur', 'schon', 'sehr', 'dass',
  'wenn', 'als', 'wie', 'wo', 'wer', 'was', 'mit', 'von', 'zu', 'zum', 'zur',
  'im', 'in', 'am', 'an', 'auf', 'aus', 'bei', 'nach', 'für', 'über', 'unter',
  'vor', 'hinter', 'durch', 'um', 'ohne', 'gegen', 'bis', 'seit', 'dann',
  'so', 'doch', 'mal', 'ja', 'nein', 'hat', 'haben', 'wird', 'werden', 'kann',
  'können', 'muss', 'soll', 'dieser', 'diese', 'dieses', 'man', 'sich',
  // English
  'the', 'a', 'and', 'or', 'but', 'if', 'of', 'to', 'on', 'at',
  'by', 'for', 'with', 'from', 'as', 'is', 'are', 'were', 'be', 'been',
  'being', 'it', 'its', 'this', 'that', 'these', 'those', 'i', 'you', 'he',
  'she', 'we', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his',
  'our', 'their', 'not', 'no', 'do', 'does', 'did', 'have', 'has', 'had',
  'will', 'would', 'can', 'could', 'should', 'shall', 'may', 'might', 'must',
  'than', 'then', 'there', 'here', 'what', 'which', 'who', 'when',
  'where', 'why', 'how', 'all', 'any', 'some',
  // Spanish
  'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'y', 'o', 'pero',
  'si', 'de', 'del', 'al', 'en', 'con', 'por', 'para', 'sin', 'sobre', 'que',
  'como', 'son', 'ser', 'estar', 'fue', 'este', 'esta', 'eso', 'ese',
  'yo', 'tú', 'él', 'ella', 'nosotros', 'ellos', 'te', 'se', 'lo', 'le',
  'les', 'mi', 'tu', 'su', 'ya', 'muy', 'más', 'también',
  // Portuguese
  'os', 'uma', 'umas', 'e', 'ou', 'mas', 'da',
  'dos', 'em', 'na', 'nos', 'nas', 'com', 'sem', 'é',
  'são', 'foi', 'isso', 'esse', 'eu', 'ele', 'ela',
  'nós', 'eles', 'lhe', 'não', 'já', 'muito', 'mais', 'também',
  // Russian
  'и', 'в', 'во', 'не', 'что', 'он', 'на', 'я', 'с', 'со', 'как', 'а', 'то',
  'все', 'она', 'так', 'его', 'но', 'да', 'ты', 'к', 'у', 'же', 'вы', 'за',
  'бы', 'по', 'только', 'её', 'мне', 'было', 'вот', 'от', 'меня', 'ещё',
  'нет', 'о', 'из', 'ему', 'теперь', 'когда', 'даже', 'ну', 'ли', 'если',
  'уже', 'или', 'ни', 'был', 'до', 'вас', 'ведь', 'там', 'себя', 'ничего',
  'мы', 'тебя', 'их', 'чем', 'для', 'это', 'этот', 'эта', 'эти',
  // Hebrew
  'את', 'של', 'ה', 'ו', 'או', 'כי', 'אם', 'לא', 'גם', 'על', 'עם', 'אני',
  'אתה', 'הוא', 'היא', 'אנחנו', 'הם', 'הן', 'זה', 'זו', 'זאת', 'אלה', 'מה',
  'מי', 'איך', 'כל', 'יש', 'אין', 'כן', 'עוד', 'רק', 'כך', 'אבל', 'כמו',
  'לי', 'לך', 'לו', 'לה', 'לנו', 'להם', 'אותו', 'אותה',
};
