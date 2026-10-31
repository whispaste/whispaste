/// Sentry-powered crash reporter with PII sanitization and GDPR consent gate.
///
/// Replaces the previous SQLite queue + Supabase relay + Discord architecture
/// with Sentry's native crash reporting pipeline.
///
/// Features:
/// - PII sanitization via `beforeSend` (regex-based sensitive data redaction)
/// - GDPR-compliant consent gate: an opt-out stops Sentry (incl. the native
///   SDK) and keeps it from starting on later launches
/// - Path sanitization: home directory → `~`, account name → `<user>` in
///   messages, exception values and breadcrumbs ([scrubUserPaths])
/// - Breadcrumb context from AppLogger ring buffer
/// - Random per-install ID (install_id.dart), not derived from the machine
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

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show containsSensitiveData;

import '../app_info.dart';
import 'breadcrumbs.dart';
import 'crash_error_redaction.dart';
import 'crash_reporting_consent.dart';
import 'install_id.dart';
import 'user_path_scrubber.dart';

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
  CrashReportingConsentMarker? _consentMarker;

  /// Whether Sentry runs in this session. It is only started at app launch
  /// (see [AppMonitoring]), so an opt-in after an opted-out launch waits for
  /// the next start.
  bool _sentryRunning = false;

  /// Error cascade throttle — prevents exponential error storms
  /// (e.g., RenderFlex overflow → Sentry tree walk → deactivated widget →
  /// another Sentry capture → infinite cascade that freezes the UI).
  static int _errorCount = 0;

  /// Time source for the throttle windows; tests replace it instead of waiting.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
  static DateTime _errorWindowStart = clock();
  static const _maxErrorsPerWindow = 10;
  static const _errorWindowDuration = Duration(seconds: 2);

  /// Per-session ceiling: Sentry's error quota is shared by every project of
  /// the organisation (5,000 a month, no server-side filters on the plan), and
  /// in October 2026 a few devices repeating one state used it up, after which
  /// real crashes were dropped too. The same error is sent at most
  /// [_maxEventsPerKeyPerSession] times, and a session sends at most
  /// [_maxEventsPerSession] events in total. Reset by [init].
  static final Map<String, int> _sessionCounts = {};
  static int _sessionTotal = 0;
  static const _maxEventsPerKeyPerSession = 3;
  static const _maxEventsPerSession = 30;

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
  static DateTime _txWindowStart = clock();
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
    _consentMarker?.record(granted: value);
    if (!value && _sentryRunning) {
      // Stops the native SDK too: crash, app-hang and session reporting
      // never pass through the Dart callbacks that check consent.
      _sentryRunning = false;
      unawaited(Sentry.close());
    }
    dev.log('Crash reporting consent: $value', name: 'CrashReporter');
  }

  /// `true` after an opt-in while Sentry is not running in this session —
  /// reporting resumes on the next app start.
  bool get restartRequired => _consentGranted && !_sentryRunning;

  /// Set while the first-run privacy choice is still open (ticket 01 of
  /// `internal-notes`). Nothing is uploaded while held —
  /// not errors, not transactions. Crash reports cannot be replayed, so
  /// they are dropped, not queued.
  bool holdForPrivacyChoice = false;

  /// Consent granted and no privacy choice pending.
  bool get _uploadAllowed => _consentGranted && !holdForPrivacyChoice;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Initializes the crash reporter. Call AFTER [SentryFlutter.init], or
  /// without it when the user opted out before launch.
  ///
  /// [deployChannel] tags native crashes with the distribution channel
  /// (store/installer/packageManaged/portable) — e.g. some Windows
  /// flutter_windows.dll teardown crashes are known upstream to be specific
  /// to the MSIX/Store AppContainer sandbox (flutter/flutter #183313), which
  /// this tag lets us confirm or rule out. Passed in rather than detected
  /// here to keep this core/logging module free of a services/ dependency.
  ///
  /// [consentGranted] is `false` when the launch already knew about an
  /// opt-out and Sentry was not started; [consentMarker] persists later
  /// changes so the next launch can decide before starting Sentry.
  static CrashReporter init({
    String? deployChannel,
    bool consentGranted = true,
    CrashReportingConsentMarker? consentMarker,
  }) {
    final cr = CrashReporter._();
    _sessionCounts.clear();
    _sessionTotal = 0;
    cr._deviceId = readInstallId();
    cr._consentGranted = consentGranted;
    cr._consentMarker = consentMarker;
    cr._sentryRunning = Sentry.isEnabled;

    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: cr._deviceId));
      scope.setTag('app_version', appVersion);
      scope.setTag('os', Platform.operatingSystem);
      scope.setTag('arch', currentArchTag());
      if (deployChannel != null) {
        scope.setTag('deploy_channel', deployChannel);
      }
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
  /// fingerprint spellings. See `internal-notes`
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
    if (!_uploadAllowed) return;

    final sentryLevel = switch (severity) {
      'critical' || 'fatal' => SentryLevel.fatal,
      'error' => SentryLevel.error,
      'warning' => SentryLevel.warning,
      _ => SentryLevel.info,
    };

    // Sentry is for crashes and critical errors only (rule 2026-10-27):
    // warnings and info signals stay as context for a later real error.
    if (!_isReportableLevel(sentryLevel)) {
      Sentry.addBreadcrumb(
        Breadcrumb(message: message, level: sentryLevel, category: type),
      );
      return;
    }

    if (error != null) {
      _trackCapture(
        Sentry.captureException(
          redactForCrashReport(error),
          stackTrace: stackTrace,
          withScope: (scope) {
            scope.level = sentryLevel;
            scope.setTag('error_type', type);
            if (processName != null) scope.setTag('process', processName);
            if (extras != null) {
              scope.setContexts('extras', redactPathsInMap(extras));
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
              scope.setContexts('extras', redactPathsInMap(extras));
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
    if (_instance != null && !_instance!._uploadAllowed) return null;

    // Crashes and errors only; captureMessage with a lower level, from any
    // call site, never uses the shared quota.
    final level = event.level;
    if (level != null && !_isReportableLevel(level)) return null;

    // Error cascade throttle — prevent exponential error storms.
    final now = clock();
    if (now.difference(_errorWindowStart) > _errorWindowDuration) {
      _errorWindowStart = now;
      _errorCount = 0;
    }
    _errorCount++;
    if (_errorCount > _maxErrorsPerWindow) return null;

    // Remove SqliteException bound parameters (transcript and note text)
    // from every text field before the checks below. Covers unhandled errors
    // that sentry_flutter captures itself, log breadcrumbs and captureMessage
    // alike, not only the paths that pass through redactForCrashReport.
    _redactSqliteParameters(event);

    // Drop events whose exception or message holds an API key, token or
    // other secret. A breadcrumb with one is removed alone, below: the log
    // lines around a crash must not cost the crash its report.
    if (_carriesSensitiveData(event)) return null;
    event.breadcrumbs = _withoutSensitiveBreadcrumbs(event.breadcrumbs);

    // Filter out user-facing toast messages (not real errors)
    final messageStr =
        event.message?.formatted ?? event.throwable?.toString() ?? '';
    if (messageStr.startsWith('TOAST:') ||
        messageStr.contains('Kein Audio erkannt') ||
        messageStr.contains('Etwas ist schiefgelaufen')) {
      // These are expected UX flows, not errors — suppress from Sentry
      return null;
    }

    _scrubUserPaths(event);
    if (!_admitToSession(event)) return null;
    return event;
  }

  /// Clears the cascade throttle and the per-session ceilings so a test
  /// starts from an empty session.
  @visibleForTesting
  static void resetThrottlesForTesting() {
    _errorCount = 0;
    _errorWindowStart = clock();
    _sessionCounts.clear();
    _sessionTotal = 0;
  }

  /// Whether the exception values or the message hold a secret. Breadcrumbs
  /// are not checked here, see [_withoutSensitiveBreadcrumbs].
  static bool _carriesSensitiveData(SentryEvent event) {
    for (final ex in event.exceptions ?? const <SentryException>[]) {
      final value = ex.value;
      if (value != null && containsSensitiveData(value)) return true;
    }
    final message = event.message;
    if (message != null && containsSensitiveData(message.formatted)) {
      return true;
    }
    return false;
  }

  /// The breadcrumbs without any that hold a secret. Keeps the list as it is
  /// when none does, and returns null for a null list.
  static List<Breadcrumb>? _withoutSensitiveBreadcrumbs(
    List<Breadcrumb>? breadcrumbs,
  ) {
    if (breadcrumbs == null) return null;
    final kept = [
      for (final b in breadcrumbs)
        if (b.message == null || !containsSensitiveData(b.message!)) b,
    ];
    return kept.length == breadcrumbs.length ? breadcrumbs : kept;
  }

  static bool _isReportableLevel(SentryLevel level) =>
      level == SentryLevel.error || level == SentryLevel.fatal;

  /// Counts [event] against the per-session ceilings; false once the same
  /// error or the session as a whole has used its share.
  static bool _admitToSession(SentryEvent event) {
    if (_sessionTotal >= _maxEventsPerSession) return false;
    final key = _sessionKey(event);
    final seen = _sessionCounts[key] ?? 0;
    if (seen >= _maxEventsPerKeyPerSession) return false;
    _sessionCounts[key] = seen + 1;
    _sessionTotal++;
    return true;
  }

  /// Groups like Sentry would: the explicit fingerprint plus the first
  /// exception (type and value) or the message, so different errors that
  /// share a catch-all fingerprint keep their own share.
  static String _sessionKey(SentryEvent event) {
    final ex = event.exceptions?.firstOrNull;
    final text = ex != null
        ? '${ex.type}: ${ex.value ?? ''}'
        : (event.message?.formatted ?? '');
    final head = text.length > 160 ? text.substring(0, 160) : text;
    return '${(event.fingerprint ?? const []).join(',')}|$head';
  }

  /// Strips SqliteException bound parameters from the free-text parts of
  /// [event]: exception values, the message and breadcrumb messages.
  static void _redactSqliteParameters(SentryEvent event) {
    final message = event.message;
    if (message != null) {
      message.formatted = redactSqliteParametersInText(message.formatted);
    }
    for (final ex in event.exceptions ?? const <SentryException>[]) {
      final value = ex.value;
      if (value != null) ex.value = redactSqliteParametersInText(value);
    }
    for (final b in event.breadcrumbs ?? const <Breadcrumb>[]) {
      final text = b.message;
      if (text != null) b.message = redactSqliteParametersInText(text);
    }
  }

  /// Redacts paths in the free-text parts of [event]: the message, the
  /// transaction name, the culprit, the request, exception values, stack frame paths, and breadcrumb
  /// messages and string data. Home directories reach Sentry through log
  /// breadcrumbs and exception values, and file names through the same
  /// parts (see [redactPathsInText]).
  static void _scrubUserPaths(SentryEvent event) {
    final message = event.message;
    if (message != null) {
      message.formatted = redactPathsInText(message.formatted);
    }
    final transaction = event.transaction;
    if (transaction != null) event.transaction = redactPathsInText(transaction);
    final culprit = event.culprit;
    if (culprit != null) event.culprit = redactPathsInText(culprit);
    _redactRequest(event.request);
    for (final ex in event.exceptions ?? const <SentryException>[]) {
      final value = ex.value;
      if (value != null) ex.value = redactPathsInText(value);
      _redactFrames(ex.stackTrace);
    }
    for (final thread in event.threads ?? const <SentryThread>[]) {
      _redactFrames(thread.stacktrace);
    }
    for (final b in event.breadcrumbs ?? const <Breadcrumb>[]) {
      final text = b.message;
      if (text != null) b.message = redactPathsInText(text);
      final data = b.data;
      if (data != null) b.data = redactPathsInMap(data);
    }
  }

  /// Sentry `beforeBreadcrumb` callback: applies the same path redaction as
  /// [beforeSend] as each breadcrumb is recorded. Breadcrumbs are the main
  /// carrier of home paths (log lines, file operations), so they are cleaned
  /// at the source and do not depend on the event that later carries them.
  static Breadcrumb? beforeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
    if (breadcrumb == null) return null;
    final text = breadcrumb.message;
    if (text != null) breadcrumb.message = redactPathsInText(text);
    final data = breadcrumb.data;
    if (data != null) breadcrumb.data = redactPathsInMap(data);
    return breadcrumb;
  }

  /// Redacts paths in the URL, query, fragment and header values of
  /// [request]. Cookies and credential headers are dropped completely.
  static void _redactRequest(SentryRequest? request) {
    if (request == null) return;
    final url = request.url;
    if (url != null) request.url = redactPathsInText(url);
    final query = request.queryString;
    if (query != null) request.queryString = redactPathsInText(query);
    final fragment = request.fragment;
    if (fragment != null) request.fragment = redactPathsInText(fragment);
    request.cookies = null;
    final headers = request.headers;
    if (headers.isNotEmpty) {
      request.headers = {
        for (final e in headers.entries)
          if (!_credentialHeaders.contains(e.key.toLowerCase()))
            e.key: redactPathsInText(e.value),
      };
    }
  }

  static const _credentialHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
  };

  /// Redacts the local file paths of every frame in [trace]. Dart frames
  /// such as `package:whispaste/app.dart` stay readable.
  static void _redactFrames(SentryStackTrace? trace) {
    for (final frame in trace?.frames ?? const <SentryStackFrame>[]) {
      final absPath = frame.absPath;
      if (absPath != null) frame.absPath = redactPathsInText(absPath);
      final fileName = frame.fileName;
      if (fileName != null) frame.fileName = redactPathsInText(fileName);
    }
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
    if (_instance != null && !_instance!._uploadAllowed) return 0.0;
    return null;
  }

  // -------------------------------------------------------------------------
  // Sentry beforeSendTransaction — Free-Tier span throttle + consent fallback
  // -------------------------------------------------------------------------

  /// Drops performance transactions once the per-session ceiling is hit and
  /// strips the log breadcrumbs from the ones that are kept.
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
    if (_instance != null && !_instance!._uploadAllowed) return null;

    final now = clock();
    if (now.difference(_txWindowStart) > _transactionWindowDuration) {
      _txWindowStart = now;
      _txCount = 0;
    }
    _txCount++;
    if (_txCount > _maxTransactionsPerWindow) return null;

    // Traces only need timings. The scope copies the log breadcrumbs onto
    // every event, transactions included, but only [beforeSend] scrubs
    // them — so drop them here instead of shipping unchecked log lines.
    transaction.breadcrumbs = null;
    final name = transaction.transaction;
    if (name != null) transaction.transaction = redactPathsInText(name);
    return transaction;
  }
}
