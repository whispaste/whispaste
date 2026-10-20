/// Tests for the `whispaste` CLI (WP-38 / 8.2).
///
/// Each test runs the real command runner against a loopback fake of the API,
/// so the assertions cover what goes over the wire, not only what gets printed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_client.dart';
import 'package:whispaste/services/automation_api/automation_cli.dart';

import '../../test_helpers/fake_automation_api.dart';

const _token = 'test-token-0123456789abcdef';

class _Run {
  _Run(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

Future<_Run> _run(
  List<String> args, {
  required int port,
  Map<String, String>? env,
  Future<List<int>> Function(String path)? readFile,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runAutomationCli(
    args,
    environment:
        env ?? {'WHISPASTE_API_TOKEN': _token, 'WHISPASTE_API_PORT': '$port'},
    out: out,
    err: err,
    readFile: readFile,
  );
  return _Run(code, out.toString(), err.toString());
}

void main() {
  FakeAutomationApi? api;

  tearDown(() async {
    await api?.close();
    api = null;
  });

  group('argument handling', () {
    test('no command prints usage and exits 2', () async {
      final result = await _run(const [], port: 1);
      expect(result.code, 2);
      expect(result.out, contains('Usage: whispaste'));
    });

    test('--help exits 0 with usage', () async {
      final result = await _run(const ['--help'], port: 1);
      expect(result.code, 0);
      expect(result.out, contains('Commands:'));
    });

    test('an unknown command exits 2 without contacting the API', () async {
      api = await FakeAutomationApi.start((_) async => jsonReply(200, {}));
      final result = await _run(const ['dance'], port: api!.port);
      expect(result.code, 2);
      expect(result.err, contains('unknown command'));
      expect(api!.requests, isEmpty);
    });

    test('--limit outside 1-200 is a usage error', () async {
      final result = await _run(const [
        'note',
        'list',
        '--limit',
        '500',
      ], port: 1);
      expect(result.code, 2);
      expect(result.err, contains('--limit must be 1-200'));
    });

    test('--field without = is a usage error', () async {
      final result = await _run(const [
        'snippet',
        'render',
        'Greeting',
        '--field',
        'name',
      ], port: 1);
      expect(result.code, 2);
      expect(result.err, contains('key=value'));
    });

    test('a missing token exits 2 and sends nothing', () async {
      api = await FakeAutomationApi.start((_) async => jsonReply(200, {}));
      final result = await _run(
        const ['status'],
        port: api!.port,
        env: {'WHISPASTE_API_PORT': '${api!.port}'},
      );
      expect(result.code, 2);
      expect(result.err, contains('WHISPASTE_API_TOKEN'));
      expect(api!.requests, isEmpty);
    });
  });

  group('commands over loopback', () {
    test('status sends the bearer token and prints the JSON answer', () async {
      api = await FakeAutomationApi.start(
        (_) async => jsonReply(200, {'api_version': 1, 'dictation': 'idle'}),
      );
      final result = await _run(const ['status'], port: api!.port);

      expect(result.code, 0);
      expect(result.out, contains('"api_version": 1'));
      expect(api!.requests.single.method, 'GET');
      expect(api!.requests.single.path, '/v1/status');
      expect(api!.requests.single.authorization, 'Bearer $_token');
    });

    test('note create joins the words into one note body', () async {
      api = await FakeAutomationApi.start(
        (_) async => jsonReply(201, {'id': 'n1', 'content': 'Milk and eggs'}),
      );
      final result = await _run(const [
        'note',
        'create',
        'Milk',
        'and',
        'eggs',
      ], port: api!.port);

      expect(result.code, 0);
      expect(api!.requests.single.method, 'POST');
      expect(api!.requests.single.path, '/v1/notes');
      expect(api!.requests.single.jsonBody, {'content': 'Milk and eggs'});
    });

    test('note list passes --limit as the query parameter', () async {
      api = await FakeAutomationApi.start(
        (_) async => jsonReply(200, {'notes': <Object>[]}),
      );
      final result = await _run(const [
        'note',
        'list',
        '--limit',
        '5',
      ], port: api!.port);

      expect(result.code, 0);
      expect(api!.requests.single.query, {'limit': '5'});
    });

    test('snippet render sends the fields and prints only the text', () async {
      api = await FakeAutomationApi.start(
        (_) async => jsonReply(200, {'name': 'Greeting', 'text': 'Hi Ada'}),
      );
      final result = await _run(const [
        'snippet',
        'render',
        'Greeting',
        '--field',
        'name=Ada',
      ], port: api!.port);

      expect(result.code, 0);
      expect(result.out, 'Hi Ada\n');
      expect(api!.requests.single.jsonBody, {
        'name': 'Greeting',
        'values': {'name': 'Ada'},
      });
    });

    test(
      'transcribe posts the WAV bytes as audio/wav and prints the transcript',
      () async {
        api = await FakeAutomationApi.start(
          (_) async => jsonReply(200, {'transcript': 'hello there'}),
        );
        final wav = [82, 73, 70, 70, 1, 2, 3];
        final result = await _run(
          const ['transcribe', '/fixtures/clip.wav'],
          port: api!.port,
          readFile: (path) async {
            expect(path, '/fixtures/clip.wav');
            return wav;
          },
        );

        expect(result.code, 0);
        expect(result.out, 'hello there\n');
        expect(api!.requests.single.path, '/v1/transcriptions');
        expect(api!.requests.single.contentType, startsWith('audio/wav'));
        expect(api!.requests.single.body, wav);
      },
    );

    test('an API error prints its code and exits 1', () async {
      api = await FakeAutomationApi.start(
        (_) async => jsonReply(404, {'error': 'snippet_not_found'}),
      );
      final result = await _run(const [
        'snippet',
        'render',
        'Missing',
      ], port: api!.port);

      expect(result.code, 1);
      expect(result.err, contains('snippet_not_found'));
      expect(result.err, contains('HTTP 404'));
    });

    test(
      'a busy app gets a clear message and exit 1, not the raw code',
      () async {
        api = await FakeAutomationApi.start(
          (_) async => jsonReply(409, {'error': 'busy'}),
        );
        final result = await _run(
          const ['transcribe', '/fixtures/clip.wav'],
          port: api!.port,
          readFile: (_) async => [82, 73, 70, 70],
        );

        expect(result.code, 1);
        expect(result.err, contains('busy with a dictation'));
        expect(result.err, isNot(contains('HTTP 409')));
      },
    );

    test('a rejected token gets a message that points to Settings', () async {
      api = await FakeAutomationApi.start(
        (_) async => jsonReply(401, {'error': 'unauthorized'}),
      );
      final result = await _run(const ['status'], port: api!.port);

      expect(result.code, 1);
      expect(result.err, contains('token was rejected'));
    });

    test(
      'an app that is not running gets a clear message, not a stack trace',
      () async {
        final port = await closedLoopbackPort();
        final result = await _run(const ['status'], port: port);

        expect(result.code, 1);
        expect(result.err, contains('no WhisPaste API answered'));
        expect(result.err, isNot(contains('SocketException')));
      },
    );
  });

  group('AutomationApiClient', () {
    test('a non-JSON answer is reported as invalid_response', () async {
      api = await FakeAutomationApi.start(
        (_) async => Response.ok('<html>proxy</html>'),
      );
      final client = AutomationApiClient(token: _token, port: api!.port);

      await expectLater(
        client.status(),
        throwsA(
          isA<AutomationApiException>().having(
            (e) => e.error,
            'error',
            'invalid_response',
          ),
        ),
      );
    });
  });
}
