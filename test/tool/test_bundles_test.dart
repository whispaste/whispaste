import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_bundles.dart';

void main() {
  test('areas group nested files by their second folder', () {
    expect(areaOf('test/a_test.dart'), 'test');
    expect(areaOf('test/core/a_test.dart'), 'test/core');
    expect(
      areaOf('test/features/history/a_test.dart'),
      'test/features/history',
    );
    expect(
      areaOf('test/features/history/data/a_test.dart'),
      'test/features/history',
    );
  });

  test('bundles are split per area and capped in size', () {
    final files = [
      for (var i = 0; i < maxFilesPerBundle + 1; i++)
        'test/core/f${i.toString().padLeft(3, '0')}_test.dart',
      'test/app/a_test.dart',
    ];
    final bundles = planBundles(files);
    expect(bundles.map((b) => b.name), [
      'test_app_1_test.dart',
      'test_core_1_test.dart',
      'test_core_2_test.dart',
    ]);
    expect(bundles[1].files, hasLength(maxFilesPerBundle));
    expect(bundles[2].files, ['test/core/f040_test.dart']);
  });

  test('a smaller cap splits an area into more bundles', () {
    final files = [for (var i = 0; i < 31; i++) 'test/core/f${i}_test.dart'];
    expect(planBundles(files, maxFiles: 15), hasLength(3));
  });

  test('a list too large for one run is split into runs of whole bundles', () {
    Bundle b(String name, int n) => Bundle(name, [
      for (var i = 0; i < n; i++) 'test/$name/f${i}_test.dart',
    ]);
    final bundles = [b('a', 15), b('b', 15), b('c', 10), b('d', 15)];

    expect(planRuns(bundles, ['test/x_test.dart'], 0), hasLength(1));

    final runs = planRuns(bundles, [
      'test/x_test.dart',
      'test/y_test.dart',
    ], 30);
    expect([for (final r in runs) r.files], [30, 27]);
    expect(
      [for (final r in runs) r.bundles.map((x) => x.name).join()],
      ['ab', 'cd'],
    );
    expect(runs.last.own, ['test/x_test.dart', 'test/y_test.dart']);
  });

  test('a bundle larger than a run gets a run of its own', () {
    final big = Bundle('big', [for (var i = 0; i < 40; i++) 'test/f$i']);
    final runs = planRuns(
      [
        big,
        const Bundle('s', ['test/s']),
      ],
      const [],
      30,
    );
    expect([for (final r in runs) r.files], [40, 1]);
  });

  test('a bundle imports from test/ and names each group after its file', () {
    final source = bundleSource(
      const Bundle('x_test.dart', ['test/core/a_test.dart']),
      'test/_lab_bundles',
    );
    expect(source, contains("import '../core/a_test.dart' as t0;"));
    expect(source, contains("group('core/a_test.dart', t0.main);"));
  });

  test('files an import would change run on their own', () {
    expect(needsOwnRun("@Tags(['golden'])\nlibrary;\n"), isTrue);
    expect(needsOwnRun("@TestOn('linux')\nlibrary;\n"), isTrue);
    expect(needsOwnRun('Future<void> main() async {}\n'), isTrue);
    expect(needsOwnRun('void main() async {}\n'), isTrue);
    expect(needsOwnRun('$ownRunMarker (shared database)\n'), isTrue);
    expect(needsOwnRun('void main() {\n  test(...);\n}\n'), isFalse);
    // A test-level annotation inside the file stays with its test.
    expect(
      needsOwnRun("void main() {\n  test('x', () {}, tags: ['a']);\n}"),
      isFalse,
    );
  });
}
