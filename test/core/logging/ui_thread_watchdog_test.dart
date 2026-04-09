import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/ui_thread_watchdog.dart';

void main() {
  group('UiThreadWatchdog', () {
    test('singleton returns same instance', () {
      final a = UiThreadWatchdog.instance;
      final b = UiThreadWatchdog.instance;
      expect(identical(a, b), isTrue);
    });

    test('is not running initially', () {
      final wd = UiThreadWatchdog.instance;
      expect(wd.isRunning, isFalse);
    });

    test('start is no-op in test environment', () {
      // The watchdog detects the flutter_test zone and skips activation.
      final wd = UiThreadWatchdog.instance;
      wd.start();
      expect(wd.isRunning, isFalse,
          reason: 'Watchdog should stay inactive inside flutter_test');
    });

    test('dispose is safe to call when not running', () {
      final wd = UiThreadWatchdog.instance;
      // Should not throw.
      wd.dispose();
      expect(wd.isRunning, isFalse);
    });

    test('stop is safe to call repeatedly', () {
      final wd = UiThreadWatchdog.instance;
      wd.stop();
      wd.stop();
      expect(wd.isRunning, isFalse);
    });
  });
}
