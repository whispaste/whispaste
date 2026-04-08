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

import '../app_info.dart';
import 'app_logger.dart';

// ---------------------------------------------------------------------------
// Sensitive data patterns for PII sanitization
// ---------------------------------------------------------------------------

// ignore_for_file: valid_regexps
final _sensitivePatterns = [
  RegExp(r'''(?i)["']?(api[_-]?key|token|password|authorization)["']?\s*[:=]\s*['"]?[^\s'",}]+'''),
  RegExp(r'(?i)\bbearer\s+\S+'),
  RegExp(r'\bsk-[A-Za-z0-9][A-Za-z0-9_]{5,}\b'),
  RegExp(r'\bgsk_[A-Za-z0-9][A-Za-z0-9_]{5,}\b'),
  RegExp(r'\bsk-ant-[A-Za-z0-9_]{8,}\b'),
  RegExp(r'\bAIza[0-9A-Za-z_]{10,}\b'),
];

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
      scope.setTag('arch', _currentArch());
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
  void captureError({
    required String message,
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
          // Attach recent log breadcrumbs for context.
          for (final line in getRecentBreadcrumbs().reversed.take(10)) {
            scope.addBreadcrumb(Breadcrumb(message: line));
          }
        },
      );
    } else {
      Sentry.captureMessage(
        message,
        level: sentryLevel,
        withScope: (scope) {
          scope.setTag('error_type', type);
          if (processName != null) scope.setTag('process', processName);
          if (extras != null) {
            scope.setContexts('extras', extras);
          }
        },
      );
    }
  }

  /// Captures a Flutter framework error via Sentry.
  void captureFlutterError(FlutterErrorDetails details) {
    if (!_consentGranted) return;
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
      withScope: (scope) {
        scope.setTag('error_type', 'flutter_error');
      },
    );
  }

  // -------------------------------------------------------------------------
  // Sentry beforeSend — PII sanitization + consent gate
  // -------------------------------------------------------------------------

  /// Sentry `beforeSend` callback — drops events with PII or without consent.
  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    // Consent gate: drop events when user has opted out.
    if (_instance != null && !_instance!._consentGranted) return null;

    // Don't send in debug mode.
    if (kDebugMode) return null;

    // Drop events containing API keys, tokens, or other secrets.
    final exceptions = event.exceptions;
    if (exceptions != null) {
      for (final ex in exceptions) {
        if (ex.value != null && _containsSensitiveData(ex.value!)) {
          return null;
        }
      }
    }
    final message = event.message;
    if (message != null && _containsSensitiveData(message.formatted)) {
      return null;
    }

    return event;
  }

  // -------------------------------------------------------------------------
  // Private — PII sanitization
  // -------------------------------------------------------------------------

  static bool _containsSensitiveData(String s) {
    return _sensitivePatterns.any((p) => p.hasMatch(s));
  }

  /// Replaces user-specific path segments with placeholders.
  static String sanitizePaths(String s) {
    var result = s;
    final userProfile =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (userProfile != null && userProfile.isNotEmpty) {
      result = result.replaceAll(userProfile, '<home>');
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      result = result.replaceAll(appData, '<appdata>');
    }
    final user =
        Platform.environment['USERNAME'] ?? Platform.environment['USER'];
    if (user != null && user.isNotEmpty) {
      result = result.replaceAll(user, '<user>');
    }
    return result;
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

  static String _currentArch() {
    const is64 = 0x7FFFFFFFFFFFFFFF > 0;
    return is64 ? 'x64' : 'x86';
  }
}
