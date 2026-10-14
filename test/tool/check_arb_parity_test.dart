@Tags(<String>['l10n'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_arb_parity.dart';

void main() {
  group('checkArbParity', () {
    const template = {'a', 'b', 'c'};

    test('passes when every locale has exactly the template keys', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'de': {'a', 'b', 'c'},
        },
        baseline: const {},
      );

      expect(errors, isEmpty);
    });

    test('reports a key missing from a locale', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'he': {'a', 'b'},
        },
        baseline: const {},
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('app_he.arb'));
      expect(errors.single, contains('missing'));
      expect(errors.single, contains('"c"'));
    });

    test('reports a key the template does not have', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'ru': {'a', 'b', 'c', 'obsolete'},
        },
        baseline: const {},
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('app_ru.arb'));
      expect(errors.single, contains('"obsolete"'));
    });

    test('tolerates a missing key frozen in the baseline', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'he': {'a', 'b'},
        },
        baseline: {
          'he': {'c'},
        },
      );

      expect(errors, isEmpty);
    });

    test('a baseline entry for one locale does not cover another', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'he': {'a', 'b'},
          'ru': {'a', 'b'},
        },
        baseline: {
          'he': {'c'},
        },
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('app_ru.arb'));
    });

    test('reports a stale baseline entry once the key is translated', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'he': {'a', 'b', 'c'},
        },
        baseline: {
          'he': {'c'},
        },
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('stale'));
      expect(errors.single, contains('"c"'));
    });

    test('reports a stale baseline entry for a key removed from the '
        'template', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'he': {'a', 'b', 'c'},
        },
        baseline: {
          'he': {'gone'},
        },
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('stale'));
    });

    test('reports a baseline locale that has no ARB file', () {
      final errors = checkArbParity(
        templateKeys: template,
        localeKeys: {
          'de': {'a', 'b', 'c'},
        },
        baseline: {
          'fr': {'c'},
        },
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('fr'));
    });
  });

  group('messageKeys', () {
    test('drops metadata entries and @@locale', () {
      final keys = messageKeys({
        '@@locale': 'en',
        'hello': 'Hello',
        '@hello': {'description': 'greeting'},
      });

      expect(keys, {'hello'});
    });
  });

  group('runArbParityCheck', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('arb_parity_test_');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    void writeFile(String name, String content) {
      File('${dir.path}/$name').writeAsStringSync(content);
    }

    test('reads every app_*.arb next to the template', () {
      writeFile('app_en.arb', '{"@@locale": "en", "a": "A", "b": "B"}');
      writeFile('app_de.arb', '{"@@locale": "de", "a": "A"}');

      final errors = runArbParityCheck(
        arbDir: dir.path,
        baselinePath: '${dir.path}/missing_baseline.json',
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('app_de.arb'));
      expect(errors.single, contains('"b"'));
    });

    test('applies the baseline file', () {
      writeFile('app_en.arb', '{"a": "A", "b": "B"}');
      writeFile('app_de.arb', '{"a": "A"}');
      writeFile('baseline.json', '{"de": ["b"]}');

      final errors = runArbParityCheck(
        arbDir: dir.path,
        baselinePath: '${dir.path}/baseline.json',
      );

      expect(errors, isEmpty);
    });
  });

  test('the repository ARB files pass the parity gate', () {
    final errors = runArbParityCheck(
      arbDir: defaultArbDir,
      baselinePath: defaultBaselinePath,
    );

    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
