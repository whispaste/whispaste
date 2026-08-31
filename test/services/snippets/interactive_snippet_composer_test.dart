import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/snippets/interactive_snippet_composer.dart';

void main() {
  test('composes a minimal two-field template', () {
    final result = composeInteractiveSnippetText(
      ['Titel', 'Beschreibung'],
      ['Login schlägt fehl', 'Der Nutzer kann sich nicht anmelden.'],
    );

    expect(
      result,
      'Titel\nLogin schlägt fehl\n\nBeschreibung\nDer Nutzer kann sich '
      'nicht anmelden.',
    );
  });

  test('preserves field order', () {
    final result = composeInteractiveSnippetText(
      ['Erwartet', 'Ist'],
      ['200 OK', '500 Internal Server Error'],
    );

    expect(result.indexOf('Erwartet'), lessThan(result.indexOf('Ist')));
  });

  test('preserves special characters and line breaks inside a field '
      'transcript', () {
    final result = composeInteractiveSnippetText(
      ['Reproduktion'],
      ['1. Login öffnen\n2. "admin" eingeben & Enter drücken'],
    );

    expect(
      result,
      'Reproduktion\n1. Login öffnen\n2. "admin" eingeben & Enter drücken',
    );
  });

  test('a single field produces no trailing separator', () {
    final result = composeInteractiveSnippetText(['Titel'], ['Nur ein Feld']);

    expect(result, 'Titel\nNur ein Feld');
  });
}
