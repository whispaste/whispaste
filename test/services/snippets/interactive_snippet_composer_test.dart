import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/snippets/interactive_snippet_composer.dart';

void main() {
  group('legacyInteractiveSnippetTemplate', () {
    test('builds a heading-per-field placeholder template', () {
      final template = legacyInteractiveSnippetTemplate([
        'Titel',
        'Beschreibung',
      ]);

      expect(template, 'Titel\n{{Titel}}\n\nBeschreibung\n{{Beschreibung}}');
    });

    test('a single field produces no trailing separator', () {
      expect(legacyInteractiveSnippetTemplate(['Titel']), 'Titel\n{{Titel}}');
    });
  });

  group('composeInteractiveSnippetText', () {
    test('substitutes each placeholder with its transcript', () {
      final result = composeInteractiveSnippetText(
        template: legacyInteractiveSnippetTemplate(['Titel', 'Beschreibung']),
        fieldNames: ['Titel', 'Beschreibung'],
        fieldTranscripts: [
          'Login schlägt fehl',
          'Der Nutzer kann sich nicht anmelden.',
        ],
      );

      expect(
        result,
        'Titel\nLogin schlägt fehl\n\nBeschreibung\nDer Nutzer kann sich '
        'nicht anmelden.',
      );
    });

    test('places fields anywhere in a free-form template, in any order', () {
      final result = composeInteractiveSnippetText(
        template: 'Hallo {{Name}}, danke für deine Anfrage zu {{Thema}}!',
        fieldNames: ['Name', 'Thema'],
        fieldTranscripts: ['Anna', 'die Rechnung'],
      );

      expect(result, 'Hallo Anna, danke für deine Anfrage zu die Rechnung!');
    });

    test('a field referenced twice in the template is substituted both '
        'times', () {
      final result = composeInteractiveSnippetText(
        template: '{{Name}}: Hallo {{Name}}!',
        fieldNames: ['Name'],
        fieldTranscripts: ['Anna'],
      );

      expect(result, 'Anna: Hallo Anna!');
    });

    test('a field with no matching placeholder contributes nothing', () {
      final result = composeInteractiveSnippetText(
        template: 'Nur {{Titel}}.',
        fieldNames: ['Titel', 'Unbenutzt'],
        fieldTranscripts: ['Login schlägt fehl', 'wird ignoriert'],
      );

      expect(result, 'Nur Login schlägt fehl.');
    });

    test('preserves special characters and line breaks inside a field '
        'transcript', () {
      final result = composeInteractiveSnippetText(
        template: legacyInteractiveSnippetTemplate(['Reproduktion']),
        fieldNames: ['Reproduktion'],
        fieldTranscripts: [
          '1. Login öffnen\n2. "admin" eingeben & Enter drücken',
        ],
      );

      expect(
        result,
        'Reproduktion\n1. Login öffnen\n2. "admin" eingeben & Enter drücken',
      );
    });
  });
}
