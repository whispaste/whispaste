import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/vocabulary_import_scanner.dart';

void main() {
  group('extractIdentifiers', () {
    test('finds a Dart class declaration', () {
      final found = extractIdentifiers({
        'a.dart': 'class RecordingOrchestrator {\n  void start() {}\n}',
      });
      expect(found, contains('RecordingOrchestrator'));
    });

    test('finds a Python def declaration', () {
      final found = extractIdentifiers({
        'a.py': 'def get_user_by_id(id):\n    pass',
      });
      expect(found, contains('get_user_by_id'));
    });

    test('finds a JS/TS function declaration', () {
      final found = extractIdentifiers({
        'a.ts': 'function computeImportDiff(candidates) { return []; }',
      });
      expect(found, contains('computeImportDiff'));
    });

    test('finds a Rust fn declaration', () {
      final found = extractIdentifiers({'a.rs': 'fn get_user_by_id() {}'});
      expect(found, contains('get_user_by_id'));
    });

    test('finds const/let/var declarations', () {
      final found = extractIdentifiers({
        'a.ts': 'const maxRetryCount = 3;\nlet userSessionToken = "";\n',
      });
      expect(found, containsAll(['maxRetryCount', 'userSessionToken']));
    });

    test('finds a multi-segment call expression as a weaker signal', () {
      final found = extractIdentifiers({'a.dart': 'getUserById(userId);'});
      expect(found, contains('getUserById'));
    });

    test(
      'does not pick up a single-segment call like a control-flow keyword',
      () {
        final found = extractIdentifiers({'a.dart': 'if (ready) { run(); }'});
        expect(found, isNot(contains('if')));
        expect(found, isNot(contains('run')));
      },
    );

    test('fallback heuristic finds a standalone camelCase token', () {
      final found = extractIdentifiers({
        'a.dart': 'final currentUserToken = fetchToken();',
      });
      expect(found, contains('currentUserToken'));
    });

    test('fallback heuristic finds a standalone snake_case token', () {
      final found = extractIdentifiers({'a.py': 'total_word_count = 0'});
      expect(found, contains('total_word_count'));
    });

    test('documented false-positive: the fallback heuristic also matches a '
        'multi-word PascalCase comment token that is not really an identifier '
        'declaration -- accepted per PRD.md, not treated as a bug', () {
      final found = extractIdentifiers({
        'a.dart': '// See TODO: FixThisLater before shipping',
      });
      expect(found, contains('FixThisLater'));
    });

    test('a single-segment lowercase word is never extracted', () {
      final found = extractIdentifiers({'a.dart': 'return value;'});
      expect(found, isNot(contains('value')));
      expect(found, isNot(contains('return')));
    });

    test('scans every file in the map', () {
      final found = extractIdentifiers({
        'a.dart': 'class Foo {}',
        'b.py': 'class BarBaz:',
      });
      expect(found, containsAll(['Foo', 'BarBaz']));
    });
  });

  group('computeImportDiff', () {
    test('new candidates are all queued for insertion', () {
      final diff = computeImportDiff({'getUserById', 'MaxRetryCount'}, {});
      expect(diff.toInsert, unorderedEquals(['getUserById', 'MaxRetryCount']));
      expect(diff.skipped, 0);
    });

    test('a candidate matching an existing trigger is skipped', () {
      final diff = computeImportDiff({'getUserById'}, {'getUserById'});
      expect(diff.toInsert, isEmpty);
      expect(diff.skipped, 1);
    });

    test('dedup is case-sensitive — a differently-cased existing trigger '
        'does not suppress the candidate', () {
      final diff = computeImportDiff({'getUserById'}, {'GetUserById'});
      expect(diff.toInsert, ['getUserById']);
      expect(diff.skipped, 0);
    });

    test('result is sorted for deterministic UI/summary output', () {
      final diff = computeImportDiff({'zebra', 'alpha', 'mango'}, {});
      expect(diff.toInsert, ['alpha', 'mango', 'zebra']);
    });
  });
}
