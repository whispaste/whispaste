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

/// Klassifiziert einen einzelnen, bereits bereinigten Token.
///
/// Alle Token, die weder DIGITS, SIGN noch SEPARATOR sind, werden als
/// CARDINAL klassifiziert. Die Zerlegung (einfacher Wert vs. Kompositum)
/// erfolgt erst bei der Emission über [_resolveCardinalValue]. Falls die
/// Zerlegung fehlschlägt, wird der Token nachträglich als UNKNOWN gewertet
/// und löst die Alles-oder-Nichts-Logik aus.
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
  // Kompositum.
  return _decomposeGermanComposite(token.word);
}

/// Gruppiert aufeinanderfolgende CARDINAL-Token zu einer Zahl und emittiert
/// alle Token als Ausgabetoken in Sprech-Reihenfolge.
///
/// Ein CARDINAL-Token wird über [_resolveCardinalValue] in einen ganzzahligen
/// Wert aufgelöst und als Ziffern-String emittiert. Gibt `null` zurück, wenn
/// ein Token nicht zerlegt werden kann (Alles-oder-Nichts).
List<String>? _emit(List<_Token> tokens) {
  final result = <String>[];
  var i = 0;
  try {
    while (i < tokens.length) {
      final token = tokens[i];
      if (token.kind == _TokenKind.cardinal) {
        // Aufeinanderfolgende CARDINAL-Token sammeln.
        final cardinals = <int>[];
        while (i < tokens.length && tokens[i].kind == _TokenKind.cardinal) {
          cardinals.add(_resolveCardinalValue(tokens[i]));
          i++;
        }
        // Kompositum berechnen: aufeinanderfolgende Kardinalzahlen werden
        // additiv verknüpft (z. B. `20 + 3 = 23` für `zwanzig drei`).
        var value = 0;
        for (final v in cardinals) {
          value += v;
        }
        result.add(value.toString());
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

  // Stufe 1.5: Getrennt geschriebene Komposita zusammenführen.
  final merged = _mergeSeparatedComposites(tokens);

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
