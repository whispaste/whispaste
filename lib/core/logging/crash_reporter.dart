/// Sentry-powered crash reporter with PII sanitization and GDPR consent gate.
///
/// Replaces the previous SQLite queue + Supabase relay + Discord architecture
/// with Sentry's native crash reporting pipeline.
///
/// Features:
/// - PII sanitization via `beforeSend` (regex-based sensitive data redaction)
/// - GDPR-compliant consent gate (nothing sent without consent)
/// - Path sanitization (user home, appdata, username → placeholders)
/// - Breadcrumb context from AppLogger ring buffer
/// - Anonymous device ID (MD5 hash of hostname, not a hardware identifier)
///
/// Architecture:
/// ```
/// AppLogger (error/fatal)
///     ↓
/// CrashReporter.captureError()
///     ↓
/// Sentry SDK (beforeSend → PII scrub → consent gate)
///     ↓
/// Sentry cloud (sentry.io)
/// ```
///
/// **App Store safety**: No raw user data is sent. Device ID is a
/// hash, not a hardware identifier. Crash data is categorized as
/// "not linked to user" in iOS privacy manifest.
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show containsSensitiveData;

import '../app_info.dart';
import 'breadcrumbs.dart';

// ---------------------------------------------------------------------------
// CrashReporter
// ---------------------------------------------------------------------------

/// Singleton crash reporter wrapping Sentry.
class CrashReporter {
  CrashReporter._();

  static CrashReporter? _instance;

  /// The active crash reporter instance. `null` if not initialized.
  static CrashReporter? get instance => _instance;

  bool _consentGranted = true;
  String _deviceId = '';

  /// Error cascade throttle — prevents exponential error storms
  /// (e.g., RenderFlex overflow → Sentry tree walk → deactivated widget →
  /// another Sentry capture → infinite cascade that freezes the UI).
  static int _errorCount = 0;
  static DateTime _errorWindowStart = DateTime.now();
  static const _maxErrorsPerWindow = 10;
  static const _errorWindowDuration = Duration(seconds: 2);

  /// Transaction throttle — hard SDK-side ceiling on performance events so
  /// no single session can blow through whispaste's Free-Tier span share,
  /// even if `tracesSampleRate` is misconfigured or a runaway loop kicks
  /// the sampler too often. Resets on app restart; for a true monthly
  /// guarantee, set a Spend Cap in the Sentry dashboard.
  ///
  /// 20 transactions/hour ≈ 1 sampled-transaction per 3 minutes of active
  /// use. A sampled transaction typically carries 5–15 child spans →
  /// ≤ ~300 spans/hour, well under the per-app Free-Tier slice.
  static int _txCount = 0;
  static DateTime _txWindowStart = DateTime.now();
  static const _maxTransactionsPerWindow = 20;
  static const _transactionWindowDuration = Duration(hours: 1);

  /// Per-instance ledger of in-flight Sentry futures, used exclusively by
  /// [flush] so tests can deterministically await fire-and-forget captures.
  /// Production code never reads this list — entries are dropped after they
  /// resolve to keep memory bounded.
  final List<Future<SentryId>> _pendingCaptures = [];

  void _trackCapture(Future<SentryId> future) {
    _pendingCaptures.add(future);
    future.whenComplete(() => _pendingCaptures.remove(future));
  }

  /// Awaits every Sentry capture started via [captureError] so far, so test
  /// assertions on the `beforeSend` spy list are not racing the SDK's async
  /// pipeline. No-op in production hot paths — callers there don't await
  /// captures anyway.
  @visibleForTesting
  Future<void> flush() async {
    while (_pendingCaptures.isNotEmpty) {
      await Future.wait(List.of(_pendingCaptures), eagerError: false);
    }
  }

  /// Whether crash reporting consent has been granted.
  /// Gate-controlled: nothing is sent when `false`.
  bool get consentGranted => _consentGranted;
  set consentGranted(bool value) {
    if (_consentGranted == value) return;
    _consentGranted = value;
    Sentry.configureScope((scope) {
      scope.setTag('consent', value ? 'granted' : 'revoked');
    });
    dev.log('Crash reporting consent: $value', name: 'CrashReporter');
  }

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Initializes the crash reporter. Call AFTER [SentryFlutter.init].
  static CrashReporter init() {
    final cr = CrashReporter._();
    cr._deviceId = _deriveDeviceId();

    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: cr._deviceId));
      scope.setTag('app_version', appVersion);
      scope.setTag('os', Platform.operatingSystem);
      scope.setTag('arch', currentArchTag());
      scope.setContexts('device_info', {
        'device_id': cr._deviceId,
        'dart_version': Platform.version.split(' ').first,
      });
    });

    _instance = cr;
    return cr;
  }

  /// Shuts down crash reporting.
  Future<void> dispose() async {
    await Sentry.close();
    _instance = null;
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Captures an error via Sentry. Non-blocking, fire-and-forget.
  ///
  /// [fingerprint] is **required** and must be sourced from
  /// `crash_fingerprints.dart` — inline string literals are a code-review
  /// failure. The list follows the Sentry SDK convention: a non-empty list
  /// of strings that controls how Sentry groups events into issues. An
  /// empty list lets Sentry's default grouping apply (still allowed, but
  /// reviewers must see the explicit empty-list choice).
  ///
  /// Why required: it pre-empts the WP-74/75 + WP-7B…7M cluster of
  /// duplicated Sentry issues that burned through the Free-Tier quota
  /// because ad-hoc capture sites kept inventing slightly different
  /// fingerprint spellings. See `.scratch/reliability-sprint/prd.md`
  /// — Modul 6.
  void captureError({
    required String message,
    required List<String> fingerprint,
    Object? error,
    StackTrace? stackTrace,
    String severity = 'error',
    String type = 'error',
    String? processName,
    Map<String, dynamic>? extras,
  }) {
    if (!_consentGranted) return;

    final sentryLevel = switch (severity) {
      'critical' || 'fatal' => SentryLevel.fatal,
      'error' => SentryLevel.error,
      'warning' => SentryLevel.warning,
      _ => SentryLevel.info,
    };

    if (error != null) {
      _trackCapture(
        Sentry.captureException(
          error,
          stackTrace: stackTrace,
          withScope: (scope) {
            scope.level = sentryLevel;
            scope.setTag('error_type', type);
            if (processName != null) scope.setTag('process', processName);
            if (extras != null) {
              scope.setContexts('extras', extras);
            }
            if (fingerprint.isNotEmpty) {
              scope.fingerprint = fingerprint;
            }
            // Attach recent log breadcrumbs for context.
            for (final line in getRecentBreadcrumbs().reversed.take(10)) {
              scope.addBreadcrumb(Breadcrumb(message: line));
            }
          },
        ),
      );
    } else {
      _trackCapture(
        Sentry.captureMessage(
          message,
          level: sentryLevel,
          withScope: (scope) {
            scope.setTag('error_type', type);
            if (processName != null) scope.setTag('process', processName);
            if (extras != null) {
              scope.setContexts('extras', extras);
            }
            if (fingerprint.isNotEmpty) {
              scope.fingerprint = fingerprint;
            }
          },
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Sentry beforeSend — PII sanitization + consent gate
  // -------------------------------------------------------------------------

  /// Sentry `beforeSend` callback — drops events with PII or without consent.
  ///
  /// Includes an error cascade throttle: if more than [_maxErrorsPerWindow]
  /// errors arrive within [_errorWindowDuration], excess events are dropped.
  /// This prevents exponential error storms (e.g., RenderFlex overflow →
  /// Sentry diagnostics → deactivated widget → another capture → freeze).
  ///
  /// Debug-mode events ARE sent (tagged `environment: 'development'`).
  /// Use Sentry's environment filter to separate dev from production.
  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    // Consent gate: drop events when user has opted out.
    if (_instance != null && !_instance!._consentGranted) return null;

    // Error cascade throttle — prevent exponential error storms.
    final now = DateTime.now();
    if (now.difference(_errorWindowStart) > _errorWindowDuration) {
      _errorWindowStart = now;
      _errorCount = 0;
    }
    _errorCount++;
    if (_errorCount > _maxErrorsPerWindow) return null;

    // Drop events containing API keys, tokens, or other secrets.
    final exceptions = event.exceptions;
    if (exceptions != null) {
      for (final ex in exceptions) {
        if (ex.value != null && containsSensitiveData(ex.value!)) {
          return null;
        }
      }
    }
    final message = event.message;
    if (message != null && containsSensitiveData(message.formatted)) {
      return null;
    }

    // Filter out user-facing toast messages (not real errors)
    final messageStr =
        event.message?.formatted ?? event.throwable?.toString() ?? '';
    if (messageStr.startsWith('TOAST:') ||
        messageStr.contains('Kein Audio erkannt') ||
        messageStr.contains('Etwas ist schiefgelaufen')) {
      // These are expected UX flows, not errors — suppress from Sentry
      return null;
    }

    return event;
  }

  // -------------------------------------------------------------------------
  // Sentry tracesSampler — primary runtime consent gate for performance data
  // -------------------------------------------------------------------------

  /// Sentry `tracesSampler` callback — runtime consent gate for transactions.
  ///
  /// Returns `0.0` when consent has been revoked so the SDK never even starts
  /// a transaction. No transaction → no child spans → nothing to leak. Returns
  /// `null` when consent is granted so the SDK falls through to
  /// `options.tracesSampleRate` (precedence rule from `sentry_traces_sampler.dart`).
  ///
  /// Why this exists in addition to [beforeSendTransaction]: a smoke test on
  /// 2026-05-18 showed that under sentry_flutter 9.20 with `bindToScope:true`
  /// transactions, child spans (including `db.sql.query` with full SQL payload
  /// and `http.client` Dio calls) could reach Sentry even after
  /// `beforeSendTransaction` returned `null`. Sampling at trace-start closes
  /// that window because no spans get created in the first place. The
  /// `beforeSendTransaction` consent check stays as a second-layer fallback
  /// for the race where consent flips mid-transaction.
  static double? tracesSampler(SentrySamplingContext context) {
    if (_instance != null && !_instance!._consentGranted) return 0.0;
    return null;
  }

  // -------------------------------------------------------------------------
  // Sentry beforeSendTransaction — Free-Tier span throttle + consent fallback
  // -------------------------------------------------------------------------

  /// Drops performance transactions once the per-session ceiling is hit.
  ///
  /// Performance events count against Sentry's Free-Tier span quota — this
  /// is a belt-and-braces guard on top of [_maxTransactionsPerWindow]
  /// sampling. Consent gate is honoured, identical to [beforeSend], as a
  /// fallback for transactions that started under consent=true and finish
  /// after consent=false (see [tracesSampler] for the primary gate).
  static SentryTransaction? beforeSendTransaction(
    SentryTransaction transaction,
    Hint hint,
  ) {
    if (_instance != null && !_instance!._consentGranted) return null;

    final now = DateTime.now();
    if (now.difference(_txWindowStart) > _transactionWindowDuration) {
      _txWindowStart = now;
      _txCount = 0;
    }
    _txCount++;
    if (_txCount > _maxTransactionsPerWindow) return null;

    return transaction;
  }

  // -------------------------------------------------------------------------
  // Private — helpers
  // -------------------------------------------------------------------------

  /// Derives a stable, anonymous device identifier from hostname.
  static String _deriveDeviceId() {
    try {
      final hostname = Platform.localHostname;
      final bytes = utf8.encode('${hostname}_whispaste');
      return md5.convert(bytes).toString().substring(0, 12);
    } on Exception {
      return 'unknown';
    }
  }
}
