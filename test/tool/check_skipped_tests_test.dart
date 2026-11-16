import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_skipped_tests.dart';

void main() {
  group('countSkipMarkers', () {
    test('counts real skips, ignores null/false, comments and iterables', () {
      const source = '''
test('a', () {}, skip: 'why');
test('b', () {}, skip: Platform.isWindows ? 'x' : false);
test('c', () {}, skip: null);
test('d', () {}, skip: false);
// skip: 'commented'
final x = list.skip(1);
markTestSkipped('no build');
''';
      expect(countSkipMarkers('a_test.dart', source), 3);
    });

    test('counts TS skip and fixme', () {
      const source = '''
it.skip("a", () => {});
test.fixme("b", () => {});
it("c", () => {});
''';
      expect(countSkipMarkers('a.test.ts', source), 2);
    });
  });

  group('checkSkipCeiling', () {
    test('passes on equal count', () {
      expect(checkSkipCeiling(count: 5, max: 5), isEmpty);
    });

    test('one extra skipped test turns it red', () {
      expect(checkSkipCeiling(count: 6, max: 5), hasLength(1));
    });

    test('a lower count demands a lowered ceiling', () {
      expect(checkSkipCeiling(count: 4, max: 5), hasLength(1));
    });
  });

  test('the checked-in ceiling matches the repository', () {
    final count = scanSkipMarkers(
      defaultRoots,
    ).values.fold<int>(0, (a, b) => a + b);
    expect(
      checkSkipCeiling(count: count, max: readCeiling(defaultBaselinePath)),
      isEmpty,
    );
    expect(File(defaultBaselinePath).existsSync(), isTrue);
  });
}
