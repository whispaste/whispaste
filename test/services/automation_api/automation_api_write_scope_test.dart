/// Scope separation of the automation API (#255, ADR 0015 D17): the
/// standard token never writes, the write token opens only the write routes,
/// and a write token that is switched off (null) authenticates nothing.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_pipeline.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';
import 'package:whispaste/services/automation_api/automation_api_status_routes.dart';
import 'package:whispaste/services/automation_api/automation_write_jobs.dart';
import 'package:whispaste/services/automation_api/automation_write_routes.dart';

const _standard = 'standard-token-0123456789abcdef';
const _write = 'write-token-fedcba9876543210';

AutomationWriteRecord _record() => AutomationWriteRecord(
  id: 'w1',
  startedAt: DateTime.utc(2026, 11, 19, 10),
  status: AutomationWriteStatus.running,
  instructionChars: 12,
);

Handler _handler({String? writeToken = _write, List<String>? started}) =>
    buildAutomationApiHandler(
      currentToken: () async => _standard,
      currentWriteToken: () async => writeToken,
      routeGroups: [
        dictationTriggerRoutes(
          triggerDictation:
              ({
                wait = false,
                language,
                smartModePreset,
                silenceTimeout,
              }) async => const DictationTriggerResult(recording: true),
        ),
        automationStatusRoutes(readStatus: () => {'dictation': 'idle'}),
        automationWriteRoutes(
          start: (request) {
            started?.add(request.instruction);
            return AutomationWriteStarted(_record(), Future.value(_record()));
          },
          lookup: (id) => id == 'w1' ? _record() : null,
        ),
      ],
    );

Request _req(String method, String path, String token, {Object? body}) =>
    Request(
      method,
      Uri.parse('http://127.0.0.1:8765$path'),
      body: body,
      headers: {'authorization': 'Bearer $token', 'host': '127.0.0.1:8765'},
    );

void main() {
  test('the standard token cannot start a write job', () async {
    final started = <String>[];
    final response = await _handler(started: started)(
      _req(
        'POST',
        '/v1/write',
        _standard,
        body: jsonEncode({'instruction': 'hi'}),
      ),
    );
    expect(response.statusCode, 403);
    expect(started, isEmpty);
  });

  test(
    'the write token reaches neither the trigger nor other routes',
    () async {
      final handler = _handler();
      final trigger = await handler(
        _req('POST', '/v1/dictation/trigger', _write),
      );
      final status = await handler(_req('GET', '/v1/status', _write));
      expect(trigger.statusCode, 403);
      expect(status.statusCode, 403);
    },
  );

  test('the write token starts a job; the answer holds no text', () async {
    final started = <String>[];
    final response = await _handler(started: started)(
      _req(
        'POST',
        '/v1/write',
        _write,
        body: jsonEncode({'instruction': '  Absage an Herrn X  '}),
      ),
    );
    expect(response.statusCode, 202);
    expect(started, ['Absage an Herrn X']);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['id'], 'w1');
    expect(body['status'], 'running');
    expect(body.keys, isNot(contains('text')));
    expect(body.keys, isNot(contains('instruction')));
  });

  test('writing switched off: the write token is no token at all', () async {
    final response = await _handler(writeToken: null)(
      _req('POST', '/v1/write', _write, body: jsonEncode({'instruction': 'x'})),
    );
    expect(response.statusCode, 401);
  });

  test('the status route reports a job of the protocol', () async {
    final handler = _handler();
    final known = await handler(_req('GET', '/v1/write/status?id=w1', _write));
    final unknown = await handler(
      _req('GET', '/v1/write/status?id=nope', _write),
    );
    expect(known.statusCode, 200);
    expect(unknown.statusCode, 404);
  });

  group('request body', () {
    for (final body in <Object?>[
      {},
      {'instruction': ''},
      {'instruction': '   '},
      {'instruction': 42},
      {'instruction': 'x' * (kAutomationWriteMaxInstructionChars + 1)},
      {'instruction': 'x', 'wait': 'yes'},
      {
        'instruction': 'x',
        'context': {'screen': false},
      },
      {
        'instruction': 'x',
        'context': {'clipboard': 'off'},
      },
      ['instruction'],
    ]) {
      test('rejects $body', () async {
        final response = await _handler()(
          _req('POST', '/v1/write', _write, body: jsonEncode(body)),
        );
        expect(response.statusCode, 400);
      });
    }

    test('context switches can only narrow', () {
      final parsed = parseAutomationWriteRequest({
        'instruction': 'x',
        'context': {'clipboard': false},
      })!;
      expect(parsed.limits.clipboard, isFalse);
      expect(parsed.limits.profile, isTrue);
      expect(parsed.limits.app, isTrue);
    });
  });

  test('busy and rate limit map to 409 and 429', () async {
    Handler withStart(AutomationWriteStart result) => buildAutomationApiHandler(
      currentToken: () async => _standard,
      currentWriteToken: () async => _write,
      routeGroups: [
        automationWriteRoutes(start: (_) => result, lookup: (_) => null),
      ],
    );
    final body = jsonEncode({'instruction': 'x'});
    final busy = await withStart(const AutomationWriteBusy('w0'))(
      _req('POST', '/v1/write', _write, body: body),
    );
    final limited = await withStart(
      const AutomationWriteRateLimited(Duration(milliseconds: 1500)),
    )(_req('POST', '/v1/write', _write, body: body));
    expect(busy.statusCode, 409);
    expect(limited.statusCode, 429);
    expect(limited.headers['retry-after'], '2');
  });
}
