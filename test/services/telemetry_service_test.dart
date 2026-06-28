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
}) {
  return TelemetryService(
    client: client,
    endpointUrl: endpointUrl,
    siteId: siteId,
    consentGranted: consentGranted,
    dntActive: dntActive,
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
}
