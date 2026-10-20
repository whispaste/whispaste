/// `POST /v1/dictation/trigger` while a transcription runs (WP-43a A-M4): the
/// route must answer 409 busy instead of reporting a recording that never
/// started.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:whispaste/services/automation_api/automation_api_router.dart';

void main() {
  test(
    'answers 409 busy when the dictation is busy and nothing started',
    () async {
      final handler = buildAutomationApiRouter([
        dictationTriggerRoutes(
          triggerDictation:
              ({
                bool wait = false,
                String? language,
                String? smartModePreset,
                double? silenceTimeout,
              }) async => throw const AutomationDictationBusyException(),
        ),
      ]).handler;

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1:8765/v1/dictation/trigger'),
          body: '{}',
        ),
      );

      expect(response.statusCode, 409);
      expect(await response.readAsString(), contains('"busy"'));
    },
  );
}
