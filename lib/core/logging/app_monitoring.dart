/// App-wide monitoring bootstrap — Sentry-powered crash reporting.
///
/// [SentryFlutter.init] provides three-tier error capture:
/// 1. Flutter framework errors (FlutterError.onError)
/// 2. Platform dispatcher errors (PlatformDispatcher.onError)
/// 3. Zone errors (runZonedGuarded wrapper)
///
/// PII sanitization, consent gate, and breadcrumb context via [CrashReporter].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../app_info.dart';
import 'app_logger.dart';
import 'crash_reporter.dart';

/// Sentry DSN — public identifier, safe to embed in client code.
/// See: https://docs.sentry.io/concepts/key-terms/dsn-explainer/
const _sentryDsn =
    'https://1dc761fb2739811a24425fd32518f611@o4511065943441408.ingest.de.sentry.io/4511185948180560';

/// Bootstraps the entire app inside Sentry's guarded error zone.
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

  /// Full-app bootstrap: logging → Sentry → crash reporter → app.
  static Future<void> bootstrap({
    required Future<void> Function() appRunner,
  }) async {
    // 1. Configure logging (breadcrumbs, dev-tools output, file sink).
    await configureLogging();

    // 2. Initialize Sentry — wraps appRunner with error zone + handlers.
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.environment = kReleaseMode ? 'production' : 'development';
        options.release = 'whispaste@$appVersion';
        options.dist = _currentArch();
        options.sendDefaultPii = false;
        options.attachScreenshot = false;
        options.beforeSend = CrashReporter.beforeSend;
        options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
        options.enableAutoPerformanceTracing = true;
        options.enableAutoNativeBreadcrumbs = true;
      },
      appRunner: () async {
        // 3. Initialize crash reporter (configures Sentry scope context).
        CrashReporter.init();
        _log.info('Sentry crash reporting initialized');

        // 4. Run the actual app.
        await appRunner();
      },
    );
  }

  static String _currentArch() {
    const is64 = 0x7FFFFFFFFFFFFFFF > 0;
    return is64 ? 'x64' : 'x86';
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
    CrashReporter.instance?.captureError(
      message: 'Provider failed: $name: $error',
      error: error,
      stackTrace: stackTrace,
      severity: 'error',
      type: 'riverpod_error',
    );
  }
}
