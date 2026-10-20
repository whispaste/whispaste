/// Request-size limit for the local automation API (WP-38 / 8.1).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_body_limit.dart';

Future<Response> _echo(Request request) async {
  final bytes = await request.read().expand((c) => c).toList();
  return Response.ok(jsonEncode({'length': bytes.length}));
}

Handler _wrapped({int limit = 16}) => const Pipeline()
    .addMiddleware(automationBodyLimit(maxBytesFor: (_) => limit))
    .addHandler(_echo);

/// Reports the type of the body the handler receives, plus its length.
Future<Response> _typeEcho(Request request) async {
  final body = await request.read().first;
  return Response.ok(
    jsonEncode({'type': body.runtimeType.toString(), 'length': body.length}),
  );
}

void main() {
  test('a body just under the limit arrives as a Uint8List', () async {
    final handler = const Pipeline()
        .addMiddleware(automationBodyLimit(maxBytesFor: (_) => 16))
        .addHandler(_typeEcho);
    final chunks = Stream<List<int>>.fromIterable([
      List<int>.filled(5, 0x61),
      List<int>.filled(5, 0x62),
      List<int>.filled(5, 0x63),
    ]);
    final response = await handler(
      Request('POST', Uri.parse('http://127.0.0.1/x'), body: chunks),
    );
    expect(response.statusCode, 200);
    final json = jsonDecode(await response.readAsString()) as Map;
    expect(json['type'], 'Uint8List');
    expect(json['length'], 15);
  });

  test('a body exactly at the limit is accepted', () async {
    final response = await _wrapped()(
      Request('POST', Uri.parse('http://127.0.0.1/x'), body: 'z' * 16),
    );
    expect(response.statusCode, 200);
  });

  test('the handler never runs once a chunk would pass the limit', () async {
    var handlerRan = false;
    final handler = const Pipeline()
        .addMiddleware(automationBodyLimit(maxBytesFor: (_) => 16))
        .addHandler((request) async {
          handlerRan = true;
          return _echo(request);
        });
    final chunks = Stream<List<int>>.fromIterable([
      List<int>.filled(10, 0x61),
      List<int>.filled(10, 0x62),
    ]);
    final response = await handler(
      Request('POST', Uri.parse('http://127.0.0.1/x'), body: chunks),
    );
    expect(response.statusCode, 413);
    expect(handlerRan, isFalse);
  });

  test('a body within the limit reaches the handler intact', () async {
    final response = await _wrapped()(
      Request('POST', Uri.parse('http://127.0.0.1/x'), body: 'hello'),
    );
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.readAsString()), {'length': 5});
  });

  test(
    'a declared Content-Length above the limit is rejected with 413',
    () async {
      final response = await _wrapped()(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1/x'),
          headers: {'content-length': '1000'},
          body: 'x' * 1000,
        ),
      );
      expect(response.statusCode, 413);
      expect(jsonDecode(await response.readAsString()), {
        'error': 'payload_too_large',
      });
    },
  );

  test(
    'a chunked body without Content-Length is cut off at the limit',
    () async {
      final chunks = Stream<List<int>>.fromIterable(
        List.generate(10, (_) => List<int>.filled(4, 0x61)),
      );
      final response = await _wrapped()(
        Request('POST', Uri.parse('http://127.0.0.1/x'), body: chunks),
      );
      expect(response.statusCode, 413);
    },
  );

  test('the limit is chosen per request', () async {
    final handler = const Pipeline()
        .addMiddleware(
          automationBodyLimit(
            maxBytesFor: (request) => request.url.path == 'big' ? 1024 : 16,
          ),
        )
        .addHandler(_echo);
    final body = 'y' * 100;
    final small = await handler(
      Request('POST', Uri.parse('http://127.0.0.1/small'), body: body),
    );
    final big = await handler(
      Request('POST', Uri.parse('http://127.0.0.1/big'), body: body),
    );
    expect(small.statusCode, 413);
    expect(big.statusCode, 200);
  });
}
