/// Wall-clock budgets for the fact guard's e-mail scan on 40k-character texts
/// (GS-032). The logic of the scan stays in
/// test/services/smart_mode/smart_mode_fact_guard_test.dart.
///
/// Not part of a test run: see benchmarks/README.md.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/smart_mode/smart_mode_fact_guard.dart';

void main() {
  group('e-mail scan budgets (GS-032)', () {
    test('a 40k text without @ is scanned in under 50 ms', () {
      final text = 'a' * 40000;
      final watch = Stopwatch()..start();
      smartModeFactViolations(input: text, output: text, checkNames: false);
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(50));
    });

    test('a 40k text with one @ is scanned in under 50 ms', () {
      final text = '${'a' * 40000}@evil.example';
      final watch = Stopwatch()..start();
      smartModeFactViolations(input: text, output: text, checkNames: false);
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(50));
    });
  });
}
