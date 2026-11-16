/// Logic of [WpFindThrottle] (#640): sync for short texts, delayed and
/// abortable for long ones.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/find_replace.dart';
import 'package:whispaste/widgets/find_throttle.dart';

void main() {
  final long = 'ab ' * 10000;

  test('short text is searched synchronously', () {
    final throttle = WpFindThrottle();
    WpFindMatches? result;
    throttle.run('abc abc', 'abc', (m) => result = m);
    expect(result!.starts, [0, 4]);
  });

  test('long text waits for the delay and matches locate()', () {
    fakeAsync((async) {
      final throttle = WpFindThrottle();
      WpFindMatches? result;
      throttle.run(long, 'ab', (m) => result = m);
      expect(result, isNull);
      async.elapse(const Duration(milliseconds: 149));
      expect(result, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(result!.sameAs(WpFindReplace.locate(long, 'ab')), isTrue);
    });
  });

  test('new input aborts the pending search', () {
    fakeAsync((async) {
      final throttle = WpFindThrottle();
      final results = <int>[];
      throttle.run(long, 'a', (m) => results.add(m.count));
      async.elapse(const Duration(milliseconds: 100));
      throttle.run(long, 'ab', (m) => results.add(m.count));
      async.elapse(const Duration(seconds: 1));
      expect(results, [10000]);
    });
  });

  test('new input aborts a running scan', () {
    fakeAsync((async) {
      final throttle = WpFindThrottle(slice: Duration.zero);
      final results = <int>[];
      throttle.run(long, 'a', (m) => results.add(m.count));
      // Fires right after the scan's first slice (same instant, queued before
      // the scan's yield timer), so the abort lands mid-scan.
      Timer(
        const Duration(milliseconds: 150),
        () => throttle.run('short', 'x', (m) => results.add(-1)),
      );
      async.elapse(const Duration(seconds: 5));
      expect(results, [-1]);
    });
  });
}
