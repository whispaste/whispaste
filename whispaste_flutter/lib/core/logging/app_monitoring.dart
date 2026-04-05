/// App-wide monitoring bootstrap — three-tier error capture + crash reporting.
///
/// Modeled after REDACTED-OTHER-PROJECT's `AppMonitoring.bootstrap()` pattern:
/// 1. Flutter framework errors → captureFlutterError
/// 2. Platform dispatcher errors → captureError
/// 3. Zone errors → captureError
///
/// All errors flow to [CrashReporter] which queues to SQLite → Supabase
/// relay → Discord webhook (no Sentry dependency).
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_logger.dart';
import 'crash_reporter.dart';

/// Crash relay URL — injected at build time via `--dart-define`.
///
/// Empty string in development = local queue only, no network.
const _crashRelayUrl = String.fromEnvironment(
  'CRASH_RELAY_URL',
  defaultValue: '',
);

/// Bootstraps the entire app inside a guarded error zone.
///
/// Call this instead of `main()` → `runApp()`. Example:
/// ```dart
/// Future<void> main() async {
///   await AppMonitoring.bootstrap(appRunner: () async {
///     runApp(const MyApp());
///   });
/// }
/// ```
class AppMonitoring {
  AppMonitoring._();

  static final _log = AppLogger('AppMonitoring');

  /// Full-app bootstrap: logging → crash reporter → error handlers → app.
  static Future<void> bootstrap({
    required Future<void> Function() appRunner,
  }) async {
    // 1. Configure logging (breadcrumbs, dev-tools output, auto-escalation).
    configureLogging();

    // 2. Initialize crash reporter.
    await CrashReporter.init(
      relayUrl: _crashRelayUrl,
      enabled: true,
    );

    // 3. Install global error handlers BEFORE runApp.
    _installGlobalErrorHandlers();

    // 4. Run app inside a guarded zone to catch uncaught async errors.
    await _runGuarded(appRunner);
  }

  static void _installGlobalErrorHandlers() {
    // Tier 1: Flutter framework errors (widget build errors, etc.)
    FlutterError.onError = (details) {
      // Keep default reporting in debug mode.
      FlutterError.presentError(details);
      CrashReporter.instance?.captureFlutterError(details);
    };

    // Tier 2: Platform dispatcher errors (isolate crashes, async gaps).
    PlatformDispatcher.instance.onError = (error, stack) {
      _log.error('Platform error', error, stack);
      CrashReporter.instance?.captureError(
        message: '$error',
        error: error,
        stackTrace: stack,
        severity: 'error',
        type: 'platform_error',
      );
      return true; // Handled — don't crash the app.
    };
  }

  /// Runs [appRunner] inside `runZonedGuarded` to catch stray async errors.
  static Future<void> _runGuarded(
    Future<void> Function() appRunner,
  ) async {
    await runZonedGuarded(
      appRunner,
      (error, stack) {
        _log.error('Uncaught zone error', error, stack);
        CrashReporter.instance?.captureError(
          message: '$error',
          error: error,
          stackTrace: stack,
          severity: 'error',
          type: 'zone_error',
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider observer — catches provider failures
// ---------------------------------------------------------------------------

/// Catches Riverpod provider errors and routes them to crash reporting.
///
/// Add to `ProviderScope(observers: [CrashProviderObserver()])`.
final class CrashProviderObserver extends ProviderObserver {
  const CrashProviderObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final name = context.provider.name ?? '${context.provider.runtimeType}';
    dev.log(
      'Provider failed: $name',
      name: 'Riverpod',
      error: error,
      stackTrace: stackTrace,
    );
    CrashReporter.instance?.captureError(
      message: 'Provider failed: $name: $error',
      error: error,
      stackTrace: stackTrace,
      severity: 'error',
      type: 'riverpod_error',
    );
  }
}
