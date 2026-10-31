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
/// endpoint is configured.
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
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_info.dart' as app_info;
import '../core/config/settings_provider.dart';
import '../core/l10n/locale_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/telemetry/onboarding_telemetry_buffer.dart';
import 'deploy_channel_service.dart';
import 'hardware_info_service.dart' as hw;
import 'speech_recommendation.dart' show ramMBProvider;
import 'telemetry_model_buckets.dart' show modelHardwareDimensions;
import 'update_channel_service.dart';

final _log = AppLogger('TelemetryService');

/// SharedPreferences key for [TelemetryService.sendDailyAlivePingIfDue]'s
/// dedup marker (T5).
const String _aliveLastPingDateKey = 'telemetry_alive_ping_last_date';

/// Settings keys that may be reported when a setting changes. Only the KEY
/// (never the value) is sent, and only keys on this static whitelist — an
/// unknown key is dropped so a future PII-bearing setting can never leak by
/// accident. Keys mirror the categorical Matomo signal, not user content.
const Set<String> kTrackableSettingKeys = {
  'stt_provider',
  'stt_engine',
  'cloud_stt_provider',
  'theme',
  'language',
  'auto_paste',
  'check_updates',
  'beta_updates',
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

// ---------------------------------------------------------------------------
// T4 — weekly-rotating cohort pseudonym (Matomo product analysis 2026-09-04)
// ---------------------------------------------------------------------------
//
// PRD Säule D forbids a persistent cross-session id, so returning-visitor
// measurement today relies on Matomo's own IP+UA heuristic (unreliable under
// dynamic IPs/NAT/VPN). This adds an alternative that exists only while usage
// sharing is on (default on, informed opt-out, CONTEXT §6.5): a categorical
// value that groups visits into weekly cohorts without ever identifying a
// device across weeks — a new value appears automatically every Monday, and
// the salt it's derived from never leaves the device (not sent to Matomo,
// not included in settings export/import).

/// Generates a random 32-hex-char salt for [PrivacySettings.cohortPseudonymSalt].
/// Persisted locally once (see `telemetryProvider`); never transmitted itself.
String generateCohortPseudonymSalt() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// ISO-8601 week label ("2026-W36") for [now] — the rotation boundary for the
/// cohort pseudonym. ISO week 1 is the week containing the year's first
/// Thursday; weeks run Monday..Sunday.
String _isoWeekLabel(DateTime now) {
  final date = DateTime.utc(now.year, now.month, now.day);
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final firstWeekMonday = firstThursday.subtract(
    Duration(days: (firstThursday.weekday + 6) % 7),
  );
  final week = (thursday.difference(firstWeekMonday).inDays / 7).floor() + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

/// Hashes [salt] together with the current ISO week into a categorical
/// dimension value — stable for one device for one calendar week, then
/// automatically different the next, so it can never accumulate into a
/// long-lived cross-session identifier. Only called while
/// `PrivacySettings.shareUsageStats` is true (same consent gate as every
/// other telemetry field).
String cohortPseudonymDimension({required String salt, DateTime? now}) {
  final week = _isoWeekLabel((now ?? DateTime.now()).toUtc());
  final digest = sha256.convert(utf8.encode('$salt|$week'));
  return digest.toString().substring(0, 16);
}

/// What [TelemetryService.sendEventNow] did with one event.
enum TelemetrySendResult {
  /// The endpoint accepted it.
  sent,

  /// Consent off or no endpoint configured: nothing may be sent.
  notAllowed,

  /// Network or server failure; the event may be retried later.
  failed,
}

final class TelemetryService {
  TelemetryService({
    required this.client,
    required this.endpointUrl,
    required this.siteId,
    required this.consentGranted,
    this.dimensions = const {},
    String? sessionVisitorId,
  }) : _sessionVisitorId = sessionVisitorId ?? _appSessionVisitorId;

  final http.Client client;
  final String endpointUrl;
  final int siteId;
  final bool consentGranted;

  /// Categorical custom dimensions (`dimension1`..`dimensionN`) appended to
  /// every request — all categories, never content.
  final Map<String, String> dimensions;

  /// Per-app-start visitor ID sent as Matomo `_id`; never persisted.
  final String _sessionVisitorId;

  final List<Future<void>> _pending = [];

  bool get _isConfigured => endpointUrl.isNotEmpty && siteId > 0;

  bool get _shouldDispatch => _isConfigured && consentGranted;

  /// Records a screen/page view (categorical path only).
  void trackPageView(String path) {
    if (!_shouldDispatch) return;
    _pending.add(
      _sendSafely({'url': 'app://whispaste$path', 'action_name': 'pageView'}),
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
    DateTime? at,
  }) {
    if (!_shouldDispatch) return;
    _pending.add(
      _sendSafely(
        _eventBody(
          category: category,
          action: action,
          name: name,
          value: value,
          at: at,
        ),
      ),
    );
  }

  /// Sends one event right away and reports whether the endpoint took it,
  /// so a caller can keep it for a later retry. Same consent and
  /// content rules as [trackEvent]; never throws.
  Future<TelemetrySendResult> sendEventNow({
    required String category,
    required String action,
    String? name,
    DateTime? at,
  }) async {
    if (!_shouldDispatch) return TelemetrySendResult.notAllowed;
    try {
      final response = await _send(
        _eventBody(category: category, action: action, name: name, at: at),
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return ok ? TelemetrySendResult.sent : TelemetrySendResult.failed;
    } catch (e) {
      _log.debug('telemetry request failed (non-fatal): $e');
      return TelemetrySendResult.failed;
    }
  }

  Map<String, String> _eventBody({
    required String category,
    required String action,
    String? name,
    int? value,
    DateTime? at,
  }) {
    final cdt = at == null
        ? null
        : (at.toUtc().millisecondsSinceEpoch ~/ 1000).toString();
    return <String, String>{
      'url': 'app://whispaste/event',
      'action_name': 'event',
      'e_c': category,
      'e_a': action,
      'e_n': ?name,
      'e_v': ?value?.toString(),
      'cdt': ?cdt,
    };
  }

  /// Records that a setting changed — only the key, only if whitelisted.
  void trackSettingChange(String settingKey) {
    if (!kTrackableSettingKeys.contains(settingKey)) return;
    trackEvent(category: 'settings', action: 'change', name: settingKey);
  }

  /// T5 (Matomo product analysis 2026-09-04): a single aggregated, non-event
  /// "alive" hit per calendar day — deliberately separate from the granular
  /// usage-sharing event stream above, for a coarser but steadier active-install
  /// signal (the ~4.000 Visits/90-Tage app-telemetry sample cannot itself be
  /// extrapolated into an install count).
  ///
  /// Still gated by [_shouldDispatch] like everything else in this class —
  /// an opted-out install sends no ping either. That means this undercounts
  /// the true active-install base by the opted-out share; a consent-
  /// independent count would need an explicit product/privacy-policy
  /// decision (PRD Säule D) that this service does not make unilaterally, so
  /// it was deliberately not implemented here.
  Future<void> sendDailyAlivePingIfDue(SharedPreferences prefs) async {
    if (!_shouldDispatch) return;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (prefs.getString(_aliveLastPingDateKey) == today) return;
    await _sendSafely({'url': 'app://whispaste/alive', 'action_name': 'alive'});
    await prefs.setString(_aliveLastPingDateKey, today);
  }

  Future<void> flush() async {
    if (_pending.isNotEmpty) {
      await Future.wait(_pending, eagerError: false);
      _pending.clear();
    }
  }

  /// Wraps [_send] so a request that outlives [flush] (e.g. this instance is
  /// discarded by a [telemetryProvider] rebuild before flush ever runs) can
  /// never surface as an unhandled async error — telemetry must not crash the
  /// app (see FLUTTER_WHISPASTE-B2: an orphaned request's DNS failure was
  /// reported to Sentry as fatal because it was never awaited by anything).
  Future<void> _sendSafely(Map<String, String> body) async {
    try {
      await _send(body);
    } catch (e) {
      _log.debug('telemetry request failed (non-fatal): $e');
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
  /// service's own consent/config gate still applies per emitted event.
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
  /// nothing was counted; the service's own consent/config gate still
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

/// The Matomo Dimension 6 ("Update Channel") value for a request — categorical
/// only (`stable`/`beta`/`n/a`), never content. Store and package-managed
/// builds (Homebrew Cask, Scoop — see [isExternallyManaged]) have no Sparkle
/// feed, so their update channel is reported as `n/a`; direct builds report
/// the persisted [UpdateChannel.name]. Extracted as a top-level pure function
/// so the categorical-discipline is unit-testable in isolation (PRD §12 Q3).
String updateChannelDimension({
  required DeployChannel deployChannel,
  required UpdateChannel updateChannel,
}) {
  if (isExternallyManaged(deployChannel)) return 'n/a';
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
  final gpu = ref.watch(hw.gpuInfoProvider).value;
  final ramMB = ref.watch(ramMBProvider);
  // Update channel loads async from SharedPreferences; fall back to the
  // stable default until it resolves (categorical — the dimension corrects on
  // the rebuild once prefs are in).
  final updateChannel =
      ref.watch(updateChannelProvider).value ?? UpdateChannel.stable;

  // T4: only compute/persist the cohort salt while consent holds (sharing is
  // on by default, CONTEXT §6.5) — an opted-out user gets no local salt.
  String? cohortDimension;
  final existingSalt = settings?.privacy.cohortPseudonymSalt;
  if (consent) {
    final salt = (existingSalt != null && existingSalt.isNotEmpty)
        ? existingSalt
        : generateCohortPseudonymSalt();
    if (existingSalt == null || existingSalt.isEmpty) {
      // Fire-and-forget: telemetry must never block app startup or crash on
      // a persistence failure (same rationale as `_sendSafely` below). The
      // freshly generated salt is still used for this session's dimension
      // immediately, so the very first opted-in session already cohorts
      // correctly even before the write lands.
      unawaited(
        ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(cohortPseudonymSalt: salt))
            .catchError(
              (e) => _log.debug('cohort salt persist failed (non-fatal): $e'),
            ),
      );
    }
    cohortDimension = cohortPseudonymDimension(salt: salt);
  }

  // Dimensions 8–12 (model and hardware classes) follow the same consent gate
  // as the cohort value: nothing is computed for an opted-out install.
  final modelHardware = consent
      ? modelHardwareDimensions(
          settings: settings ?? AppSettings.defaults,
          gpu: gpu,
          ramMB: ramMB,
          isMacOS: Platform.isMacOS,
        )
      : const <String, String>{};

  return TelemetryService(
    client: ref.watch(_telemetryHttpClientProvider),
    endpointUrl: _matomoUrl,
    siteId: int.tryParse(_matomoSiteId) ?? 0,
    consentGranted: consent,
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
      'dimension7': ?cohortDimension,
      ...modelHardware,
    },
  );
});

/// Onboarding telemetry hold (ticket 01 of `internal-notes`,
/// decision 5a). Events wait here until the privacy choice; the sender goes
/// through [telemetryProvider] so the consent gate still applies, with
/// each event keeping its original time.
final onboardingTelemetryBufferProvider = Provider<OnboardingTelemetryBuffer>(
  (ref) => OnboardingTelemetryBuffer(
    send: (event) {
      try {
        ref
            .read(telemetryProvider)
            .trackEvent(
              category: event.category,
              action: event.action,
              name: event.name,
              at: event.at,
            );
      } catch (e) {
        _log.debug('buffered onboarding telemetry skipped: $e');
      }
    },
  ),
);
