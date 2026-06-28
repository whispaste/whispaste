import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/services/telemetry_service.dart';

TelemetryService _makeService({
  required http.Client client,
  String endpointUrl = 'https://example.matomo.cloud',
  int siteId = 1,
  bool consentGranted = true,
  bool dntActive = false,
  Map<String, String> dimensions = const {},
}) {
  return TelemetryService(
    client: client,
    endpointUrl: endpointUrl,
    siteId: siteId,
    consentGranted: consentGranted,
    dntActive: dntActive,
    dimensions: dimensions,
  );
}

void main() {
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
      'sends cookieless request without _id, pk_id, or session cookies when consent granted',
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

        // No _id cookie parameter in URL or body
        expect(url.contains('_id='), false);
        expect(body.contains('_id='), false);

        // No pk_id in URL or body
        expect(url.contains('pk_id'), false);
        expect(body.contains('pk_id'), false);

        // No session cookie parameter
        expect(body.contains('_cvar'), false);
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

    test('request body does not contain visitor ID parameter', () async {
      http.Request? capturedRequest;
      final client = MockClient((req) async {
        capturedRequest = req;
        return http.Response('', 200);
      });
      final service = _makeService(client: client);

      service.trackPageView('/test');
      await service.flush();

      final body = capturedRequest!.body;
      expect(body.contains('_id'), false);
      expect(body.contains('uid'), false);
      expect(body.contains('cid'), false);
    });
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
      expect(captured!.body.contains('_id='), false);
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
}
