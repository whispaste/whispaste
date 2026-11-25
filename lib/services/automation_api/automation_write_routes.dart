/// Route group: write jobs (#255, ADR 0015 D17/D22). Only the write token
/// reaches these routes (see `automation_api_scope_middleware.dart`).
///
/// `POST /v1/write` takes an instruction as text and answers with the job id
/// and status, never with the written text. The result is pasted straight
/// into the foreground app once the safeguards in `automation_write_jobs.dart`
/// pass. `GET /v1/write/status?id=…` reports a job of the protocol.
library;

import 'package:shelf/shelf.dart';

import 'automation_api_responses.dart';
import 'automation_api_router.dart';
import 'automation_write_jobs.dart';

/// A parsed `POST /v1/write` body, or null when it is invalid.
class AutomationWriteRequest {
  const AutomationWriteRequest({
    required this.instruction,
    this.wait = false,
    this.limits = const AutomationWriteContextLimits(),
  });

  final String instruction;
  final bool wait;
  final AutomationWriteContextLimits limits;
}

const _contextKeys = {'profile', 'app', 'clipboard'};

/// Validates a decoded body. `instruction` is required, `wait` and the
/// `context` switches are optional booleans; an unknown context source is
/// rejected rather than ignored, so a typo cannot widen nothing silently.
AutomationWriteRequest? parseAutomationWriteRequest(Map<String, dynamic> body) {
  final instruction = body['instruction'];
  if (instruction is! String) return null;
  final trimmed = instruction.trim();
  if (trimmed.isEmpty || trimmed.length > kAutomationWriteMaxInstructionChars) {
    return null;
  }
  var wait = false;
  if (body.containsKey('wait')) {
    final candidate = body['wait'];
    if (candidate is! bool) return null;
    wait = candidate;
  }
  var limits = const AutomationWriteContextLimits();
  if (body.containsKey('context')) {
    final context = body['context'];
    if (context is! Map<String, dynamic>) return null;
    for (final entry in context.entries) {
      if (!_contextKeys.contains(entry.key) || entry.value is! bool) {
        return null;
      }
    }
    limits = AutomationWriteContextLimits(
      profile: context['profile'] as bool? ?? true,
      app: context['app'] as bool? ?? true,
      clipboard: context['clipboard'] as bool? ?? true,
    );
  }
  return AutomationWriteRequest(
    instruction: trimmed,
    wait: wait,
    limits: limits,
  );
}

AutomationApiRouteGroup automationWriteRoutes({
  required AutomationWriteStart Function(AutomationWriteRequest request) start,
  required AutomationWriteRecord? Function(String id) lookup,
}) {
  return (router) {
    router.add('POST', '/v1/write', (Request request) async {
      final body = await readJsonObject(request.read());
      final parsed = body == null ? null : parseAutomationWriteRequest(body);
      if (parsed == null) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }
      switch (start(parsed)) {
        case AutomationWriteBusy(:final openId):
          return jsonResponse(409, {'error': 'write_busy', 'id': openId});
        case AutomationWriteRateLimited(:final retryAfter):
          final seconds = (retryAfter.inMilliseconds / 1000).ceil();
          return Response(
            429,
            body: '{"error":"rate_limited","retry_after":$seconds}',
            headers: {
              'content-type': 'application/json',
              'retry-after': '$seconds',
            },
          );
        case AutomationWriteStarted(:final record, :final done):
          if (!parsed.wait) return jsonResponse(202, record.toJson());
          return jsonResponse(200, (await done).toJson());
      }
    });
    router.add('GET', '/v1/write/status', (Request request) async {
      final id = request.url.queryParameters['id'];
      if (id == null || id.isEmpty) {
        return jsonResponse(400, {'error': 'invalid_request'});
      }
      final record = lookup(id);
      if (record == null) return jsonResponse(404, {'error': 'not_found'});
      return jsonResponse(200, record.toJson());
    });
  };
}
