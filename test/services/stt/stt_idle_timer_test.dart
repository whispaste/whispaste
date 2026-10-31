/// Unit tests for SttIdleTimer.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/stt_idle_timer.dart';

void main() {
  group('SttIdleTimer', () {
    test('isActive is false before start()', () {
      final timer = SttIdleTimer();
      expect(timer.isActive, isFalse);
    });

    test('isActive is true after start()', () {
      final timer = SttIdleTimer();
      timer.start(const Duration(seconds: 60), () {});
      expect(timer.isActive, isTrue);
      timer.cancel();
    });

    test('isActive is false after cancel()', () {
      final timer = SttIdleTimer();
      timer.start(const Duration(seconds: 60), () {});
      timer.cancel();
      expect(timer.isActive, isFalse);
    });

    test('callback fires after timeout elapses', () async {
      final timer = SttIdleTimer();
      var fired = false;
      timer.start(const Duration(milliseconds: 30), () => fired = true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, isTrue);
    });

    test('cancel() prevents callback from firing', () async {
      final timer = SttIdleTimer();
      var fired = false;
      timer.start(const Duration(milliseconds: 50), () => fired = true);
      timer.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fired, isFalse);
    });

    test('start() re-arms when called while already active', () async {
      final timer = SttIdleTimer();
      var count = 0;
      timer.start(const Duration(milliseconds: 30), () => count++);
      // Re-arm before the first fires.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      timer.start(const Duration(milliseconds: 30), () => count++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Only the second timer should have fired.
      expect(count, 1);
      timer.cancel();
    });

    test('reset() re-arms with the same duration', () async {
      final timer = SttIdleTimer();
      var fired = false;
      timer.start(const Duration(milliseconds: 40), () => fired = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      timer.reset();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Should not have fired yet (reset extended it).
      expect(fired, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fired, isTrue);
      timer.cancel();
    });

    test('reset() is a no-op when start() was never called', () {
      final timer = SttIdleTimer();
      // Must not throw.
      expect(() => timer.reset(), returnsNormally);
    });

    test('cancel() is a no-op when no timer is running', () {
      final timer = SttIdleTimer();
      expect(() => timer.cancel(), returnsNormally);
    });
  });
}
