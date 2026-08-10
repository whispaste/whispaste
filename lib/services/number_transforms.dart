/// Pure number-word → digit-string transform for the **Zahlen-Modus** (numeric
/// only output). Engine-independent by construction — this is plain string
/// processing on the already-transcribed text, applied uniformly regardless
/// of which STT engine or provider produced it.
///
/// See PRD `itn-cad-zahlen/PRD.md` §3.1 for the design rationale.
library;

// ---------------------------------------------------------------------------
// Lexika (DE)
// ---------------------------------------------------------------------------

/// Einer (0–9), inkl. Varianten `ein`/`eine` für 1 und `zwo` für 2.
const _ones = {
  'null': 0,
  'eins': 1,
  'ein': 1,
  'eine': 1,
  'zwei': 2,
  'zwo': 2,
  'drei': 3,
  'vier': 4,
  'fünf': 5,
  'sechs': 6,
  'sieben': 7,
  'acht': 8,
  'neun': 9,
};

/// Teens 10–19, inkl. der Sonderformen `sechzehn`/`siebzehn`.
const _teens = {
  'zehn': 10,
  'elf': 11,
  'zwölf': 12,
  'dreizehn': 13,
  'vierzehn': 14,
  'fünfzehn': 15,
  'sechzehn': 16,
  'siebzehn': 17,
  'achtzehn': 18,
  'neunzehn': 19,
};

/// Zehner 20–90, inkl. `dreißig` und der alternativen Schreibweise `dreissig`.
const _tens = {
  'zwanzig': 20,
  'dreißig': 30,
  'dreissig': 30,
  'vierzig': 40,
  'fünfzig': 50,
  'sechzig': 60,
  'siebzig': 70,
  'achtzig': 80,
  'neunzig': 90,
};

/// Skalenwörter (V1: nur hundert und tausend).
const _scales = {
  'hundert': 100,
  'tausend': 1000,
};

/// Dezimal-/Trennzeichen (DE).
const _separators = {
  'komma': ',',
  'punkt': '.',
};

/// Vorzeichen (DE/EN).
const _signs = {
  'minus': '-',
  'negative': '-',
};

/// Alle einfachen (nicht-kompositen) Zahlwörter — Menge für schnelle
/// Mitgliedschaftsprüfung.
final _simpleNumberWords = <String>{
  ..._ones.keys,
  ..._teens.keys,
  ..._tens.keys,
  ..._scales.keys,
};

// ---------------------------------------------------------------------------
// Lexika (EN)
// ---------------------------------------------------------------------------

/// Einer (0–9), inkl. `oh` als Ziffern-Platzhalter (wie bei Telefonnummern).
const _enOnes = {
  'zero': 0,
  'oh': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
};

/// Teens 10–19.
const _enTeens = {
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};

/// Zehner 20–90.
const _enTens = {
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

/// Skalenwörter EN (V1: nur hundred und thousand).
const _enScales = {
  'hundred': 100,
  'thousand': 1000,
};

/// Dezimal-/Trennzeichen (EN).
const _enSeparators = {
  'point': '.',
  'dot': '.',
  'comma': ',',
};

/// Alle einfachen (nicht-kompositen) englischen Zahlwörter — Menge für
/// schnelle Mitgliedschaftsprüfung.
final _enSimpleNumberWords = <String>{
  ..._enOnes.keys,
  ..._enTeens.keys,
  ..._enTens.keys,
  ..._enScales.keys,
};

/// Englische `and`-Filler: wird zwischen Kardinalzahlen ignoriert
/// („one hundred and twenty five" → 125).
const _andFiller = 'and';

// ---------------------------------------------------------------------------
// Regexes (Top-Level `final`, nicht pro Aufruf kompilieren)
// ---------------------------------------------------------------------------

/// Passt auf bereits ziffernförmige Modellausgabe wie `5,2` oder `1.000`.
final _digitsRegex = RegExp(r'^[0-9]+([.,-][0-9]+)*$');

/// Nachbedingung: Ergebnis darf nur Zeichen aus dem Zielalphabet enthalten.
final _numericOnlyRegex = RegExp(r'^[0-9.,-]+$');

// ---------------------------------------------------------------------------
// Klassifikation
// ---------------------------------------------------------------------------

/// Was ein Token nach der Klassifikation ist.
enum _TokenKind {
  /// Bereits ziffernförmig (`5`, `3,14`, `1.000`).
  digits,

  /// Vorzeichen (`minus`, `negative`).
  sign,

  /// Dezimal-/Trennzeichen (`komma`, `punkt`).
  separator,

  /// Zahlwort, das in einen ganzzahligen Wert aufgelöst wird.
  cardinal,

  /// Skalenwort EN (`hundred`, `thousand`) — multipliziert den Akkumulator.
  scale,

  /// Einzelziffer-Wort (`oh`, `zero`) — wird als String emittiert, ohne
  /// Gruppierung mit nachfolgenden Kardinalen (für `oh five` → `05`).
  digitWord,
}

/// Ein klassifiziertes Token.
class _Token {
  final _TokenKind kind;

  /// Für CARDINAL: das Originalwort (wird bei der Emission zerlegt).
  final String word;

  /// Für DIGITS: der unveränderte String.
  /// Für SEPARATOR/SIGN: das auszugebende Zeichen.
  final String? output;

  _Token(this.kind, {required this.word, this.output});
}

// ---------------------------------------------------------------------------
// Zerlegungsalgorithmus (DE)
// ---------------------------------------------------------------------------

/// Zerlegt ein deutsches Kompositum wie `zweitausendfünfhundertdreiundzwanzig`
/// in seinen ganzzahligen Wert.
///
/// Die Reihenfolge der Split-Regeln ist **bindend** (PRD §5.1), sonst
/// zerbricht `hundert` an der eigenen Regel (`h`-`und`-`ert` würde an `und`
/// matchen).
///
/// 1. Erst an `tausend` spalten.
/// 2. Dann an `hundert`.
/// 3. Erst danach exaktes Nachschlagen in den einfachen Lexika.
/// 4. Erst zuletzt an `und` spalten (Einer-vor-Zehner, additiv).
///
/// Ein leerer linker Teil bedeutet Faktor 1 (z. B. `tausend` → `1 * 1000`).
int _decomposeGermanComposite(String word) {
  // 1. Erst an `tausend` spalten.
  final thousandIdx = word.indexOf('tausend');
  if (thousandIdx != -1) {
    final left = word.substring(0, thousandIdx);
    final right = word.substring(thousandIdx + 'tausend'.length);
    final leftValue = left.isEmpty ? 1 : _decomposeGermanComposite(left);
    final rightValue = right.isEmpty ? 0 : _decomposeGermanComposite(right);
    return leftValue * 1000 + rightValue;
  }

  // 2. Dann an `hundert` spalten.
  final hundredIdx = word.indexOf('hundert');
  if (hundredIdx != -1) {
    final left = word.substring(0, hundredIdx);
    final right = word.substring(hundredIdx + 'hundert'.length);
    final leftValue = left.isEmpty ? 1 : _decomposeGermanComposite(left);
    final rightValue = right.isEmpty ? 0 : _decomposeGermanComposite(right);
    return leftValue * 100 + rightValue;
  }

  // 3. Exaktes Nachschlagen.
  if (_ones.containsKey(word)) return _ones[word]!;
  if (_teens.containsKey(word)) return _teens[word]!;
  if (_tens.containsKey(word)) return _tens[word]!;

  // 4. Erst zuletzt an `und` spalten (Einer + Zehner, additiv).
  final undIdx = word.indexOf('und');
  if (undIdx != -1) {
    final left = word.substring(0, undIdx);
    final right = word.substring(undIdx + 'und'.length);
    // Leerer linker Teil bei `und` bedeutet 0 (kein Einer), nicht 1.
    final leftValue = left.isEmpty ? 0 : _decomposeGermanComposite(left);
    final rightValue = right.isEmpty ? 0 : _decomposeGermanComposite(right);
    return leftValue + rightValue;
  }

  // Sollte bei einem validen Kompositum nie erreicht werden.
  throw ArgumentError('Unknown German number word: $word');
}

// ---------------------------------------------------------------------------
// Tokenizer + Klassifikation
// ---------------------------------------------------------------------------

/// Setzt eine Token-Folge wie `["ein", "und", "zwanzig"]` zu einem
/// Kompositum zusammen (`["einundzwanzig"]`), wenn die Muster
/// &lt;Einer&gt; und &lt;Zehner&gt; oder &lt;Einer&gt; und &lt;Einer&gt;
/// vorliegen.
///
/// Wird **vor** der Klassifikation aufgerufen, damit der Zerlegungsalgorithmus
/// das zusammengefügte Wort korrekt verarbeiten kann.
List<String> _mergeSeparatedComposites(List<String> tokens) {
  final result = <String>[];
  var i = 0;
  while (i < tokens.length) {
    if (tokens[i] == 'und' && i > 0 && i + 1 < tokens.length) {
      final prev = tokens[i - 1];
      final next = tokens[i + 1];
      // Prüfen, ob prev und next Zahlwörter sind.
      final prevIsNumberWord = _simpleNumberWords.contains(prev);
      final nextIsNumberWord = _simpleNumberWords.contains(next);
      if (prevIsNumberWord && nextIsNumberWord) {
        // Zusammenführen: prev + und + next.
        final merged = '${prev}und$next';
        // Letztes Element war bereits hinzugefügt, also ersetzen.
        result.removeLast();
        result.add(merged);
        i += 2; // `und` und `next` überspringen.
        continue;
      }
    }
    result.add(tokens[i]);
    i++;
  }
  return result;
}

/// Splitzt englische Bindestrich-Komposita wie `twenty-one` in separate
/// Token (`["twenty", "one"]`). Ziffern-Token (`5,2-3`) behalten ihren
/// Bindestrich als Symbol.
///
/// Wird **vor** der Klassifikation aufgerufen, damit die Mehrwort-Komposition
/// im Emitter die Einzelteile addieren kann.
List<String> _splitHyphenatedComposites(List<String> tokens) {
  final result = <String>[];
  for (final token in tokens) {
    if (token.contains('-') && !_digitsRegex.hasMatch(token)) {
      // Bindestrich-Trennung nur bei Token, die Buchstaben enthalten.
      result.addAll(token.split('-').where((t) => t.isNotEmpty));
    } else {
      result.add(token);
    }
  }
  return result;
}

/// Filtert `and`-Filler heraus, die zwischen Kardinalzahlen stehen
/// (`one hundred and twenty five` → `one hundred twenty five`).
///
/// Wird **vor** der Klassifikation aufgerufen.
List<String> _filterAndFiller(List<String> tokens) {
  final result = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] == _andFiller && i > 0 && i + 1 < tokens.length) {
      final prev = tokens[i - 1];
      final next = tokens[i + 1];
      final prevIsNumber =
          _simpleNumberWords.contains(prev) || _enSimpleNumberWords.contains(prev);
      final nextIsNumber =
          _simpleNumberWords.contains(next) || _enSimpleNumberWords.contains(next);
      if (prevIsNumber && nextIsNumber) {
        continue; // `and` zwischen Kardinalzahlen überspringen.
      }
    }
    result.add(tokens[i]);
  }
  return result;
}

/// Klassifiziert einen einzelnen, bereits bereinigten Token.
///
/// Alle Token, die weder DIGITS, SIGN noch SEPARATOR sind, werden als
/// CARDINAL, SCALE oder DIGIT_WORD klassifiziert. Die Zerlegung (einfacher
/// Wert vs. Kompositum) erfolgt erst bei der Emission über
/// [_resolveCardinalValue]. Falls die Zerlegung fehlschlägt, wird der Token
/// nachträglich als UNKNOWN gewertet und löst die Alles-oder-Nichts-Logik
/// aus.
_Token _classify(String token) {
  if (_digitsRegex.hasMatch(token)) {
    return _Token(_TokenKind.digits, word: token, output: token);
  }
  if (_signs.containsKey(token)) {
    return _Token(_TokenKind.sign, word: token, output: _signs[token]);
  }
  if (_separators.containsKey(token)) {
    return _Token(_TokenKind.separator, word: token, output: _separators[token]);
  }
  if (_enSeparators.containsKey(token)) {
    return _Token(_TokenKind.separator, word: token, output: _enSeparators[token]);
  }
  // EN-Skalenwörter: `hundred`, `thousand`.
  if (_enScales.containsKey(token)) {
    return _Token(_TokenKind.scale, word: token, output: _enScales[token].toString());
  }
  // EN-Einzeldigit-Wörter: `oh`, `zero` → als String emittiert, keine
  // Gruppierung mit nachfolgenden Kardinalen (`oh five` → `05`).
  if (token == 'oh' || token == 'zero') {
    return _Token(_TokenKind.digitWord, word: token, output: '0');
  }
  // Alles andere ist potenziell ein CARDINAL — Zerlegung erfolgt bei Emission.
  return _Token(_TokenKind.cardinal, word: token);
}

/// Klassifiziert eine Liste von Token-Strings.
List<_Token> _classifyAll(List<String> tokens) {
  return tokens.map(_classify).toList();
}

// ---------------------------------------------------------------------------
// Grouping + Emission
// ---------------------------------------------------------------------------

/// Auflöst einen CARDINAL-Token auf seinen ganzzahligen Wert.
///
/// Einfache Wörter (ones/teens/tens/scales) werden direkt nachgeschlagen;
/// Komposita werden über [_decomposeGermanComposite] zerlegt.
int _resolveCardinalValue(_Token token) {
  if (_ones.containsKey(token.word)) return _ones[token.word]!;
  if (_teens.containsKey(token.word)) return _teens[token.word]!;
  if (_tens.containsKey(token.word)) return _tens[token.word]!;
  if (_scales.containsKey(token.word)) return _scales[token.word]!;
  if (_enOnes.containsKey(token.word)) return _enOnes[token.word]!;
  if (_enTeens.containsKey(token.word)) return _enTeens[token.word]!;
  if (_enTens.containsKey(token.word)) return _enTens[token.word]!;
  // Kompositum (DE).
  return _decomposeGermanComposite(token.word);
}

/// Gruppiert aufeinanderfolgende CARDINAL- und SCALE-Token zu einer Zahl und
/// emittiert alle Token als Ausgabetoken in Sprech-Reihenfolge.
///
/// Englische Komposition (§5.1): Skalenwörter (`hundred`, `thousand`)
/// multiplizieren den laufenden Akkumulator und addieren zum Total.
/// Beispiel: `one hundred twenty five` → (1×100) + 25 = 125.
///
/// Einzelziffer-Wörter (`oh`, `zero`) werden als String emittiert, ohne
/// Gruppierung mit nachfolgenden Kardinalen (`oh five` → `05`).
///
/// Gibt `null` zurück, wenn ein Token nicht zerlegt werden kann
/// (Alles-oder-Nichts).
List<String>? _emit(List<_Token> tokens) {
  final result = <String>[];
  var i = 0;
  try {
    while (i < tokens.length) {
      final token = tokens[i];
      if (token.kind == _TokenKind.cardinal || token.kind == _TokenKind.scale) {
        // Gruppe aus aufeinanderfolgenden CARDINAL- und SCALE-Token sammeln.
        final group = <_Token>[];
        while (i < tokens.length &&
            (tokens[i].kind == _TokenKind.cardinal ||
                tokens[i].kind == _TokenKind.scale)) {
          group.add(tokens[i]);
          i++;
        }
        // Englische Komposition: Akkumulator + Total.
        var accumulator = 0;
        var total = 0;
        for (final t in group) {
          if (t.kind == _TokenKind.cardinal) {
            accumulator += _resolveCardinalValue(t);
          } else if (t.kind == _TokenKind.scale) {
            final scale = int.parse(t.output!);
            if (accumulator == 0) accumulator = 1; // `hundred` allein → 100.
            total += accumulator * scale;
            accumulator = 0;
          }
        }
        total += accumulator;
        result.add(total.toString());
      } else if (token.kind == _TokenKind.digitWord) {
        // Einzelziffer-Wort (`oh`, `zero`) → als String emittiert, ohne
        // Gruppierung mit nachfolgenden Kardinalen.
        result.add(token.output!);
        i++;
      } else if (token.kind == _TokenKind.digits) {
        result.add(token.output!);
        i++;
      } else if (token.kind == _TokenKind.separator) {
        result.add(token.output!);
        i++;
      } else if (token.kind == _TokenKind.sign) {
        result.add(token.output!);
        i++;
      } else {
        // UNKNOWN — sollte vorher bereits erkannt worden sein.
        throw StateError('Unhandled token kind: ${token.kind}');
      }
    }
  } on ArgumentError {
    // Zerlegung fehlgeschlagen — Alles-oder-Nichts.
    return null;
  } on FormatException {
    // Parsing-Fehler bei Skalenwort — Alles-oder-Nichts.
    return null;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Öffentliche API
// ---------------------------------------------------------------------------

/// Wandelt ein Transkript, das ausschließlich aus Zahlwörtern, Ziffern und
/// Symbolen (`komma`/`punkt`/`minus`) besteht, in eine rein numerische
/// Darstellung um.
///
/// Gibt `null` zurück, wenn das Transkript nicht vollständig konvertierbar
/// ist (Alles-oder-Nichts-Garantie, PRD §3.2).
///
/// Das Ergebnis passt garantiert auf `^[0-9.,-]+$` und enthält keine
/// Leerzeichen.
///
/// Beispiel:
/// ```dart
/// toNumericOnly('fünf komma zwei minus drei'); // → '5,2-3'
/// toNumericOnly('Hallo Welt');                  // → null
/// ```
String? toNumericOnly(String text) {
  // Stufe 1: Tokenisieren.
  final rawTokens = text.split(RegExp(r'\s+'));
  final tokens = rawTokens
      .map(_cleanToken)
      .where((t) => t.isNotEmpty)
      .toList();

  if (tokens.isEmpty) return null;

  // Ausnahme: reine Satzzeichen-Token werden verworfen (kein UNKNOWN).
  final hasNonPunctuation = tokens.any((t) {
    final c = t.codeUnitAt(0);
    return (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        (c >= 0x30 && c <= 0x39); // 0-9
  });
  if (!hasNonPunctuation) return null;

  // Stufe 1.1: Englische Bindestrich-Komposita auftrennen
  // (z. B. `twenty-one` → `["twenty", "one"]`).
  final hyphenSplit = _splitHyphenatedComposites(tokens);

  // Stufe 1.2: Englischen `and`-Filler herausfiltern (zwischen Kardinalen).
  final andFiltered = _filterAndFiller(hyphenSplit);

  // Stufe 1.5: Getrennt geschriebene Komposita zusammenführen (DE: `und`).
  final merged = _mergeSeparatedComposites(andFiltered);

  // Stufe 2: Klassifizieren.
  final classified = _classifyAll(merged);

  // Stufe 3 + 4: Grouping + Emission. Falls die Zerlegung fehlschlägt,
  // gibt _emit `null` zurück (Alles-oder-Nichts).
  final emitted = _emit(classified);
  if (emitted == null) return null;

  // Stufe 5: Verifizieren.
  final result = emitted.join();
  if (result.isEmpty || !_numericOnlyRegex.hasMatch(result)) return null;

  return result;
}

/// Beschneidet einen Roh-Token an den Rändern: alle Zeichen, die weder
/// Buchstabe, Ziffer noch `.`, `,`, `-` sind, werden entfernt. Bei
/// Ziffern-Token (`5,2`) bleiben `.`, `,`, `-` als Teil des Musters
/// erhalten; bei Wort-Token (`drei.`) werden nachgestellte Satzzeichen
/// entfernt. Dann Kleinbuchstaben.
String _cleanToken(String raw) {
  // Führende/schließende Nicht-Alphabet-/Nicht-Ziffern-Zeichen abschneiden.
  var start = 0;
  var end = raw.length;
  while (start < end && !_isAlphanumeric(raw.codeUnitAt(start))) {
    start++;
  }
  while (end > start && !_isAlphanumeric(raw.codeUnitAt(end - 1))) {
    end--;
  }
  if (start >= end) return '';
  var cleaned = raw.substring(start, end).toLowerCase();

  // Wenn der Token ein Ziffernmuster ist (`5,2`, `1.000`), unverändert
  // zurückgeben (inklusive `.`, `,`, `-` als Teil des Musters).
  if (_digitsRegex.hasMatch(cleaned)) return cleaned;

  // Andernfalls: nachgestellte/vor gestellte `.`, `,`, `-` entfernen
  // (Satzzeichen, die nicht Teil eines Ziffernmusters sind).
  cleaned = _trimPunctuation(cleaned);

  return cleaned;
}

String _trimPunctuation(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && _isPunctuation(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isPunctuation(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

bool _isPunctuation(int codeUnit) {
  return codeUnit == 0x2E || // .
      codeUnit == 0x2C || // ,
      codeUnit == 0x2D; // -
}

bool _isAlphanumeric(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
      (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
      (codeUnit >= 0x30 && codeUnit <= 0x39); // 0-9
}
