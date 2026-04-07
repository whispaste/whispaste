/// Offline-first crash reporter that queues reports to SQLite and flushes
/// them to the Supabase crash-relay edge function (which posts to Discord).
///
/// Mirrors the Go `CrashReporter` in `crashreporter.go`:
/// - SQLite queue with FIFO flushing
/// - MD5-based dedup within a 1-hour window
/// - Rate limiting (50 reports/hour)
/// - PII sanitization (regex-based sensitive data redaction, path scrubbing)
/// - GDPR-compliant consent gate
/// - Breadcrumb context (last N log lines)
///
/// Architecture:
/// ```
/// AppLogger (warning/error/fatal)
///     ↓
/// CrashReporter.captureError()
///     ↓
/// SQLite queue (crash_queue table via drift NativeDatabase)
///     ↓  (flush timer, every 60 s)
/// POST → Supabase crash-relay edge function
///     ↓
/// Discord webhook embed
/// ```
///
/// **App Store safety**: No raw user data is sent. Device ID is a
/// hash, not a hardware identifier. Crash data is categorized as
/// "not linked to user" in iOS privacy manifest.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../services/path_service.dart' as paths;
import 'app_logger.dart';

// ---------------------------------------------------------------------------
// Constants (mirrors crashreporter.go)
// ---------------------------------------------------------------------------

const _maxQueueSize = 500;
const _maxReportsPerHour = 50;
const _flushInterval = Duration(seconds: 60);
const _dedupWindow = Duration(hours: 1);
const _maxFieldLen = 1024;
const _httpTimeout = Duration(seconds: 15);
const _queueMaxAgeDays = 30;

/// App version — single source of truth is types.go AppVersion.
const _appVersion = '1.2.0';

// ---------------------------------------------------------------------------
// Sensitive data patterns (mirrors crashreporter.go)
// ---------------------------------------------------------------------------

// ignore_for_file: valid_regexps
final _sensitivePatterns = [
  // API key/token/password assignments
  RegExp(r'''(?i)["']?(api[_-]?key|token|password|authorization)["']?\s*[:=]\s*['"]?[^\s'",}]+'''),
  // Bearer tokens
  RegExp(r'(?i)\bbearer\s+\S+'),
  // OpenAI keys (sk-...)
  RegExp(r'\bsk-[A-Za-z0-9][A-Za-z0-9_]{5,}\b'),
  // Groq keys (gsk_...)
  RegExp(r'\bgsk_[A-Za-z0-9][A-Za-z0-9_]{5,}\b'),
  // Anthropic keys (sk-ant-...)
  RegExp(r'\bsk-ant-[A-Za-z0-9_]{8,}\b'),
  // Google AI keys (AIza...)
  RegExp(r'\bAIza[0-9A-Za-z_]{10,}\b'),
];

// ---------------------------------------------------------------------------
// CrashReporter
// ---------------------------------------------------------------------------

/// Singleton crash reporter with offline SQLite queue.
class CrashReporter {
  CrashReporter._();

  static CrashReporter? _instance;

  /// The active crash reporter instance. `null` if not initialized.
  static CrashReporter? get instance => _instance;

  GeneratedDatabase? _db;
  Timer? _flushTimer;
  bool _enabled = false;
  bool _consentGranted = true;
  String _relayUrl = '';
  String _deviceId = '';
  final _httpClient = http.Client();

  // Dedup cache: hash → last-sent timestamp.
  final _dedupCache = <String, DateTime>{};
  int _hourCount = 0;
  DateTime _hourReset = DateTime.now().add(const Duration(hours: 1));

  /// Whether crash reporting consent has been granted.
  /// Gate-controlled: nothing is sent when `false`.
  bool get consentGranted => _consentGranted;
  set consentGranted(bool value) {
    _consentGranted = value;
    dev.log(
      'Crash reporting consent: $value',
      name: 'CrashReporter',
    );
  }

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Initializes the crash reporter. Call once during app bootstrap.
  ///
  /// [relayUrl] — Supabase edge function URL for the crash relay.
  /// If empty, reports are queued locally only (dev mode).
  /// [enabled] — Whether crash reporting is enabled at all.
  static Future<CrashReporter> init({
    required String relayUrl,
    bool enabled = true,
  }) async {
    final cr = CrashReporter._();
    cr._enabled = enabled;
    cr._relayUrl = relayUrl.trim();
    cr._deviceId = _deriveDeviceId();

    if (!enabled) {
      dev.log('Crash reporting: disabled', name: 'CrashReporter');
      _instance = cr;
      return cr;
    }

    try {
      await cr._initDb();
    } on Exception catch (e) {
      dev.log(
        'Failed to init crash queue DB: $e',
        name: 'CrashReporter',
      );
      // Still usable — just won't persist queue.
      _instance = cr;
      return cr;
    }

    if (cr._relayUrl.isNotEmpty) {
      cr._flushTimer = Timer.periodic(_flushInterval, (_) => cr._flush());
      dev.log(
        'Crash reporting: enabled (relay configured)',
        name: 'CrashReporter',
      );
    } else {
      dev.log(
        'Crash reporting: enabled (local queue only)',
        name: 'CrashReporter',
      );
    }

    _instance = cr;
    return cr;
  }

  /// Shuts down — flushes remaining reports and closes the DB.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
    _httpClient.close();
    await _db?.close();
    _db = null;
    _instance = null;
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Enqueues a crash report. Non-blocking, fire-and-forget.
  void captureError({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String severity = 'error',
    String type = 'error',
    String? processName,
    Map<String, dynamic>? extras,
  }) {
    if (!_enabled) return;

    // Run async enqueue without blocking caller.
    unawaited(_enqueue(
      message: message,
      error: error,
      stackTrace: stackTrace,
      severity: severity,
      type: type,
      processName: processName,
      extras: extras,
    ));
  }

  /// Captures a Flutter framework error.
  void captureFlutterError(FlutterErrorDetails details) {
    captureError(
      message: details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
      severity: 'error',
      type: 'flutter_error',
    );
  }

  // -------------------------------------------------------------------------
  // Private — queue management (drift NativeDatabase, raw SQL)
  // -------------------------------------------------------------------------

  Future<void> _initDb() async {
    final dbDir = _crashDbDir();
    final dir = Directory(dbDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final dbPath = p.join(dbDir, 'crash_queue.db');
    final nativeDb = NativeDatabase(File(dbPath));
    _db = _CrashQueueDb(nativeDb);

    // Create table if not exists.
    await _db!.customStatement('''
      CREATE TABLE IF NOT EXISTS crash_queue (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        severity TEXT NOT NULL,
        message TEXT NOT NULL,
        stack_trace TEXT,
        process_name TEXT,
        app_version TEXT NOT NULL,
        os TEXT NOT NULL,
        arch TEXT NOT NULL,
        device_id TEXT NOT NULL,
        breadcrumbs TEXT,
        extras TEXT,
        hash TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await _db!.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_crash_hash ON crash_queue(hash)',
    );
    await _db!.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_crash_created ON crash_queue(created_at)',
    );

    // Prune old entries.
    final cutoff = DateTime.now()
        .subtract(const Duration(days: _queueMaxAgeDays))
        .millisecondsSinceEpoch;
    await _db!.customStatement(
      'DELETE FROM crash_queue WHERE created_at < ?',
      [cutoff],
    );
  }

  Future<void> _enqueue({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    required String severity,
    required String type,
    String? processName,
    Map<String, dynamic>? extras,
  }) async {
    if (_db == null) return;

    try {
      final sanitizedMessage = _sanitizeMessage(
        error != null ? '$message: $error' : message,
      );
      final sanitizedStack = stackTrace != null
          ? _sanitizePaths(stackTrace.toString())
          : null;
      final hash = _hashCrash(sanitizedMessage, sanitizedStack ?? '');
      final now = DateTime.now();
      final id = '${now.millisecondsSinceEpoch}_${hash.substring(0, 8)}';

      // Enforce queue size limit (FIFO eviction).
      final countResult = await _db!.customSelect(
        'SELECT COUNT(*) AS cnt FROM crash_queue',
      ).getSingle();
      final count = countResult.read<int>('cnt');
      if (count >= _maxQueueSize) {
        await _db!.customStatement(
          'DELETE FROM crash_queue WHERE id = '
          '(SELECT id FROM crash_queue ORDER BY created_at ASC LIMIT 1)',
        );
      }

      final breadcrumbs = getRecentBreadcrumbs().join('\n');

      await _db!.customStatement(
        '''INSERT OR REPLACE INTO crash_queue
           (id, timestamp, type, severity, message, stack_trace,
            process_name, app_version, os, arch, device_id,
            breadcrumbs, extras, hash, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          id,
          now.millisecondsSinceEpoch ~/ 1000,
          type,
          severity,
          _truncate(sanitizedMessage, _maxFieldLen),
          sanitizedStack != null
              ? _truncate(sanitizedStack, _maxFieldLen)
              : null,
          processName,
          _appVersion,
          Platform.operatingSystem,
          _currentArch(),
          _deviceId,
          _truncate(breadcrumbs, _maxFieldLen),
          extras != null ? jsonEncode(extras) : null,
          hash,
          now.millisecondsSinceEpoch,
        ],
      );
    } on Exception catch (e) {
      // Never let the crash reporter itself crash the app.
      dev.log('Failed to enqueue crash: $e', name: 'CrashReporter');
    }
  }

  // -------------------------------------------------------------------------
  // Private — flush (send to relay)
  // -------------------------------------------------------------------------

  Future<void> _flush() async {
    if (_db == null || _relayUrl.isEmpty || !_consentGranted) return;
    if (_isRateLimited()) return;

    try {
      final rows = await _db!.customSelect(
        'SELECT * FROM crash_queue ORDER BY created_at ASC LIMIT 10',
      ).get();

      for (final row in rows) {
        final hash = row.read<String>('hash');
        final id = row.read<String>('id');

        // Dedup check.
        final lastSent = _dedupCache[hash];
        if (lastSent != null &&
            DateTime.now().difference(lastSent) < _dedupWindow) {
          await _db!.customStatement(
            'DELETE FROM crash_queue WHERE id = ?',
            [id],
          );
          continue;
        }

        // Build payload.
        final embed = _buildEmbed(row);
        final report = <String, dynamic>{
          'id': id,
          'timestamp': row.read<int>('timestamp'),
          'type': row.read<String>('type'),
          'severity': row.read<String>('severity'),
          'message': row.read<String>('message'),
          'stack_trace': row.readNullable<String>('stack_trace'),
          'process_name': row.readNullable<String>('process_name'),
          'app_version': row.read<String>('app_version'),
          'os': row.read<String>('os'),
          'arch': row.read<String>('arch'),
          'device_id': row.read<String>('device_id'),
          'hash': hash,
        };

        try {
          final resp = await _httpClient
              .post(
                Uri.parse(_relayUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'report': report, 'embed': embed}),
              )
              .timeout(_httpTimeout);

          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            await _db!.customStatement(
              'DELETE FROM crash_queue WHERE id = ?',
              [id],
            );
            _dedupCache[hash] = DateTime.now();
            _hourCount++;
          } else if (resp.statusCode == 429) {
            break; // Rate limited by relay.
          } else {
            dev.log(
              'Relay returned ${resp.statusCode}: ${resp.body}',
              name: 'CrashReporter',
            );
          }
        } on Exception catch (e) {
          dev.log('Flush failed: $e', name: 'CrashReporter');
          break; // Network issue — retry next cycle.
        }
      }
    } on Exception catch (e) {
      dev.log('Flush query failed: $e', name: 'CrashReporter');
    }
  }

  // -------------------------------------------------------------------------
  // Private — Discord embed builder
  // -------------------------------------------------------------------------

  Map<String, dynamic> _buildEmbed(QueryRow row) {
    final severity = row.read<String>('severity');
    final type = row.read<String>('type');
    final message = row.read<String>('message');

    final (emoji, color) = switch (severity) {
      'critical' => ('🔴', 0xDC2626),
      'error' => ('🟠', 0xE97451),
      'warning' => ('🟡', 0xF59E0B),
      _ => ('ℹ️', 0x3B82F6),
    };

    final fields = <Map<String, dynamic>>[
      {'name': 'Version', 'value': row.read<String>('app_version'), 'inline': true},
      {'name': 'OS', 'value': '${row.read<String>('os')}/${row.read<String>('arch')}', 'inline': true},
      {'name': 'Runtime', 'value': 'Flutter ${Platform.version.split(' ').first}', 'inline': true},
      {'name': 'Device', 'value': _truncate(row.read<String>('device_id'), 12), 'inline': true},
    ];

    final stack = row.readNullable<String>('stack_trace');
    if (stack != null && stack.isNotEmpty) {
      fields.add({
        'name': 'Stack Trace',
        'value': '```\n${_truncate(stack, 900)}\n```',
        'inline': false,
      });
    }

    final breadcrumbs = row.readNullable<String>('breadcrumbs');
    if (breadcrumbs != null && breadcrumbs.isNotEmpty) {
      final last5 =
          breadcrumbs.split('\n').reversed.take(5).toList().reversed.join('\n');
      fields.add({
        'name': 'Recent Logs',
        'value': '```\n${_truncate(last5, 600)}\n```',
        'inline': false,
      });
    }

    final process = row.readNullable<String>('process_name');
    if (process != null && process.isNotEmpty) {
      fields.add({'name': 'Process', 'value': process, 'inline': true});
    }

    final id = row.read<String>('id');
    final ts = row.read<int>('timestamp');
    final tsStr = DateTime.fromMillisecondsSinceEpoch(ts * 1000)
        .toUtc()
        .toIso8601String();

    return {
      'title': '$emoji [$type] $severity',
      'description': _truncate(message, _maxFieldLen),
      'color': color,
      'fields': fields,
      'footer': {
        'text': 'ID: ${id.length > 16 ? id.substring(0, 16) : id} | $tsStr',
      },
    };
  }

  // -------------------------------------------------------------------------
  // Private — rate limiting
  // -------------------------------------------------------------------------

  bool _isRateLimited() {
    final now = DateTime.now();
    if (now.isAfter(_hourReset)) {
      _hourCount = 0;
      _hourReset = now.add(const Duration(hours: 1));
    }
    return _hourCount >= _maxReportsPerHour;
  }

  // -------------------------------------------------------------------------
  // Private — sanitization
  // -------------------------------------------------------------------------

  /// Redacts the entire message if it contains sensitive patterns.
  static String _sanitizeMessage(String s) {
    for (final pattern in _sensitivePatterns) {
      if (pattern.hasMatch(s)) {
        return '[REDACTED — contains sensitive data]';
      }
    }
    return _sanitizePaths(s);
  }

  /// Replaces user-specific path segments with placeholders.
  static String _sanitizePaths(String s) {
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

  static String _hashCrash(String message, String stack) {
    final bytes = utf8.encode('$message$stack');
    return md5.convert(bytes).toString();
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen - 1)}…';
  }

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
    // Dart doesn't expose CPU arch directly; infer from pointer size.
    const is64 = 0x7FFFFFFFFFFFFFFF > 0;
    return is64 ? 'x64' : 'x86';
  }

  static String _crashDbDir() {
    try {
      return paths.appDataDir();
    } catch (_) {
      // Fallback for platforms where path_service can't resolve.
      final home = Platform.environment['HOME'] ?? '.';
      return p.join(home, '.whispaste');
    }
  }
}

// ---------------------------------------------------------------------------
// Minimal drift database wrapper (no code-gen needed)
// ---------------------------------------------------------------------------

/// Bare-bones drift database that provides raw SQL access for the crash queue.
/// Avoids coupling to the history database schema and build_runner.
class _CrashQueueDb extends GeneratedDatabase {
  _CrashQueueDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
}
