import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/services/update_channel_service.dart';

TelemetryService _makeService({
  required http.Client client,
  String endpointUrl = 'https://example.matomo.cloud',
  int siteId = 1,
  bool consentGranted = true,
  bool dntActive = false,
  Map<String, String> dimensions = const {},
  String? sessionVisitorId,
}) {
  return TelemetryService(
    client: client,
    endpointUrl: endpointUrl,
    siteId: siteId,
    consentGranted: consentGranted,
    dntActive: dntActive,
    dimensions: dimensions,
    sessionVisitorId: sessionVisitorId,
  );
}

void main() {
  group(
    'updateChannelDimension — Dimension 6 discipline (categorical only)',
    () {
      test('store deploy channel → n/a (no Sparkle feed in store builds)', () {
        for (final update in UpdateChannel.values) {
          expect(
            updateChannelDimension(
              deployChannel: DeployChannel.store,
              updateChannel: update,
            ),
            'n/a',
          );
        }
      });

      test('installer + stable → stable', () {
        expect(
          updateChannelDimension(
            deployChannel: DeployChannel.installer,
            updateChannel: UpdateChannel.stable,
          ),
          'stable',
        );
      });

      test('portable + beta → beta', () {
        expect(
          updateChannelDimension(
            deployChannel: DeployChannel.portable,
            updateChannel: UpdateChannel.beta,
          ),
          'beta',
        );
      });

      test('never emits free-form content — only the categorical tokens '
          'stable/beta/n/a', () {
        const allowed = {'stable', 'beta', 'n/a'};
        for (final deploy in DeployChannel.values) {
          for (final update in UpdateChannel.values) {
            final value = updateChannelDimension(
              deployChannel: deploy,
              updateChannel: update,
            );
            expect(allowed, contains(value), reason: 'emitted: $value');
          }
        }
      });
    },
  );

  group('TelemetryService', () {
    test('does not send HTTP request when consentGranted is false', () async {
      var httpCallMade = false;
      final client = MockClient((_) async {
        httpCallMade = true;
        return http.Response('', 200);
      });
      final service = _makeService(client: client, consentGranted: false);

      service.trackPageView('/test');

      await Future.delayed(Duration.zero);
      expect(httpCallMade, false);
    });

    test(
      'does not send HTTP request when DNT is active, even with consent',
      () async {
        var httpCallMade = false;
        final client = MockClient((_) async {
          httpCallMade = true;
          return http.Response('', 200);
        });
        final service = _makeService(
          client: client,
          consentGranted: true,
          dntActive: true,
        );

        service.trackPageView('/test');

        await Future.delayed(Duration.zero);
        expect(httpCallMade, false);
      },
    );

    test(
      'does not send HTTP request when endpointUrl is empty (not configured)',
      () async {
        var httpCallMade = false;
        final client = MockClient((_) async {
          httpCallMade = true;
          return http.Response('', 200);
        });
        final service = _makeService(client: client, endpointUrl: '');

        service.trackPageView('/test');

        await Future.delayed(Duration.zero);
        expect(httpCallMade, false);
      },
    );

    test(
      'does not send HTTP request when siteId is 0 (not configured)',
      () async {
        var httpCallMade = false;
        final client = MockClient((_) async {
          httpCallMade = true;
          return http.Response('', 200);
        });
        final service = _makeService(client: client, siteId: 0);

        service.trackPageView('/test');

        await Future.delayed(Duration.zero);
        expect(httpCallMade, false);
      },
    );

    test(
      'sends cookieless request without pk_id or session cookies when consent granted',
      () async {
        http.Request? capturedRequest;
        final client = MockClient((req) async {
          capturedRequest = req;
          return http.Response('', 200);
        });
        final service = _makeService(client: client);

        service.trackPageView('/test');
        await service.flush();

        expect(capturedRequest, isNotNull);

        final url = capturedRequest!.url.toString();
        final body = capturedRequest!.body;

        // No cookies in the request headers
        final allHeaders = capturedRequest!.headers.keys
            .join(', ')
            .toLowerCase();
        expect(allHeaders.contains('cookie'), false);

        // No pk_id in URL or body (persistent cross-session identifier)
        expect(url.contains('pk_id'), false);
        expect(body.contains('pk_id'), false);

        // No session cookie parameter
        expect(body.contains('_cvar'), false);

        // _id is the per-session visitor ID — present but ephemeral (not persisted).
        expect(body.contains('_id='), true);
      },
    );

    test('sends page view to correct Matomo endpoint path', () async {
      http.Request? capturedRequest;
      final client = MockClient((req) async {
        capturedRequest = req;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      service.trackPageView('/settings');
      await service.flush();

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.url.toString(), contains('/matomo.php'));
    });

    test('request URL contains siteId parameter', () async {
      http.Request? capturedRequest;
      final client = MockClient((req) async {
        capturedRequest = req;
        return http.Response('', 200);
      });
      final service = _makeService(client: client, siteId: 7);

      service.trackPageView('/test');
      await service.flush();

      final url = capturedRequest!.url.toString();
      expect(url.contains('idsite=7'), true);
    });

    test(
      'request body does not contain persistent cross-session identifiers',
      () async {
        http.Request? capturedRequest;
        final client = MockClient((req) async {
          capturedRequest = req;
          return http.Response('', 200);
        });
        final service = _makeService(client: client);

        service.trackPageView('/test');
        await service.flush();

        final body = capturedRequest!.body;
        // uid and cid are persistent user/client identifiers — never sent.
        expect(body.contains('uid='), false);
        expect(body.contains('cid='), false);
        // _id is the ephemeral per-session visitor ID — present and expected.
        expect(body.contains('_id='), true);
      },
    );
  });

  group('TelemetryService events', () {
    test('trackEvent sends e_c/e_a/e_n/e_v and stays cookieless', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);
      service.trackEvent(
        category: 'pipeline',
        action: 'success',
        name: 'ok',
        value: 3,
      );
      await service.flush();

      final params = Uri.splitQueryString(captured!.body);
      expect(params['e_c'], 'pipeline');
      expect(params['e_a'], 'success');
      expect(params['e_n'], 'ok');
      expect(params['e_v'], '3');
      final headers = captured!.headers.keys.join(',').toLowerCase();
      expect(headers.contains('cookie'), false);
      expect(captured!.body.contains('pk_id'), false);
      // _id is the ephemeral per-session visitor ID — present and expected.
      expect(captured!.body.contains('_id='), true);
    });

    test('trackEvent omits name and value when null', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);
      service.trackEvent(category: 'lifecycle', action: 'start');
      await service.flush();

      final params = Uri.splitQueryString(captured!.body);
      expect(params['e_c'], 'lifecycle');
      expect(params.containsKey('e_n'), false);
      expect(params.containsKey('e_v'), false);
    });

    test('custom dimensions are appended to every event', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      final service = _makeService(
        client: client,
        dimensions: {'dimension1': '1.2.41', 'dimension3': 'On Device'},
      );
      service.trackEvent(category: 'lifecycle', action: 'start');
      await service.flush();

      final params = Uri.splitQueryString(captured!.body);
      expect(params['dimension1'], '1.2.41');
      expect(params['dimension3'], 'On Device');
    });

    test('trackSettingChange sends only whitelisted keys', () async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('', 200);
      });
      final service = _makeService(client: client);
      service.trackSettingChange('stt_provider'); // whitelisted
      service.trackSettingChange('api_key_openai'); // NOT whitelisted → dropped
      service.trackSettingChange('custom_vocabulary'); // NOT whitelisted
      await service.flush();

      expect(bodies, hasLength(1));
      final params = Uri.splitQueryString(bodies.single);
      expect(params['e_c'], 'settings');
      expect(params['e_a'], 'change');
      expect(params['e_n'], 'stt_provider');
    });

    test('beta_updates is whitelisted — it was previously missing, so the '
        'Beta-Updates toggle in Settings silently sent nothing', () async {
      expect(kTrackableSettingKeys, contains('beta_updates'));

      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('', 200);
      });
      final service = _makeService(client: client);
      service.trackSettingChange('beta_updates');
      await service.flush();

      expect(bodies, hasLength(1));
      final params = Uri.splitQueryString(bodies.single);
      expect(params['e_n'], 'beta_updates');
    });

    test(
      'event payloads can never carry transcript text, audio, or history',
      () async {
        http.Request? captured;
        final client = MockClient((req) async {
          captured = req;
          return http.Response('', 200);
        });
        // The transcription signal is purely categorical (outcome + bucket);
        // the API exposes no parameter that could carry the dictated text.
        final service = _makeService(
          client: client,
          dimensions: {'dimension3': 'On Device'},
        );
        service.trackEvent(
          category: 'pipeline',
          action: 'success',
          name: 'ok',
          value: 3,
        );
        await service.flush();

        final body = captured!.body.toLowerCase();
        for (final forbidden in [
          'secret',
          'dictated',
          'transcript',
          'audio',
          'history',
          'snippet',
          'note',
        ]) {
          expect(body.contains(forbidden), false, reason: 'leaked: $forbidden');
        }
      },
    );
  });

  // ── Aufgabe D: session visitor ID ─────────────────────────────────────────

  group('TelemetryService session visitor ID (Aufgabe D)', () {
    test('_id is a 16-character lowercase hex string', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      const fixedId = 'aabbccddeeff0011';
      final service = _makeService(client: client, sessionVisitorId: fixedId);

      service.trackPageView('/test');
      await service.flush();

      final params = Uri.splitQueryString(captured!.body);
      expect(params['_id'], fixedId);
      expect(params['_id']!.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(params['_id']!), true);
    });

    test(
      '_id is stable across multiple _send calls on the same instance',
      () async {
        final capturedIds = <String>[];
        final client = MockClient((req) async {
          final id = Uri.splitQueryString(req.body)['_id'];
          if (id != null) capturedIds.add(id);
          return http.Response('', 200);
        });
        const fixedId = '1234567890abcdef';
        final service = _makeService(client: client, sessionVisitorId: fixedId);

        service.trackPageView('/a');
        service.trackEvent(category: 'lifecycle', action: 'start');
        service.trackPageView('/b');
        await service.flush();

        expect(capturedIds, hasLength(3));
        expect(capturedIds.every((id) => id == fixedId), true);
      },
    );

    test('default _id passes 16-char hex validation', () async {
      // Tests that the auto-generated app-level ID has the correct shape.
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      // No sessionVisitorId override — uses _appSessionVisitorId.
      final service = _makeService(client: client);

      service.trackPageView('/shape-check');
      await service.flush();

      final id = Uri.splitQueryString(captured!.body)['_id'];
      expect(id, isNotNull);
      expect(id!.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), true);
    });
  });

  // ── Aufgabe E: flush im Shutdown-Pfad ─────────────────────────────────────
  //
  // Die Aufrufe von flush() in app.dart (onWindowClose) und
  // floating_button_service.dart (_quit) werden im Flutter-Engine-Kontext
  // ausgeführt und sind ohne vollständigen Widget-Test-Harness nicht
  // sinnvoll unit-testbar. Stattdessen wird flush() selbst abgedeckt.

  group('TelemetryService flush (Aufgabe E)', () {
    test(
      'flush completes all pending requests and clears the buffer',
      () async {
        var requestCount = 0;
        final client = MockClient((_) async {
          requestCount++;
          return http.Response('', 200);
        });
        final service = _makeService(client: client);

        service.trackEvent(category: 'lifecycle', action: 'start');
        service.trackPageView('/test');
        await service.flush();

        expect(requestCount, 2);

        // Second flush with empty buffer is a no-op.
        await service.flush();
        expect(requestCount, 2);
      },
    );
  });

  // ── Aufgabe F: Opt-out-Toggle-Reihenfolge ─────────────────────────────────

  group('TelemetryService opt-out ordering (Aufgabe F)', () {
    test(
      'opt-out event is dispatched when trackSettingChange is called while consent is still active',
      () async {
        // Simulates the correct ordering in PrivacySection: trackSettingChange
        // is called BEFORE updateSettings revokes consent (v=false path).
        final bodies = <String>[];
        final client = MockClient((req) async {
          bodies.add(req.body);
          return http.Response('', 200);
        });
        final service = _makeService(client: client, consentGranted: true);
        service.trackSettingChange('share_usage_stats');
        await service.flush();

        expect(bodies, hasLength(1));
        final params = Uri.splitQueryString(bodies.single);
        expect(params['e_n'], 'share_usage_stats');
      },
    );

    test(
      'opt-out event is silently dropped when consent is already revoked (wrong order)',
      () async {
        // Simulates the WRONG ordering: trackSettingChange called after
        // updateSettings already set shareUsageStats=false. The PrivacySection
        // fix ensures this wrong-order path never occurs in production.
        var dispatched = false;
        final client = MockClient((_) async {
          dispatched = true;
          return http.Response('', 200);
        });
        final service = _makeService(client: client, consentGranted: false);
        service.trackSettingChange('share_usage_stats');
        await Future.delayed(Duration.zero);

        expect(
          dispatched,
          false,
          reason: 'Event must be sent BEFORE consent is revoked, not after',
        );
      },
    );
  });

  // ── Session aggregation — hot-path volume control ─────────────────────────

  group('TelemetrySessionAggregator', () {
    test('count() tallies repeated tuples; drainTo emits one event with the '
        'session count as value', () async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      final agg = TelemetrySessionAggregator();
      // 3 successful recordings + 2 clipboard insertions in one session.
      agg.count(category: 'pipeline', action: 'success', name: 'ok');
      agg.count(category: 'pipeline', action: 'success', name: 'ok');
      agg.count(category: 'pipeline', action: 'success', name: 'ok');
      agg.count(category: 'insertion', action: 'clipboard');
      agg.count(category: 'insertion', action: 'clipboard');

      agg.drainTo(service);
      await service.flush();

      // One HTTP hit per distinct tuple — not one per occurrence.
      expect(bodies, hasLength(2));
      final byTuple = {
        for (final b in bodies)
          () {
            final p = Uri.splitQueryString(b);
            return '${p['e_c']}/${p['e_a']}/${p['e_n'] ?? ''}';
          }(): Uri.splitQueryString(
            b,
          )['e_v'],
      };
      expect(byTuple['pipeline/success/ok'], '3');
      expect(byTuple['insertion/clipboard/'], '2');
    });

    test('drainTo clears counters — a second drain is a no-op', () async {
      var hits = 0;
      final client = MockClient((_) async {
        hits++;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      final agg = TelemetrySessionAggregator();
      agg.count(category: 'ui', action: 'fab_click');
      agg.drainTo(service);
      await service.flush();
      expect(hits, 1);

      // Nothing accumulated since → second drain emits nothing.
      agg.drainTo(service);
      await service.flush();
      expect(hits, 1);
      expect(agg.debugCounts, isEmpty);
    });

    test('drainTo respects the service consent gate — no HTTP without '
        'consent', () async {
      var hits = 0;
      final client = MockClient((_) async {
        hits++;
        return http.Response('', 200);
      });
      final service = _makeService(client: client, consentGranted: false);

      final agg = TelemetrySessionAggregator();
      agg.count(category: 'pipeline', action: 'success', name: 'ok');
      agg.drainTo(service);
      await Future<void>.delayed(Duration.zero);

      expect(hits, 0);
    });

    test('empty aggregator drainTo sends nothing', () async {
      var hits = 0;
      final client = MockClient((_) async {
        hits++;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      TelemetrySessionAggregator().drainTo(service);
      await service.flush();
      expect(hits, 0);
    });

    test('drainAndFlush combines drain + flush in one call', () async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      final agg = TelemetrySessionAggregator();
      agg.count(category: 'pipeline', action: 'success', name: 'ok');
      agg.count(category: 'insertion', action: 'clipboard');

      // Single call drains the counters AND awaits the pending requests.
      await agg.drainAndFlush(service);

      expect(bodies, hasLength(2));
      expect(agg.debugCounts, isEmpty);
    });

    test('drainAndFlush on an empty aggregator sends nothing', () async {
      var hits = 0;
      final client = MockClient((_) async {
        hits++;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      await TelemetrySessionAggregator().drainAndFlush(service);

      expect(hits, 0);
    });
  });
}
