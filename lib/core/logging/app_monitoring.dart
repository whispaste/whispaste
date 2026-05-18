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
import 'package:flutter/widgets.dart';
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
    //
    // Free-Tier budget (per organization, shared across all projects):
    //   ~5k errors/month, ~10k performance units (spans)/month.
    //
    // Sampling math for whispaste's share (assuming 5 sibling apps):
    //   tracesSampleRate=0.005 → 1 of 200 transactions sampled.
    //   A typical sampled transaction emits ~5–15 child spans (drift + dio).
    //   Even at 1k actions/user/day × 10 users → 50 sampled transactions/day
    //   × ~10 spans = 500 spans/day ≈ 15k/month. That still busts the share,
    //   so we ALSO install `beforeSendTransaction` as a hard per-session
    //   throttle (see CrashReporter.beforeSendTransaction). For a *real*
    //   monthly guarantee, set a Spend Cap in the Sentry dashboard.
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.environment = kReleaseMode ? 'production' : 'development';
        options.release = sentryRelease;
        options.dist = _currentArch();
        options.sendDefaultPii = false;
        options.attachScreenshot = false;
        // Attach the widget tree (structure only — no text content) to error
        // events. Privacy-safe and very helpful for UI bugs.
        // ignore: experimental_member_use
        options.attachViewHierarchy = true;
        // Shrink per-event payload to stay well under the 1 GB attachment
        // bucket and reduce noise in issue grouping.
        options.maxBreadcrumbs = 30;
        options.beforeSend = CrashReporter.beforeSend;
        options.beforeSendTransaction = CrashReporter.beforeSendTransaction;
        // tracesSampler takes precedence over tracesSampleRate when both are
        // set — see sentry_traces_sampler.dart. Our sampler returns 0.0 on
        // consent=false (blocks the trace entirely so no spans can leak) and
        // null otherwise (falls through to tracesSampleRate below).
        options.tracesSampler = CrashReporter.tracesSampler;
        options.tracesSampleRate = kReleaseMode ? 0.005 : 0.05;
        options.enableAutoPerformanceTracing = true;
        options.enableAutoNativeBreadcrumbs = true;
      },
      appRunner: () async {
        // 3. Initialize crash reporter (configures Sentry scope context).
        CrashReporter.init();
        _log.info('Sentry crash reporting initialized');

        // 4. Install cascade guard around Sentry's FlutterError.onError.
        _installCascadeGuard();

        // 5. Run the actual app.
        await appRunner();
      },
    );
  }

  static String _currentArch() {
    const is64 = 0x7FFFFFFFFFFFFFFF > 0;
    return is64 ? 'x64' : 'x86';
  }

  // ── Cascade guard ────────────────────────────────────────────────────────
  // Sentry's FlutterErrorIntegration walks the widget tree for every error
  // BEFORE beforeSend runs. During this walk, deactivated/disposed widgets
  // trigger secondary FlutterErrors → exponential cascade → UI thread freeze.
  //
  // The guard wraps FlutterError.onError AFTER SentryFlutter.init and drops
  // errors when re-entrancy is detected or the rate exceeds the threshold.
  // Also guards PlatformDispatcher.onError (Sentry uses both mechanisms).
  // ────────────────────────────────────────────────────────────────────────

  static const _cascadeMax = 3;
  static const _cascadeWindow = Duration(milliseconds: 500);

  static void _installCascadeGuard() {
    _guardFlutterErrorHandler();
    _guardPlatformDispatcherHandler();
  }

  static void _guardFlutterErrorHandler() {
    final sentryHandler = FlutterError.onError;
    if (sentryHandler == null) return;

    bool inHandler = false;
    int count = 0;
    DateTime windowStart = DateTime.now();

    FlutterError.onError = (FlutterErrorDetails details) {
      // Re-entrancy guard: a secondary error triggered by the handler
      // itself (e.g., Sentry tree walk hitting a deactivated widget).
      if (inHandler) {
        debugPrint(
          '[CascadeGuard] Re-entrant error suppressed: '
          '${details.exceptionAsString().split('\n').first}',
        );
        return;
      }

      // Volume guard: drop excess errors in rapid succession.
      final now = DateTime.now();
      if (now.difference(windowStart) > _cascadeWindow) {
        windowStart = now;
        count = 0;
      }
      count++;
      if (count > _cascadeMax) {
        debugPrint(
          '[CascadeGuard] Suppressed (${count}x): '
          '${details.exceptionAsString().split('\n').first}',
        );
        return;
      }

      inHandler = true;
      try {
        sentryHandler(details);
      } finally {
        inHandler = false;
      }
    };
  }

  static void _guardPlatformDispatcherHandler() {
    final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
    final sentryHandler = platformDispatcher.onError;
    if (sentryHandler == null) return;

    bool inHandler = false;
    int count = 0;
    DateTime windowStart = DateTime.now();

    platformDispatcher.onError = (Object error, StackTrace stack) {
      if (inHandler) {
        debugPrint(
          '[CascadeGuard] Re-entrant platform error suppressed: '
          '${error.toString().split('\n').first}',
        );
        return true; // handled — prevent process termination
      }

      final now = DateTime.now();
      if (now.difference(windowStart) > _cascadeWindow) {
        windowStart = now;
        count = 0;
      }
      count++;
      if (count > _cascadeMax) {
        debugPrint(
          '[CascadeGuard] Platform error suppressed (${count}x): '
          '${error.toString().split('\n').first}',
        );
        return true;
      }

      inHandler = true;
      try {
        return sentryHandler(error, stack);
      } finally {
        inHandler = false;
      }
    };
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
