/// Settings model for automation hooks (WP-38 / 8.3): validation at save
/// time, tolerant decoding at load time, and the versioned event payload.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/automation_hooks.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  group('validateAutomationHook (save time)', () {
    test('a loopback URL with one known event is valid', () {
      expect(
        validateAutomationHook('http://127.0.0.1:9000/x', {'note.changed'}),
        AutomationHookValidation.ok,
      );
    });

    test('a non-loopback URL is refused with invalidUrl', () {
      expect(
        validateAutomationHook('http://example.com/x', {'note.changed'}),
        AutomationHookValidation.invalidUrl,
      );
    });

    test('no events and unknown events are refused', () {
      expect(
        validateAutomationHook('http://127.0.0.1/x', <String>{}),
        AutomationHookValidation.noEvents,
      );
      expect(
        validateAutomationHook('http://127.0.0.1/x', {'shell.run'}),
        AutomationHookValidation.unknownEvent,
      );
    });

    test('the number of hooks is capped', () {
      expect(kAutomationHookMaxCount, greaterThanOrEqualTo(1));
      expect(
        validateAutomationHook('http://127.0.0.1/x', {
          'note.changed',
        }, existingCount: kAutomationHookMaxCount),
        AutomationHookValidation.tooMany,
      );
    });
  });

  group('encode / decode', () {
    test('a list round-trips through the settings string', () {
      final hooks = [
        const AutomationHook(
          url: 'http://127.0.0.1:9000/a',
          events: {'transcript.finished'},
        ),
        const AutomationHook(
          url: 'http://localhost:9001/b',
          events: {'note.changed', 'transcript.finished'},
        ),
      ];
      final decoded = decodeAutomationHooks(encodeAutomationHooks(hooks));
      expect(decoded, hooks);
    });

    test('a missing, empty or corrupt value decodes to no hooks', () {
      expect(decodeAutomationHooks(null), isEmpty);
      expect(decodeAutomationHooks(''), isEmpty);
      expect(decodeAutomationHooks('{not json'), isEmpty);
      expect(decodeAutomationHooks('{"a":1}'), isEmpty);
    });

    test('entries that fail validation are dropped on load', () {
      const raw =
          '[{"url":"http://8.8.8.8/x","events":["note.changed"]},'
          '{"url":"http://127.0.0.1/ok","events":["note.changed"]},'
          '{"url":"http://127.0.0.1/none","events":[]},'
          '{"url":"http://127.0.0.1/unknown","events":["nope"]},'
          '"junk"]';
      final decoded = decodeAutomationHooks(raw);
      expect(decoded.map((h) => h.url), ['http://127.0.0.1/ok']);
    });
  });

  group('AutomationApiSettings hooks (additive key)', () {
    test('the hooks are stored under a new key and read back', () {
      const settings = AutomationApiSettings(
        hooks: [
          AutomationHook(
            url: 'http://127.0.0.1:9000/h',
            events: {'transcript.finished'},
          ),
        ],
      );
      final map = settings.toMap();
      expect(map.keys, contains('automation_hooks'));
      expect(map['automation_enabled'], isNull);
      expect(AutomationApiSettings.fromMap(map), settings);
    });

    test('an old settings map without the key loads with no hooks', () {
      final loaded = AutomationApiSettings.fromMap({
        'automation_api_enabled': 'true',
      });
      expect(loaded.hooks, isEmpty);
      expect(loaded.enabled, isTrue);
    });
  });

  group('versioned event payload', () {
    test('carries schema, version, event, time and data', () {
      final payload = buildAutomationEventPayload(
        event: 'note.changed',
        at: DateTime.utc(2026, 10, 17, 12),
        data: {'note_id': 'n1'},
      );
      expect(payload, {
        'schema': 'whispaste.automation-event',
        'version': 1,
        'event': 'note.changed',
        'occurred_at': '2026-10-17T12:00:00.000Z',
        'data': {'note_id': 'n1'},
      });
    });
  });
}
