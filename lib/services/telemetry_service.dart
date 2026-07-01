/// Cookieless usage-telemetry sender (Matomo `matomo.php` endpoint). Named
/// *telemetry* — not *analytics* — to stay distinct from the in-app analytics
/// dashboard (`analyticsProvider` / `AnalyticsData`), which is an unrelated
/// local feature.
///
/// Hard privacy rules (PRD Säule D): no persistent cookie, no `pk_id`, no user
/// id. A per-app-start random `_id` (16 hex chars, never persisted to disk or
/// registry) is sent so Matomo can count visits reliably; it does not enable
/// cross-session tracking. Only aggregated event counters + categorical
/// dimensions ever leave the app, and only when [consentGranted] is true, the
/// endpoint is configured, and OS Do-Not-Track is off.
///
/// **Volume**: hot-path events (recording outcome, insertion, voice-note,
/// snippet, history-copy, FAB click) are NOT sent per occurrence. They are
/// tallied in [TelemetrySessionAggregator] and flushed as one aggregated event
/// per distinct tuple at shutdown — so a session with 200 dictations produces a
/// handful of hits, not ~800. Only genuinely low-frequency signals
/// (lifecycle/start, settings change, onboarding) are sent immediately. The
/// hard negative list
/// (transcribed text, audio, history, tags, notes, API keys, concrete hotkeys,
/// file paths, cursor position, target app) is enforced structurally: the
/// public API only accepts categories/actions/buckets, never free-form content.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/app_info.dart' as app_info;
import '../core/config/settings_provider.dart';
import '../core/l10n/locale_provider.dart';
import 'deploy_channel_service.dart';
import 'update_channel_service.dart';

/// Settings keys that may be reported when a setting changes. Only the KEY
/// (never the value) is sent, and only keys on this static whitelist — an
/// unknown key is dropped so a future PII-bearing setting can never leak by
/// accident. Keys mirror the categorical Matomo signal, not user content.
const Set<String> kTrackableSettingKeys = {
  'stt_provider',
  'cloud_stt_provider',
  'theme',
  'language',
  'auto_paste',
  'check_updates',
  'share_usage_stats',
  'error_reporting',
  'hotkey_mode',
};

/// Generates a cryptographically random 16-character hex string for use as
/// a per-session Matomo visitor ID. Called once at app-start via
/// [_appSessionVisitorId]; never written to disk.
String _generateSessionVisitorId() {
  final random = Random.secure();
  return List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Single visitor ID for the current app process (in-memory only).
final String _appSessionVisitorId = _generateSessionVisitorId();

final class TelemetryService {
  TelemetryService({
    required this.client,
    required this.endpointUrl,
    required this.siteId,
    required this.consentGranted,
    required this.dntActive,
    this.dimensions = const {},
    String? sessionVisitorId,
  }) : _sessionVisitorId = sessionVisitorId ?? _appSessionVisitorId;

  final http.Client client;
  final String endpointUrl;
  final int siteId;
  final bool consentGranted;
  final bool dntActive;

  /// Categorical custom dimensions (`dimension1`..`dimensionN`) appended to
  /// every request — all categories, never content.
  final Map<String, String> dimensions;

  /// Per-app-start visitor ID sent as Matomo `_id`; never persisted.
  final String _sessionVisitorId;

  final List<Future<http.Response>> _pending = [];

  bool get _isConfigured => endpointUrl.isNotEmpty && siteId > 0;

  bool get _shouldDispatch => _isConfigured && consentGranted && !dntActive;

  /// Records a screen/page view (categorical path only).
  void trackPageView(String path) {
    if (!_shouldDispatch) return;
    _pending.add(
      _send({'url': 'app://whispaste$path', 'action_name': 'pageView'}),
    );
  }

  /// Records an aggregated event. [category]/[action] are required categories;
  /// [name] is an optional category label (e.g. provider, outcome, step id);
  /// [value] is an optional numeric bucket. None of these may carry content —
  /// callers pass enums/buckets only.
  void trackEvent({
    required String category,
    required String action,
    String? name,
    int? value,
  }) {
    if (!_shouldDispatch) return;
    final body = <String, String>{
      'url': 'app://whispaste/event',
      'action_name': 'event',
      'e_c': category,
      'e_a': action,
      'e_n': ?name,
      'e_v': ?value?.toString(),
    };
    _pending.add(_send(body));
  }

  /// Records that a setting changed — only the key, only if whitelisted.
  void trackSettingChange(String settingKey) {
    if (!kTrackableSettingKeys.contains(settingKey)) return;
    trackEvent(category: 'settings', action: 'change', name: settingKey);
  }

  Future<void> flush() async {
    if (_pending.isNotEmpty) {
      await Future.wait(_pending, eagerError: false);
      _pending.clear();
    }
  }

  Future<http.Response> _send(Map<String, String> body) {
    final url = Uri.parse(
      '$endpointUrl/matomo.php',
    ).replace(queryParameters: {'idsite': '$siteId', 'rec': '1'});

    return client.post(
      url,
      headers: {'User-Agent': 'WhisPaste'},
      body: {
        ...body,
        ...dimensions,
        '_id': _sessionVisitorId,
        'apiv': '1',
        'send_image': '0',
        'rand': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Session aggregator — hot-path volume control
// ---------------------------------------------------------------------------

/// Accumulates **hot-path** usage counters in memory during the app session and
/// emits them as a small set of aggregated events at shutdown — instead of one
/// network hit per recording/insertion/click. This keeps Matomo volume
/// proportional to app *runs* (~a handful of hits per session) rather than to
/// dictation count (which could be hundreds per day for a heavy user).
///
/// Only categorical `(category, action, name)` tuples are counted — never
/// content, exactly like [TelemetryService.trackEvent]. The session count is
/// sent as the Matomo event `value`.
///
/// Long-lived (one instance per app process via
/// [telemetrySessionAggregatorProvider]): the counters must survive the
/// [telemetryProvider] rebuilds triggered by settings changes (consent toggle,
/// locale, provider).
final class TelemetrySessionAggregator {
  final Map<(String, String, String?), int> _counts = {};

  /// Increments the in-memory counter for a categorical event tuple. Infallible
  /// (no I/O) — safe to call from the recording hot path without try/catch.
  /// Content must never be passed — same rules as [TelemetryService.trackEvent].
  void count({required String category, required String action, String? name}) {
    _counts.update((category, action, name), (n) => n + 1, ifAbsent: () => 1);
  }

  /// Drains all accumulated counters into [service] as aggregated events
  /// (`value` = session count) and clears them. Call right before
  /// [TelemetryService.flush] at shutdown. No-op when nothing was counted; the
  /// service's own consent/DNT/config gate still applies per emitted event.
  void drainTo(TelemetryService service) {
    if (_counts.isEmpty) return;
    for (final entry in _counts.entries) {
      final (category, action, name) = entry.key;
      service.trackEvent(
        category: category,
        action: action,
        name: name,
        value: entry.value,
      );
    }
    _counts.clear();
  }

  /// Drains accumulated counters into [service] and awaits the sender's
  /// pending HTTP requests (best-effort). Convenience for shutdown / lifecycle
  /// flush points so callers don't repeat the drain→flush sequence. No-op when
  /// nothing was counted; the service's own consent/DNT/config gate still
  /// applies per emitted event.
  Future<void> drainAndFlush(TelemetryService service) async {
    drainTo(service);
    await service.flush();
  }

  /// Snapshot of the current counters — test-only.
  @visibleForTesting
  Map<(String, String, String?), int> get debugCounts =>
      Map.unmodifiable(_counts);
}

// ---------------------------------------------------------------------------
// Runtime wiring (Riverpod)
// ---------------------------------------------------------------------------

/// Matomo endpoint + site id come from `--dart-define` so the on-prem server
/// coordinates (kept in the separate `Projekte/matomo` folder) never live in
/// the repo. Absent config → the service is a No-Op.
const String _matomoUrl = String.fromEnvironment('WHISPASTE_MATOMO_URL');
const String _matomoSiteId = String.fromEnvironment('WHISPASTE_MATOMO_SITE_ID');

/// Override for testing OS Do-Not-Track detection.
@visibleForTesting
bool? telemetryDntOverride;

/// Best-effort OS Do-Not-Track honouring. Desktop OSes expose no uniform DNT
/// signal; respect the conventional `DNT=1` environment variable when present.
bool telemetryDntActive() {
  if (telemetryDntOverride != null) return telemetryDntOverride!;
  return Platform.environment['DNT'] == '1';
}

/// The Matomo Dimension 6 ("Update Channel") value for a request — categorical
/// only (`stable`/`beta`/`n/a`), never content. Store builds have no Sparkle
/// feed, so their update channel is reported as `n/a`; direct builds report the
/// persisted [UpdateChannel.name]. Extracted as a top-level pure function so
/// the categorical-discipline is unit-testable in isolation (PRD §12 Q3).
String updateChannelDimension({
  required DeployChannel deployChannel,
  required UpdateChannel updateChannel,
}) {
  if (deployChannel == DeployChannel.store) return 'n/a';
  return updateChannel.name;
}

/// Long-lived HTTP client for telemetry — created once, closed on dispose.
final _telemetryHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Process-lifetime aggregator for hot-path usage counters. Deliberately
/// independent of [telemetryProvider] (which rebuilds on every settings change)
/// so per-session counters are not reset by a consent/locale/provider toggle.
/// Drained into the telemetry service at shutdown (see app.dart / floating
/// button quit paths).
final telemetrySessionAggregatorProvider = Provider<TelemetrySessionAggregator>(
  (ref) => TelemetrySessionAggregator(),
);

/// The telemetry sender, rebuilt whenever settings change so the live consent
/// toggle and categorical dimensions (provider/locale) stay current.
final telemetryProvider = Provider<TelemetryService>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final consent = settings?.privacy.shareUsageStats ?? false;
  final channel = ref.watch(deployChannelProvider);
  final locale = ref.watch(localeProvider);
  // Update channel loads async from SharedPreferences; fall back to the
  // stable default until it resolves (categorical — the dimension corrects on
  // the rebuild once prefs are in).
  final updateChannel =
      ref.watch(updateChannelProvider).value ?? UpdateChannel.stable;

  return TelemetryService(
    client: ref.watch(_telemetryHttpClientProvider),
    endpointUrl: _matomoUrl,
    siteId: int.tryParse(_matomoSiteId) ?? 0,
    consentGranted: consent,
    dntActive: telemetryDntActive(),
    dimensions: {
      'dimension1': app_info.appVersion,
      'dimension2': Platform.operatingSystem,
      'dimension3': settings?.stt.provider ?? 'unknown',
      'dimension4': channel.name,
      'dimension5': locale.languageCode,
      'dimension6': updateChannelDimension(
        deployChannel: channel,
        updateChannel: updateChannel,
      ),
    },
  );
});
