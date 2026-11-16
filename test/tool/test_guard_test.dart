import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_guard.dart';

Map<String, Object?> _start(int id, String name, int time) => {
  'type': 'testStart',
  'time': time,
  'test': {'id': id, 'name': name, 'suiteID': 0},
};

Map<String, Object?> _done(
  int id,
  int time, {
  String result = 'success',
  bool hidden = false,
  bool skipped = false,
}) => {
  'type': 'testDone',
  'testID': id,
  'result': result,
  'hidden': hidden,
  'skipped': skipped,
  'time': time,
};

const _suite = <String, Object?>{
  'type': 'suite',
  'suite': {'id': 0, 'path': 'test/a_test.dart'},
};

TestGuard _guard(List<Map<String, Object?>> events) {
  final guard = TestGuard();
  events.forEach(guard.add);
  return guard;
}

List<String> _verdict(
  TestGuard guard, {
  int wall = 30,
  int exitCode = 0,
  int? stalledAfter,
}) => guard.verdict(
  wall: Duration(seconds: wall),
  exitCode: exitCode,
  stalledAfter: stalledAfter == null ? null : Duration(seconds: stalledAfter),
);

void main() {
  test('a fast green run within the limits is green', () {
    final guard = _guard([
      _suite,
      _start(1, 'loading test/a_test.dart', 0),
      _done(1, 60000, hidden: true),
      _start(2, 'fast', 60000),
      _done(2, 60100),
      _start(3, 'skipped', 60100),
      _done(3, 90000, skipped: true),
    ]);

    expect((guard.passed, guard.skipped, guard.failed), (1, 1, 0));
    expect(_verdict(guard), isEmpty);
  });

  test('a passing test over the limit is red and named with its time', () {
    final guard = TestGuard();
    guard.add(_suite);
    guard.add(_start(1, 'slow but green', 0));

    final lines = guard.add(_done(1, 10900));

    expect(lines.single, contains('test/a_test.dart | slow but green'));
    expect(lines.single, contains('10.9 s'));
    expect(guard.failed, 1);
    expect(_verdict(guard).single, contains('1 passing test(s) over 10 s'));
  });

  test('a failing test is printed with its error, a failing hook counts', () {
    final guard = TestGuard();
    guard.add(_suite);
    guard.add(_start(1, 'red', 0));
    guard.add({
      'type': 'error',
      'testID': 1,
      'error': 'Expected: 1',
      'stackTrace': 'a_test.dart 5',
    });

    final lines = guard.add(_done(1, 50, result: 'failure'));
    guard.add(_start(2, '(tearDownAll)', 50));
    guard.add(_done(2, 60, result: 'error', hidden: true));

    expect(lines.first, 'FAILED  test/a_test.dart | red');
    expect(lines, contains('  Expected: 1'));
    expect(guard.failures, hasLength(2));
    expect(_verdict(guard, exitCode: 1).single, '2 test(s) failed');
  });

  test('an error after a test completed fails that test by name', () {
    final guard = TestGuard();
    guard.add(_suite);
    guard.add(_start(1, 'late', 0));
    guard.add(_done(1, 10));
    final lines = guard.add({
      'type': 'error',
      'testID': 1,
      'error': 'This test failed after it had already completed.',
      'stackTrace': '',
    });

    expect(lines.first, 'FAILED AFTER COMPLETION  test/a_test.dart | late');
    expect(guard.passed, 0);
    expect(guard.failures, ['test/a_test.dart | late']);
    // Named with the test instead of only "flutter test exited with 1".
    expect(_verdict(guard, exitCode: 1).single, '1 test(s) failed');
  });

  test('silence: the startup limit holds until the first real result', () {
    final guard = TestGuard();
    guard.add(_start(1, 'loading test/a_test.dart', 0));
    guard.add(_done(1, 5000, hidden: true));
    expect(guard.silenceLimit, const Duration(seconds: 120));

    guard.add(_start(2, 'first', 5000));
    guard.add(_done(2, 5100));
    expect(guard.silenceLimit, const Duration(seconds: 20));
  });

  test('a stalled run names the tests that never finished', () {
    final guard = _guard([_suite, _start(1, 'hangs', 0)]);

    final reasons = _verdict(guard, exitCode: -9, stalledAfter: 21);

    expect(reasons.single, contains('no reporter event for 21 s'));
    expect(reasons.single, contains('test/a_test.dart | hangs'));
  });

  test('the run limit ends the run live and names the running tests', () {
    final guard = _guard([_suite, _start(1, 'fast', 0), _done(1, 10)]);
    bool mustEnd(int wall, int silence) => guard.mustEnd(
      wall: Duration(seconds: wall),
      silence: Duration(seconds: silence),
    );

    expect(mustEnd(180, 1), isFalse);
    expect(mustEnd(181, 1), isTrue);
    expect(mustEnd(30, 21), isTrue);
    guard.add(_start(2, 'still running', 10));
    final reasons = _verdict(guard, wall: 181, exitCode: -9);
    expect(reasons.single, contains('limit 180 s, run ended'));
    expect(reasons.single, contains('test/a_test.dart | still running'));
    expect(_verdict(guard, exitCode: 1).single, contains('exited with 1'));
  });

  test('the slowest tests come first, hidden entries are left out', () {
    final guard = _guard([
      _suite,
      _start(1, 'loading test/a_test.dart', 0),
      _done(1, 9000, hidden: true),
      _start(2, 'quick', 9000),
      _done(2, 9100),
      _start(3, 'slower', 9100),
      _done(3, 12100),
    ]);

    expect(
      [for (final t in guard.slowest(5)) '$t'],
      ['3.0 s  test/a_test.dart | slower', '0.1 s  test/a_test.dart | quick'],
    );
  });

  test(
    'shuffle: a given seed is kept, otherwise a random one; replay names it',
    () {
      expect(shuffleSeed('4711'), 4711);
      expect(shuffleSeed(null, () => 99), 99);
      expect(shuffleSeed(''), isPositive);
      expect(
        shuffleReplay(4711, ['test/core', '--exclude-tags=golden']),
        'dart tool/test_guard.dart --shuffle=4711 -- test/core --exclude-tags=golden',
      );
    },
  );
}
