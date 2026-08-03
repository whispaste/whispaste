import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/automation_dispatch_service.dart';

Automation _automation({
  String id = 'a1',
  String trigger = 'open timer',
  String actionType = 'open_url',
  String payload = '{"url": "https://example.com/timer"}',
}) => Automation(
  id: id,
  trigger: trigger,
  actionType: actionType,
  payload: payload,
  createdAt: DateTime(2026),
);

void main() {
  group('normalizeForExactMatch', () {
    test('trims, collapses whitespace, drops trailing punctuation, '
        'lowercases', () {
      expect(normalizeForExactMatch('  Open   Timer!  '), 'open timer');
    });

    test('collapses internal newlines/tabs to a single space', () {
      expect(normalizeForExactMatch('open\ntimer'), 'open timer');
    });

    test('strips a run of multiple trailing punctuation marks', () {
      expect(normalizeForExactMatch('open timer?!'), 'open timer');
    });

    test('leaves leading punctuation untouched (only trailing is dropped)', () {
      expect(normalizeForExactMatch('...open timer'), '...open timer');
    });
  });

  group('AutomationDispatchService.findMatch', () {
    final service = AutomationDispatchService();

    test('matches when the whole transcript equals the trigger exactly '
        'after normalization', () {
      final automations = [_automation(trigger: 'open timer')];
      final match = service.findMatch(automations, '  Open Timer.  ');
      expect(match?.id, 'a1');
    });

    test('does not match when the trigger is only a substring of the '
        'transcript', () {
      final automations = [_automation(trigger: 'open timer')];
      final match = service.findMatch(automations, 'please open timer for me');
      expect(match, isNull);
    });

    test('returns null when nothing matches', () {
      final automations = [_automation(trigger: 'open timer')];
      expect(service.findMatch(automations, 'unrelated text'), isNull);
    });

    test('an empty automation list never matches', () {
      expect(service.findMatch(const [], 'open timer'), isNull);
    });

    test('a whitespace-only transcript never matches even against an '
        'empty-trigger automation', () {
      final automations = [_automation(trigger: '')];
      expect(service.findMatch(automations, '   '), isNull);
    });
  });

  group('AutomationDispatchService.dispatch — open_url', () {
    test('launches the URL decoded from the payload', () async {
      Uri? launched;
      final service = AutomationDispatchService(
        urlLauncher: (uri) async {
          launched = uri;
          return true;
        },
      );

      final result = await service.dispatch(
        _automation(payload: '{"url": "https://example.com/timer"}'),
      );

      expect(result, isTrue);
      expect(launched, Uri.parse('https://example.com/timer'));
    });

    test('returns false and does not throw when the launcher rejects the '
        'URL', () async {
      final service = AutomationDispatchService(
        urlLauncher: (uri) async => false,
      );

      final result = await service.dispatch(_automation());

      expect(result, isFalse);
    });

    test('returns false for a payload missing "url"', () async {
      final service = AutomationDispatchService(
        urlLauncher: (uri) async => true,
      );

      final result = await service.dispatch(
        _automation(payload: '{"not_url": "x"}'),
      );

      expect(result, isFalse);
    });

    test('returns false for malformed JSON payload', () async {
      final service = AutomationDispatchService(
        urlLauncher: (uri) async => true,
      );

      final result = await service.dispatch(_automation(payload: 'not json'));

      expect(result, isFalse);
    });

    test('returns false for an unknown action type', () async {
      final service = AutomationDispatchService(
        urlLauncher: (uri) async => true,
      );

      final result = await service.dispatch(
        _automation(actionType: 'shell_command'),
      );

      expect(result, isFalse);
    });
  });
}
