/// Deterministic German prose for the #642 editor spike (tests and
/// benchmarks). Generated text, no external source.
library;

const _sentences = [
  'Heute habe ich mit dem Team über den nächsten Schritt gesprochen.',
  'Die Aufnahme lief ruhig, und der Text landete sofort im richtigen Feld.',
  'Wir wollen die Übersicht schlanker machen, ohne Funktionen zu verlieren.',
  'Für längere Diktate braucht der Editor eine klare Gliederung.',
  'Am Nachmittag prüfen wir die Ergebnisse noch einmal in Ruhe.',
  'Wichtig ist, dass niemand beim Schreiben warten muss!',
  'Was passiert, wenn der Absatz sehr lang wird?',
  'Die Überschriften helfen beim Springen durch das Dokument.',
];

int _words(String s) => s.split(' ').length;

/// About [words] words of prose: a heading every ~[wordsPerSection] words,
/// paragraphs of ~[wordsPerParagraph] words, separated by blank lines.
String germanProse(
  int words, {
  int wordsPerParagraph = 120,
  int wordsPerSection = 1500,
}) {
  final out = StringBuffer();
  var total = 0;
  var sectionWords = wordsPerSection;
  var section = 0;
  var k = 0;
  while (total < words) {
    if (sectionWords >= wordsPerSection) {
      section++;
      out.write('${section.isOdd ? '#' : '##'} Abschnitt $section\n\n');
      sectionWords = 0;
    }
    var p = 0;
    final para = StringBuffer();
    while (p < wordsPerParagraph && total < words) {
      final s = _sentences[k++ % _sentences.length];
      if (para.isNotEmpty) para.write(' ');
      para.write(s);
      p += _words(s);
      total += _words(s);
    }
    sectionWords += p;
    out.write('$para\n\n');
  }
  return out.toString();
}

/// One paragraph of about [words] words without any blank line (the
/// dictation case).
String singleParagraph(int words) {
  final out = StringBuffer();
  var total = 0;
  var k = 0;
  while (total < words) {
    final s = _sentences[k++ % _sentences.length];
    if (out.isNotEmpty) out.write(' ');
    out.write(s);
    total += _words(s);
  }
  out.write('\n');
  return out.toString();
}
