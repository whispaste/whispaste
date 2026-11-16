/// Writes uncaught framework and zone errors into the app log (#439).
///
/// Sentry only sees these errors while error reporting is switched on, and it
/// never writes them to the local log file. A broken frame (a black main
/// window) or an exception lost in an async gap then left no trace at all.
/// The handlers here run in front of whatever was installed before (Sentry,
/// the cascade guard or Flutter's defaults) and log at warning level: warnings
/// stay local breadcrumbs, so this adds no Sentry event of its own.
///
/// A storm of errors (one failing build per frame) is throttled: at most
/// [ErrorLogThrottle.maxPerWindow] entries per window, one line when the
/// throttle starts dropping, and the dropped count with the next entry.
library;

import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Rate limit for error log entries; time comes from `package:clock`.
class ErrorLogThrottle {
  ErrorLogThrottle({
    this.maxPerWindow = 5,
    this.window = const Duration(seconds: 10),
  });

  final int maxPerWindow;
  final Duration window;

  DateTime? _windowStart;
  int _inWindow = 0;
  int _dropped = 0;

  /// Decides about one error. [ErrorLogDecision.log] is false while the
  /// window's budget is spent.
  ErrorLogDecision next() {
    final now = clock.now();
    final start = _windowStart;
    if (start == null || now.difference(start) >= window) {
      _windowStart = now;
      _inWindow = 0;
    }
    _inWindow++;
    if (_inWindow > maxPerWindow) {
      _dropped++;
      return ErrorLogDecision(
        log: false,
        droppedBefore: 0,
        startsDropping: _inWindow == maxPerWindow + 1,
      );
    }
    final dropped = _dropped;
    _dropped = 0;
    return ErrorLogDecision(
      log: true,
      droppedBefore: dropped,
      startsDropping: false,
    );
  }
}

/// Outcome of [ErrorLogThrottle.next].
@immutable
class ErrorLogDecision {
  const ErrorLogDecision({
    required this.log,
    required this.droppedBefore,
    required this.startsDropping,
  });

  /// Whether this error gets its own log entry.
  final bool log;

  /// Errors dropped since the last entry, reported along with this one.
  final int droppedBefore;

  /// True for the first dropped error of a window, which logs one notice.
  final bool startsDropping;
}

final _log = AppLogger('UncaughtError');

void _record(
  ErrorLogThrottle throttle,
  AppLogger log,
  String source,
  Object error,
  StackTrace? stack,
) {
  try {
    final decision = throttle.next();
    if (decision.startsDropping) {
      log.warning(
        '$source errors are coming in a burst; further ones are counted, '
        'not logged, for up to ${throttle.window.inSeconds} s',
      );
    }
    if (!decision.log) return;
    final dropped = decision.droppedBefore > 0
        ? ' (${decision.droppedBefore} earlier ones not logged)'
        : '';
    // Only the error kind: the message text can carry user content.
    log.warning('$source error: ${errorKind(error)}$dropped', null, stack);
  } on Object {
    // Logging must never turn one error into a second one; the original
    // error still reaches the next handler, which is all that is left.
    return;
  }
}

/// Wraps [next] so every framework error is logged before it runs on.
FlutterExceptionHandler wrapFlutterErrorHandler(
  FlutterExceptionHandler? next, {
  required ErrorLogThrottle throttle,
  AppLogger? log,
}) {
  final logger = log ?? _log;
  return (FlutterErrorDetails details) {
    _record(throttle, logger, 'Framework', details.exception, details.stack);
    (next ?? FlutterError.presentError)(details);
  };
}

/// Wraps [next] so every uncaught zone error (async errors that reach
/// [PlatformDispatcher.onError]) is logged before it runs on. Without a
/// previous handler the error stays unhandled, as before.
ErrorCallback wrapPlatformErrorHandler(
  ErrorCallback? next, {
  required ErrorLogThrottle throttle,
  AppLogger? log,
}) {
  final logger = log ?? _log;
  return (Object error, StackTrace stack) {
    _record(throttle, logger, 'Zone', error, stack);
    return next?.call(error, stack) ?? false;
  };
}

/// Installs both wrappers in front of the current handlers. Call it after
/// Sentry and the cascade guard are in place, or before the app runs when
/// error reporting is switched off. One throttle covers both sources, since
/// a storm often shows up in both. The engine's own dispatcher is used
/// (the binding's is the same object in the app; the test binding's wrapper
/// does not forward the setter).
void installErrorLogForwarding() {
  final throttle = ErrorLogThrottle();
  FlutterError.onError = wrapFlutterErrorHandler(
    FlutterError.onError,
    throttle: throttle,
  );
  final platform = PlatformDispatcher.instance;
  platform.onError = wrapPlatformErrorHandler(
    platform.onError,
    throttle: throttle,
  );
}
