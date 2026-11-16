import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The German app and its manual address the user informally ("du"), never
/// with "Sie". A capitalised "Sie", "Ihnen" or "Ihr…" in the middle of a
/// sentence is the formal address; at a sentence start (after ". ", a colon,
/// a quote or an ICU brace) it is the plain pronoun "sie" and stays allowed.
final _formal = RegExp(
  r'(?<=[\wäöüß,;)] )(Sie|Ihnen|Ihr|Ihre|Ihren|Ihrem|Ihrer|Ihres)\b',
);

void main() {
  test('German strings use the informal "du", never the formal "Sie"', () {
    final decoded =
        jsonDecode(File('lib/core/l10n/app_de.arb').readAsStringSync())
            as Map<String, dynamic>;

    final violations = <String>[];
    decoded.forEach((key, value) {
      if (key.startsWith('@') || value is! String) return;
      for (final match in _formal.allMatches(value)) {
        final start = match.start < 30 ? 0 : match.start - 30;
        final end = match.end + 20 > value.length
            ? value.length
            : match.end + 20;
        violations.add('$key: …${value.substring(start, end)}…');
      }
    });

    expect(
      violations,
      isEmpty,
      reason: 'Formal address found:\n${violations.join('\n')}',
    );
  });

  test('the guard catches a formal address mid-sentence', () {
    expect(_formal.hasMatch('Wenn Sie den Text bearbeiten'), isTrue);
    expect(_formal.hasMatch('so holen Sie ihn zurück'), isTrue);
    expect(_formal.hasMatch('in Ihrem Postfach'), isTrue);
    expect(_formal.hasMatch('Fertig. Sie bleiben in der Liste.'), isFalse);
    expect(_formal.hasMatch('Hinweis: Sie erscheint später.'), isFalse);
    expect(_formal.hasMatch('{days, plural, =0{Sie bleiben}}'), isFalse);
  });
}
