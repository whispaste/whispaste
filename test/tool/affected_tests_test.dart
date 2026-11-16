import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart';

// A small repo: a service with a helper, a test that reaches the helper only
// through the service, a guard that scans lib/, and a guard over one script.
const _sources = <String, String>{
  'lib/core/helper.dart': '',
  'lib/services/service.dart': "import '../core/helper.dart';\n",
  'lib/services/other.dart': '',
  'lib/barrel.dart': "export 'services/other.dart';\n",
  'test/services/service_test.dart':
      "import 'package:whispaste/services/service.dart';\n",
  'test/barrel_test.dart': "import 'package:whispaste/barrel.dart';\n",
  'test/core/lib_guard_test.dart':
      "import 'dart:io';\nfinal d = Directory('lib');\n",
  'test/build/pin_guard_test.dart':
      "import 'dart:io';\n"
      "const _scripts = ['scripts/build.sh'];\n"
      'String read(String p) => File(p).readAsStringSync();\n',
  'test/unrelated_test.dart':
      "import 'package:flutter_test/flutter_test.dart';\n",
};

List<String> _select(List<String> changed) {
  final selection = selectTests(_sources, changed);
  expect(selection.isAll, isFalse);
  return selection.tests;
}

void main() {
  test('a transitive import reaches the test', () {
    expect(_select(['lib/core/helper.dart']), [
      'test/core/lib_guard_test.dart',
      'test/services/service_test.dart',
    ]);
  });

  test('an export reaches the test of the barrel', () {
    expect(
      _select(['lib/services/other.dart']),
      contains('test/barrel_test.dart'),
    );
  });

  test('a guard naming a script through a variable is selected', () {
    expect(_select(['scripts/build.sh']), ['test/build/pin_guard_test.dart']);
  });

  test('a changed test selects itself, nothing else', () {
    expect(_select(['test/unrelated_test.dart']), ['test/unrelated_test.dart']);
  });

  test('a docs-only change selects nothing', () {
    expect(_select(['BUILD.md']), isEmpty);
  });

  test('nearest tests come first: guards, then direct, then transitive', () {
    final selection = selectTests(
      {
        ..._sources,
        'test/core/helper_test.dart':
            "import 'package:whispaste/core/helper.dart';\n",
      },
      ['lib/core/helper.dart'],
    );
    expect(selection.tests, [
      'test/core/lib_guard_test.dart',
      'test/core/helper_test.dart',
      'test/services/service_test.dart',
    ]);
    expect(selection.distances['test/services/service_test.dart'], 2);
  });

  test('generated localizations reach no test through imports', () {
    expect(_select(['lib/core/l10n/generated/app_localizations.dart']), [
      'test/core/lib_guard_test.dart',
    ]);
  });

  test('within a distance, a rarely imported change comes first', () {
    final selection = selectTests(
      {
        'lib/hub.dart': '',
        'lib/rare.dart': '',
        for (final name in ['a', 'b', 'c'])
          'test/${name}_test.dart': "import 'package:whispaste/hub.dart';\n",
        'test/z_test.dart': "import 'package:whispaste/rare.dart';\n",
      },
      ['lib/hub.dart', 'lib/rare.dart'],
    );
    expect(selection.tests.first, 'test/z_test.dart');
  });

  test('pubspec changes run the whole suite', () {
    final selection = selectTests(_sources, ['pubspec.lock']);
    expect(selection.isAll, isTrue);
  });
}
