import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/services/custom_endpoint/custom_endpoint_models.dart';

/// Loads the list from a fake server; no network is touched.
Future<CustomEndpointModelList> _load(
  Future<http.Response> Function(http.Request request) handler, {
  String base = 'http://localhost:1234/v1',
  String? apiKey,
  Duration timeout = const Duration(seconds: 2),
}) => loadCustomEndpointModels(
  base: Uri.parse(base),
  apiKey: apiKey,
  client: MockClient(handler),
  timeout: timeout,
);

http.Response _openAi(List<String> ids) => http.Response(
  jsonEncode({
    'object': 'list',
    'data': [
      for (final id in ids) {'id': id, 'object': 'model'},
    ],
  }),
  200,
);

http.Response _tags(List<String> names) => http.Response(
  jsonEncode({
    'models': [
      for (final name in names) {'name': name, 'model': name},
    ],
  }),
  200,
);

void main() {
  test('lists the OpenAI models sorted and without duplicates', () async {
    final requested = <Uri>[];
    final list = await _load((r) async {
      requested.add(r.url);
      return _openAi(['qwen', 'Llama', 'qwen', ' ']);
    });
    expect(list.result, CustomEndpointModelListResult.loaded);
    expect(list.models, ['Llama', 'qwen']);
    expect(list.needsV1, isFalse);
    expect(requested, [Uri.parse('http://localhost:1234/v1/models')]);
  });

  test('sends the key as bearer token only when there is one', () async {
    final headers = <Map<String, String>>[];
    Future<http.Response> handler(http.Request r) async {
      headers.add(r.headers);
      return _openAi(['a']);
    }

    await _load(handler, apiKey: 'sk-1');
    await _load(handler);
    expect(headers[0]['Authorization'], 'Bearer sk-1');
    expect(headers[1].containsKey('Authorization'), isFalse);
  });

  test('an empty list is reported as empty, not as an error', () async {
    final list = await _load((_) async => _openAi([]));
    expect(list.result, CustomEndpointModelListResult.empty);
    expect(list.models, isEmpty);
  });

  test('without /models it asks Ollama at the root without /v1', () async {
    final requested = <Uri>[];
    final list = await _load((r) async {
      requested.add(r.url);
      return r.url.path == '/api/tags'
          ? _tags(['llama3.2:latest'])
          : http.Response('not found', 404);
    }, base: 'http://localhost:11434/v1/');
    expect(requested.map((u) => u.toString()), [
      'http://localhost:11434/v1/models',
      'http://localhost:11434/api/tags',
    ]);
    expect(list.result, CustomEndpointModelListResult.loaded);
    expect(list.models, ['llama3.2:latest']);
    expect(list.needsV1, isFalse);
  });

  test('Ollama names found on an address without /v1 ask for /v1', () async {
    final list = await _load(
      (r) async => r.url.path == '/api/tags'
          ? _tags(['llama3.2:latest'])
          : http.Response('not found', 404),
      base: 'http://localhost:11434',
    );
    expect(list.result, CustomEndpointModelListResult.loaded);
    expect(list.needsV1, isTrue);
  });

  test('no list anywhere is reported as no list', () async {
    final list = await _load((_) async => http.Response('<html>', 200));
    expect(list.result, CustomEndpointModelListResult.noList);
  });

  test(
    'refused key, server error and no answer keep their own class',
    () async {
      expect(
        (await _load((_) async => http.Response('', 401))).result,
        CustomEndpointModelListResult.unauthorized,
      );
      expect(
        (await _load((_) async => http.Response('', 503))).result,
        CustomEndpointModelListResult.serverError,
      );
      expect(
        (await _load(
          (_) async => throw http.ClientException('Connection refused'),
        )).result,
        CustomEndpointModelListResult.unreachable,
      );
      expect(
        (await _load(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 10),
        )).result,
        CustomEndpointModelListResult.unreachable,
      );
    },
  );

  test('the Ollama root drops a trailing /v1 and keeps other paths', () {
    expect(
      customEndpointOllamaRoot(Uri.parse('http://h:11434/v1')).toString(),
      'http://h:11434',
    );
    expect(
      customEndpointOllamaRoot(Uri.parse('http://h/ollama/v1/')).toString(),
      'http://h/ollama',
    );
    expect(
      customEndpointOllamaRoot(Uri.parse('http://h/ollama')).toString(),
      'http://h/ollama',
    );
  });

  test('the list is capped', () {
    expect(
      customEndpointModelNames([
        for (var i = 0; i < kCustomEndpointModelListMax + 5; i++) 'm$i',
      ]),
      hasLength(kCustomEndpointModelListMax),
    );
  });
}
