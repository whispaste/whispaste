import 'package:flutter_test/flutter_test.dart';

import '../../tool/lab_tests.dart';

const _sources = <String, String>{
  'lib/a.dart': '',
  'lib/b.dart': '',
  'test/a_test.dart': "import 'package:whispaste/a.dart';\n",
  'test/b_test.dart': "import 'package:whispaste/b.dart';\n",
  'test/journeys/a_journey_test.dart': "import 'package:whispaste/a.dart';\n",
};
const _full = ['test/a_test.dart', 'test/b_test.dart'];
const _base =
    '100644 blob 1111\tlib/a.dart\n'
    '100644 blob 2222\tlib/b.dart\n'
    '100644 blob 3333\tinternal-notes\n';

LabPlan _plan(String current, {String? baseline = _base, bool force = false}) =>
    planLab(
      baseline: baseline,
      current: current,
      sources: _sources,
      full: _full,
      forceFull: force,
    );

void main() {
  test('changedPaths finds modified, added and removed entries', () {
    expect(
      changedPaths(
        _base,
        '100644 blob 9999\tlib/a.dart\n'
        '100644 blob 2222\tlib/b.dart\n'
        '100755 blob 4444\tscripts/new.sh\n',
      ),
      {'lib/a.dart', 'internal-notes', 'scripts/new.sh'},
    );
  });

  test('a merge runs only the tests importing the change, no journeys', () {
    final plan = _plan(_base.replaceFirst('1111', '9999'));
    expect(plan.isFull, isFalse);
    expect(plan.tests, ['test/a_test.dart']);
  });

  test('a change no test depends on runs no test', () {
    final plan = _plan(_base.replaceFirst('3333', '9999'));
    expect(plan.isFull, isFalse);
    expect(plan.tests, isEmpty);
  });

  test('no baseline, a manual run or a Flutter change run the full lane', () {
    expect(_plan(_base, baseline: null).tests, _full);
    expect(_plan(_base, force: true).isFull, isTrue);
    final flutter = _plan('${_base}100644 blob 5\t.flutter-version\n');
    expect(flutter.reason, contains('.flutter-version'));
    final pubspec = _plan('${_base}100644 blob 6\tpubspec.lock\n');
    expect(pubspec.tests, _full);
  });

  test('a change to the lane itself does not force the full lane', () {
    final plan = _plan('${_base}100644 blob 7\t.internal forge/workflows/lab.yml\n');
    expect(plan.isFull, isFalse);
  });

  test('the full lane leaves the journeys to lab-full', () {
    expect(fullLane(['test/core', 'test/journeys', 'test/a_test.dart']), [
      'test/a_test.dart',
      'test/core',
    ]);
  });
}
