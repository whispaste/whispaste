import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_client.dart';

import '../../test_helpers/fake_automation_api.dart';

void main() {
  test(
    'triggerDictation sends the language in the request body (SW-09)',
    () async {
      final api = await FakeAutomationApi.start(
        (request) async => Response.ok(
          '{"status":"triggered","recording":true}',
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(api.close);

      final client = AutomationApiClient(token: 'test-token', port: api.port);
      await client.triggerDictation(language: 'ar');

      expect(api.requests.single.jsonBody, {'wait': false, 'language': 'ar'});
    },
  );

  test('triggerDictation omits the language when none is given', () async {
    final api = await FakeAutomationApi.start(
      (request) async => Response.ok(
        '{"status":"triggered","recording":true}',
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(api.close);

    final client = AutomationApiClient(token: 'test-token', port: api.port);
    await client.triggerDictation();

    expect(api.requests.single.jsonBody, {'wait': false});
  });
}
