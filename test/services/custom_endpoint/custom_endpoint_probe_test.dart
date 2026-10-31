import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/services/custom_endpoint/custom_endpoint_probe.dart';

/// Runs the probe against a fake server; no network is touched.
Future<CustomEndpointProbe> _probe(
  Future<http.Response> Function(http.Request request) handler, {
  String model = 'llama',
  String? apiKey,
  Duration timeout = const Duration(seconds: 2),
}) => probeCustomEndpoint(
  base: Uri.parse('http://localhost:1234/v1'),
  model: model,
  apiKey: apiKey,
  client: MockClient(handler),
  timeout: timeout,
);

http.Response _models(List<String> ids) => http.Response(
  jsonEncode({
    'object': 'list',
    'data': [
      for (final id in ids) {'id': id, 'object': 'model'},
    ],
  }),
  200,
);

void main() {
  test('a listed model is connected and verified', () async {
    final probe = await _probe((_) async => _models(['llama', 'qwen']));
    expect(probe.result, CustomEndpointProbeResult.connected);
    expect(probe.modelVerified, isTrue);
    expect(probe.availableModels, ['llama', 'qwen']);
  });

  test('a missing model names the models that are available', () async {
    final probe = await _probe((_) async => _models(['qwen']), model: 'llama');
    expect(probe.result, CustomEndpointProbeResult.modelMissing);
    expect(probe.availableModels, ['qwen']);
  });

  test('an empty model list is connected but not verified', () async {
    final probe = await _probe((_) async => _models([]));
    expect(probe.result, CustomEndpointProbeResult.connected);
    expect(probe.modelVerified, isFalse);
  });

  test('the listed models are capped', () async {
    final probe = await _probe(
      (_) async => _models([for (var i = 0; i < 20; i++) 'm$i']),
      model: 'other',
    );
    expect(probe.availableModels, hasLength(kCustomEndpointProbeListedModels));
  });

  test('a body without a model list is a bad format', () async {
    expect(
      (await _probe((_) async => http.Response('<html>', 200))).result,
      CustomEndpointProbeResult.badFormat,
    );
    expect(
      (await _probe((_) async => http.Response('{"data": 3}', 200))).result,
      CustomEndpointProbeResult.badFormat,
    );
  });

  test('401 and 403 are unauthorized, 404 is a bad format', () async {
    expect(
      (await _probe((_) async => http.Response('', 401))).result,
      CustomEndpointProbeResult.unauthorized,
    );
    expect(
      (await _probe((_) async => http.Response('', 403))).result,
      CustomEndpointProbeResult.unauthorized,
    );
    expect(
      (await _probe((_) async => http.Response('Not Found', 404))).result,
      CustomEndpointProbeResult.badFormat,
    );
  });

  test('5xx is a server error', () async {
    expect(
      (await _probe((_) async => http.Response('boom', 503))).result,
      CustomEndpointProbeResult.serverError,
    );
  });

  test('a refused connection is unreachable', () async {
    final probe = await _probe(
      (_) async => throw http.ClientException('Connection refused'),
    );
    expect(probe.result, CustomEndpointProbeResult.unreachable);
  });

  test('no answer within the timeout is unreachable', () async {
    final never = Completer<http.Response>();
    final probe = await _probe(
      (_) => never.future,
      timeout: const Duration(milliseconds: 20),
    );
    never.complete(http.Response('', 200));
    expect(probe.result, CustomEndpointProbeResult.unreachable);
  });

  test('asks the models endpoint and sends the key as bearer token', () async {
    http.Request? seen;
    await _probe((request) async {
      seen = request;
      return _models(['llama']);
    }, apiKey: 'sk-test');
    expect(seen!.url.toString(), 'http://localhost:1234/v1/models');
    expect(seen!.method, 'GET');
    expect(seen!.headers['Authorization'], 'Bearer sk-test');
    expect(seen!.body, isEmpty);
  });

  test('sends no authorization header without a key', () async {
    http.Request? seen;
    await _probe((request) async {
      seen = request;
      return _models(['llama']);
    });
    expect(seen!.headers.containsKey('Authorization'), isFalse);
  });
}
