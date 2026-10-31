/// Auth middleware order (WP-43a A-M2): the token store is read only for a
/// request that carries an Authorization header, and a failing store answers
/// with a status code instead of throwing into the server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_auth_middleware.dart';

Handler _inner() =>
    (Request request) async => Response.ok('ok');

void main() {
  test(
    'a request without a header is rejected without reading the token',
    () async {
      var reads = 0;
      final handler = bearerTokenAuth(
        currentToken: () async {
          reads++;
          return 'secret';
        },
      )(_inner());

      final response = await handler(
        Request('GET', Uri.parse('http://127.0.0.1:8765/v1/status')),
      );

      expect(response.statusCode, 401);
      expect(reads, 0);
    },
  );

  test(
    'a token store that throws answers 503, not an unhandled error',
    () async {
      final handler = bearerTokenAuth(
        currentToken: () async => throw StateError('keyring locked'),
      )(_inner());

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://127.0.0.1:8765/v1/status'),
          headers: {'authorization': 'Bearer abc'},
        ),
      );

      expect(response.statusCode, 503);
    },
  );

  test('a valid bearer token still reaches the handler', () async {
    final handler = bearerTokenAuth(currentToken: () async => 'abc')(_inner());

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://127.0.0.1:8765/v1/status'),
        headers: {'authorization': 'Bearer abc'},
      ),
    );

    expect(response.statusCode, 200);
  });
}
