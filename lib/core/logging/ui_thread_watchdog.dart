/// UI thread responsiveness watchdog.
///
/// Periodically schedules a timer callback on the main isolate. If the
/// callback fires significantly later than expected, the UI thread was
/// blocked by synchronous work. Logs a warning so we can diagnose jank
/// without the user having to reproduce it with DevTools attached.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Detects UI thread stalls by measuring timer callback jitter.
///
/// Call [start] once after the app is initialized and [dispose] on shutdown.
/// In test environments ([kIsWeb] or when [Platform.environment] contains
/// `FLUTTER_TEST`) the watchdog is a no-op.
class UiThreadWatchdog {
  UiThreadWatchdog._();

  static final _log = AppLogger('UiThreadWatchdog');

  static UiThreadWatchdog? _instance;

  /// Singleton accessor. The watchdog is process-global because there is
  /// exactly one UI thread per Flutter engine.
  static UiThreadWatchdog get instance => _instance ??= UiThreadWatchdog._();

  /// How often we probe the event loop.
  static const _interval = Duration(seconds: 2);

  /// Stall threshold — timer jitter above this is logged as a warning.
  static const _threshold = Duration(milliseconds: 500);

  Timer? _timer;
  final _stopwatch = Stopwatch();

  /// Whether the watchdog is currently active.
  bool get isRunning => _timer != null;

  /// Starts the watchdog. Safe to call multiple times — restarts if already
  /// running.
  void start() {
    // Skip in tests — Timer.periodic interferes with fake async.
    if (_isTestEnvironment) return;

    stop();
    _stopwatch
      ..reset()
      ..start();
    _timer = Timer.periodic(_interval, _onTick);
    _log.debug('UI thread watchdog started (interval=${_interval.inSeconds}s, '
        'threshold=${_threshold.inMilliseconds}ms)');
  }

  /// Stops the watchdog and releases the timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
  }

  /// Alias for [stop] to match widget lifecycle naming.
  void dispose() => stop();

  // ---------------------------------------------------------------------------

  void _onTick(Timer t) {
    final elapsed = _stopwatch.elapsed;
    // Expected elapsed = interval × tick count.
    final expected = _interval * t.tick;
    final jank = elapsed - expected;

    if (jank > _threshold) {
      _log.warning(
        'UI thread stall detected: ${jank.inMilliseconds}ms jank '
        '(tick #${t.tick}, monotonic elapsed=${elapsed.inMilliseconds}ms)',
      );
    }
  }

  /// Returns `true` when running inside `flutter test` or on the web.
  static bool get _isTestEnvironment {
    // kIsWeb is a const — tree-shaken in native builds.
    if (kIsWeb) return true;
    // flutter_test sets this zone value.
    if (Zone.current[#test.declarer] != null) return true;
    return false;
  }
}
