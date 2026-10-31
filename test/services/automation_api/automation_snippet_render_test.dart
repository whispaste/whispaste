/// Pure rendering rules for `POST /v1/snippets/render` (WP-38 / 8.1).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/automation_snippet_render.dart';

void main() {
  group('renderSnippetBody', () {
    test('a static snippet renders its body verbatim', () {
      final result = renderSnippetBody(
        kind: 'static',
        body: 'Hello\nWorld',
        fieldNames: const [],
        values: const {},
      );
      expect(result, isA<SnippetRenderSuccess>());
      expect((result as SnippetRenderSuccess).text, 'Hello\nWorld');
    });

    test('a static snippet refuses field values it has no fields for', () {
      final result = renderSnippetBody(
        kind: 'static',
        body: 'Hello',
        fieldNames: const [],
        values: const {'name': 'Ada'},
      );
      expect(result, isA<SnippetRenderUnknownFields>());
      expect((result as SnippetRenderUnknownFields).names, ['name']);
    });

    test('an interactive snippet substitutes each placeholder', () {
      final result = renderSnippetBody(
        kind: 'interactive',
        body: 'Dear {{name}}, {{topic}}.',
        fieldNames: const ['name', 'topic'],
        values: const {'name': 'Ada', 'topic': 'meeting'},
      );
      expect((result as SnippetRenderSuccess).text, 'Dear Ada, meeting.');
    });

    test('an interactive snippet reports every missing field', () {
      final result = renderSnippetBody(
        kind: 'interactive',
        body: '{{a}} {{b}} {{c}}',
        fieldNames: const ['a', 'b', 'c'],
        values: const {'b': 'x'},
      );
      expect(result, isA<SnippetRenderMissingFields>());
      expect((result as SnippetRenderMissingFields).names, ['a', 'c']);
    });

    test('an interactive snippet rejects values for unknown fields', () {
      final result = renderSnippetBody(
        kind: 'interactive',
        body: '{{a}}',
        fieldNames: const ['a'],
        values: const {'a': 'x', 'zzz': 'y'},
      );
      expect(result, isA<SnippetRenderUnknownFields>());
      expect((result as SnippetRenderUnknownFields).names, ['zzz']);
    });

    test('a placeholder value is inserted literally, not re-parsed', () {
      final result = renderSnippetBody(
        kind: 'interactive',
        body: '[{{a}}]',
        fieldNames: const ['a'],
        values: const {'a': r'{{a}} $1'},
      );
      expect((result as SnippetRenderSuccess).text, r'[{{a}} $1]');
    });

    test('a value containing another field placeholder is not expanded', () {
      final result = renderSnippetBody(
        kind: 'interactive',
        body: '{{a}} / {{b}}',
        fieldNames: const ['a', 'b'],
        values: const {'a': '{{b}}', 'b': 'second'},
      );
      expect((result as SnippetRenderSuccess).text, '{{b}} / second');
    });
  });
}
