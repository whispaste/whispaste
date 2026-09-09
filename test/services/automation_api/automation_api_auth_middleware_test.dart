/// Unit tests for the bearer-token auth middleware — no real HTTP socket.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_auth_middleware.dart';

Request _request({String? bearer}) => Request(
  'GET',
  Uri.parse('http://localhost/anything'),
  headers: bearer == null ? null : {'authorization': 'Bearer $bearer'},
);

void main() {
  group('bearerTokenAuth', () {
    late Handler protected;
    var innerCalled = false;

    Handler build(Future<String?> Function() currentToken) {
      innerCalled = false;
      return const Pipeline()
          .addMiddleware(bearerTokenAuth(currentToken: currentToken))
          .addHandler((Request request) {
            innerCalled = true;
            return Response.ok('secret');
          });
    }

    test('valid token → passes through to the inner handler', () async {
      protected = build(() async => 'good-token');
      final response = await protected(_request(bearer: 'good-token'));

      expect(innerCalled, isTrue);
      expect(response.statusCode, 200);
    });

    test('missing Authorization header → 401, never reaches handler', () async {
      protected = build(() async => 'good-token');
      final response = await protected(_request());

      expect(innerCalled, isFalse);
      expect(response.statusCode, 401);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'unauthorized');
    });

    test('wrong token → 401, never reaches handler', () async {
      protected = build(() async => 'good-token');
      final response = await protected(_request(bearer: 'wrong-token'));

      expect(innerCalled, isFalse);
      expect(response.statusCode, 401);
    });

    test('no token configured (null) → every request is rejected, even '
        'with a non-empty header', () async {
      protected = build(() async => null);
      final response = await protected(_request(bearer: 'anything'));

      expect(innerCalled, isFalse);
      expect(response.statusCode, 401);
    });

    test('empty-string configured token never matches, even an empty '
        'bearer value', () async {
      protected = build(() async => '');
      final response = await protected(
        Request(
          'GET',
          Uri.parse('http://localhost/anything'),
          headers: {'authorization': 'Bearer '},
        ),
      );

      expect(innerCalled, isFalse);
      expect(response.statusCode, 401);
    });

    test('re-reads currentToken on every call — a token rotated between '
        'two requests invalidates the old one immediately', () async {
      var current = 'first';
      protected = build(() async => current);

      final firstResponse = await protected(_request(bearer: 'first'));
      expect(firstResponse.statusCode, 200);

      current = 'second';
      final staleResponse = await protected(_request(bearer: 'first'));
      expect(staleResponse.statusCode, 401);

      final freshResponse = await protected(_request(bearer: 'second'));
      expect(freshResponse.statusCode, 200);
    });
  });
}
