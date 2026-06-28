/// Cookieless, identifierless usage-telemetry sender (Matomo `matomo.php`
/// endpoint). Named *telemetry* — not *analytics* — to stay distinct from the
/// in-app analytics dashboard (`analyticsProvider` / `AnalyticsData`), which is
/// an unrelated local feature.
///
/// Hard privacy rules (PRD Säule D): no cookie, no `_id`/`pk_id`, no visitor
/// id, no user id. Only aggregated event counters + categorical dimensions
/// ever leave the app, and only when [consentGranted] is true, the endpoint is
/// configured, and OS Do-Not-Track is off. The hard negative list (transcribed
/// text, audio, history, tags, notes, API keys, concrete hotkeys, file paths,
/// cursor position, target app) is enforced structurally: the public API only
/// accepts categories/actions/buckets, never free-form content.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/app_info.dart' as app_info;
import '../core/config/settings_provider.dart';
import '../core/l10n/locale_provider.dart';
import 'deploy_channel_service.dart';

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

final class TelemetryService {
  TelemetryService({
    required this.client,
    required this.endpointUrl,
    required this.siteId,
    required this.consentGranted,
    required this.dntActive,
    this.dimensions = const {},
  });

  final http.Client client;
  final String endpointUrl;
  final int siteId;
  final bool consentGranted;
  final bool dntActive;

  /// Categorical custom dimensions (`dimension1`..`dimensionN`) appended to
  /// every request — all categories, never content.
  final Map<String, String> dimensions;

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
        'apiv': '1',
        'send_image': '0',
        'rand': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
  }
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

/// Long-lived HTTP client for telemetry — created once, closed on dispose.
final _telemetryHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// The telemetry sender, rebuilt whenever settings change so the live consent
/// toggle and categorical dimensions (provider/locale) stay current.
final telemetryProvider = Provider<TelemetryService>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final consent = settings?.privacy.shareUsageStats ?? false;
  final channel = ref.watch(deployChannelProvider);
  final locale = ref.watch(localeProvider);

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
    },
  );
});
