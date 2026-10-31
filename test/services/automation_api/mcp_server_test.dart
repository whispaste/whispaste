/// Protocol tests for the stdio MCP server (ticket / 8.4).
///
/// Covers initialize, tools/list, tools/call, malformed input, and an unknown
/// method. Tool calls go through a loopback fake of the API, so the tests also
/// check that every call carries the bearer token and the right route.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/automation_api_client.dart';
import 'package:whispaste/services/automation_api/mcp_server.dart';

import '../../test_helpers/fake_automation_api.dart';

const _token = 'mcp-token-0123456789abcdef';

Map<String, Object?> _decode(String? line) =>
    jsonDecode(line!) as Map<String, Object?>;

void main() {
  late FakeAutomationApi api;
  late McpServer server;

  setUp(() async {
    api = await FakeAutomationApi.start((request) async {
      return switch ('${request.method} ${request.path}') {
        'GET /v1/notes' => jsonReply(200, {
          'notes': [
            {'id': 'n1', 'content': 'first'},
          ],
        }),
        'POST /v1/notes' => jsonReply(201, {
          'id': 'n2',
          'content': request.jsonBody['content'],
        }),
        'GET /v1/snippets' => jsonReply(200, {'snippets': <Object>[]}),
        'POST /v1/snippets/render' => jsonReply(404, {
          'error': 'snippet_not_found',
        }),
        'GET /v1/history/latest' => jsonReply(200, {'transcript': 'hi'}),
        'POST /v1/dictation/trigger' => jsonReply(200, {'status': 'started'}),
        _ => jsonReply(500, {'error': 'unexpected_route'}),
      };
    });
    server = McpServer(
      client: AutomationApiClient(token: _token, port: api.port),
      serverVersion: '9.9.9',
    );
  });

  tearDown(() async {
    await api.close();
  });

  group('protocol', () {
    test(
      'initialize answers with the protocol version and tool capability',
      () async {
        final response = _decode(
          await server.handleLine(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'initialize',
              'params': {
                'protocolVersion': kMcpProtocolVersion,
                'capabilities': <String, Object?>{},
                'clientInfo': {'name': 'test', 'version': '0'},
              },
            }),
          ),
        );

        expect(response['jsonrpc'], '2.0');
        expect(response['id'], 1);
        final result = response['result'] as Map<String, Object?>;
        expect(result['protocolVersion'], kMcpProtocolVersion);
        expect(result['capabilities'], {'tools': <String, Object?>{}});
        expect(result['serverInfo'], {'name': 'whispaste', 'version': '9.9.9'});
      },
    );

    test('notifications/initialized gets no answer', () async {
      expect(
        await server.handleLine(
          jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        ),
        isNull,
      );
    });

    test('ping answers with an empty result', () async {
      final response = _decode(
        await server.handleLine(
          jsonEncode({'jsonrpc': '2.0', 'id': 'p', 'method': 'ping'}),
        ),
      );
      expect(response, {'jsonrpc': '2.0', 'id': 'p', 'result': {}});
    });

    test('an unknown method with an id answers -32601', () async {
      final response = _decode(
        await server.handleLine(
          jsonEncode({'jsonrpc': '2.0', 'id': 7, 'method': 'resources/list'}),
        ),
      );
      expect(response['id'], 7);
      expect(response['error'], {
        'code': -32601,
        'message': 'Method not found',
      });
    });

    test('an unknown notification is ignored, not answered', () async {
      expect(
        await server.handleLine(
          jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/whatever'}),
        ),
        isNull,
      );
    });
  });

  group('tools/list', () {
    test('exposes exactly the six tools, each with an input schema', () async {
      final response = _decode(
        await server.handleLine(
          jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}),
        ),
      );
      final tools = (response['result'] as Map)['tools'] as List;
      final names = [for (final t in tools) (t as Map)['name']];

      expect(names, [
        'notes_list',
        'notes_create',
        'snippets_list',
        'snippets_render',
        'last_dictation',
        'trigger_dictation',
      ]);
      for (final tool in tools) {
        expect((tool as Map)['inputSchema'], isA<Map<String, Object?>>());
      }
    });
  });

  group('tools/call', () {
    test(
      'notes_create forwards the content and returns the note as text',
      () async {
        final response = _decode(
          await server.handleLine(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 3,
              'method': 'tools/call',
              'params': {
                'name': 'notes_create',
                'arguments': {'content': 'buy milk'},
              },
            }),
          ),
        );

        final result = response['result'] as Map<String, Object?>;
        expect(result['isError'], false);
        final text =
            ((result['content'] as List).single as Map)['text'] as String;
        expect(jsonDecode(text), {'id': 'n2', 'content': 'buy milk'});

        final sent = api.requests.single;
        expect(sent.method, 'POST');
        expect(sent.path, '/v1/notes');
        expect(sent.authorization, 'Bearer $_token');
        expect(sent.jsonBody, {'content': 'buy milk'});
      },
    );

    test('notes_list passes the limit through', () async {
      await server.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {
            'name': 'notes_list',
            'arguments': {'limit': 10},
          },
        }),
      );
      expect(api.requests.single.query, {'limit': '10'});
    });

    test('trigger_dictation defaults to wait=false', () async {
      await server.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'tools/call',
          'params': {'name': 'trigger_dictation'},
        }),
      );
      expect(api.requests.single.path, '/v1/dictation/trigger');
      expect(api.requests.single.jsonBody, {'wait': false});
    });

    test(
      'trigger_dictation passes the language on to the API (SW-09)',
      () async {
        await server.handleLine(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 50,
            'method': 'tools/call',
            'params': {
              'name': 'trigger_dictation',
              'arguments': {'language': 'de'},
            },
          }),
        );
        expect(api.requests.single.jsonBody, {'wait': false, 'language': 'de'});
      },
    );

    test(
      'an API error becomes a tool result with isError, not a protocol error',
      () async {
        final response = _decode(
          await server.handleLine(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 6,
              'method': 'tools/call',
              'params': {
                'name': 'snippets_render',
                'arguments': {'name': 'Missing'},
              },
            }),
          ),
        );

        expect(response.containsKey('error'), isFalse);
        final result = response['result'] as Map<String, Object?>;
        expect(result['isError'], true);
        final text =
            ((result['content'] as List).single as Map)['text'] as String;
        expect(text, contains('snippet_not_found'));
      },
    );

    test('an unknown tool name is an invalid-params error', () async {
      final response = _decode(
        await server.handleLine(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 8,
            'method': 'tools/call',
            'params': {'name': 'shell_exec'},
          }),
        ),
      );
      expect((response['error'] as Map)['code'], -32602);
      expect(api.requests, isEmpty);
    });

    test(
      'missing required arguments are rejected before any request',
      () async {
        final response = _decode(
          await server.handleLine(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 9,
              'method': 'tools/call',
              'params': {
                'name': 'notes_create',
                'arguments': <String, Object?>{},
              },
            }),
          ),
        );
        expect((response['error'] as Map)['code'], -32602);
        expect(api.requests, isEmpty);
      },
    );

    test('a limit outside 1-200 is rejected before any request', () async {
      final response = _decode(
        await server.handleLine(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 10,
            'method': 'tools/call',
            'params': {
              'name': 'notes_list',
              'arguments': {'limit': 9999},
            },
          }),
        ),
      );
      expect((response['error'] as Map)['code'], -32602);
      expect(api.requests, isEmpty);
    });

    test('tools/call without params is an invalid-params error', () async {
      final response = _decode(
        await server.handleLine(
          jsonEncode({'jsonrpc': '2.0', 'id': 11, 'method': 'tools/call'}),
        ),
      );
      expect((response['error'] as Map)['code'], -32602);
    });
  });

  group('malformed input', () {
    test('invalid JSON answers -32700 with a null id', () async {
      final response = _decode(await server.handleLine('{not json'));
      expect(response['id'], isNull);
      expect((response['error'] as Map)['code'], -32700);
    });

    test('a JSON array is an invalid request', () async {
      final response = _decode(await server.handleLine('[1,2,3]'));
      expect((response['error'] as Map)['code'], -32600);
    });

    test('a message without jsonrpc 2.0 is an invalid request', () async {
      final response = _decode(
        await server.handleLine(jsonEncode({'id': 1, 'method': 'ping'})),
      );
      expect(response['id'], 1);
      expect((response['error'] as Map)['code'], -32600);
    });

    test(
      'a message whose method is not a string is an invalid request',
      () async {
        final response = _decode(
          await server.handleLine(
            jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 42}),
          ),
        );
        expect((response['error'] as Map)['code'], -32600);
      },
    );
  });

  test(
    'serve writes one JSON line per answered message and nothing else',
    () async {
      final lines = Stream.fromIterable([
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}),
        '',
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        '{broken',
        jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}),
      ]);
      final written = <String>[];

      await server.serve(lines, written.add);

      expect(written, hasLength(3));
      for (final line in written) {
        expect(_decode(line)['jsonrpc'], '2.0');
      }
      expect(_decode(written[0])['id'], 1);
      expect(_decode(written[1])['id'], isNull);
      expect(_decode(written[2])['id'], 2);
    },
  );
}
