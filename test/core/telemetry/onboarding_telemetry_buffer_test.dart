/// Unit tests for [OnboardingTelemetryBuffer] — onboarding events are held in
/// memory until the user's privacy choice (ticket 01, decision 5a).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/telemetry/onboarding_telemetry_buffer.dart';

void main() {
  late List<BufferedTelemetryEvent> sent;
  late DateTime clock;

  OnboardingTelemetryBuffer buffer({int capacity = 200}) {
    return OnboardingTelemetryBuffer(
      send: sent.add,
      capacity: capacity,
      clock: () => clock,
    );
  }

  void stepEvent(OnboardingTelemetryBuffer b, String name) {
    b.track(category: 'onboarding', action: 'step', name: name);
  }

  setUp(() {
    sent = [];
    clock = DateTime.utc(2026, 10, 22, 12);
  });

  test('outside a first run events are sent straight through', () {
    final b = buffer();
    stepEvent(b, 'welcome');
    expect(sent, hasLength(1));
  });

  group('first run, privacy choice pending', () {
    test('5 step events before the choice send nothing', () {
      final b = buffer()..begin();
      for (var i = 0; i < 5; i++) {
        stepEvent(b, 'step$i');
      }
      expect(sent, isEmpty);
      expect(b.pendingCount, 5);
      expect(b.isPending, isTrue);
    });

    test('choice "on" sends every buffered event once, with original time', () {
      final b = buffer()..begin();
      stepEvent(b, 'welcome');
      clock = clock.add(const Duration(seconds: 7));
      stepEvent(b, 'speech');
      b.decide(shareUsageStats: true);
      expect(sent.map((e) => e.name), ['welcome', 'speech']);
      expect(sent.map((e) => e.at), [
        DateTime.utc(2026, 10, 22, 12),
        DateTime.utc(2026, 10, 22, 12, 0, 7),
      ]);
      // Later events after "on" go straight out, exactly once each.
      stepEvent(b, 'hotkey');
      expect(sent, hasLength(3));
      b.decide(shareUsageStats: true); // a second decision is a no-op
      expect(sent, hasLength(3));
    });

    test('choice "off" discards the buffer and nothing is sent afterwards', () {
      final b = buffer()..begin();
      for (var i = 0; i < 5; i++) {
        stepEvent(b, 'step$i');
      }
      b.decide(shareUsageStats: false);
      expect(sent, isEmpty);
      expect(b.pendingCount, 0);
      stepEvent(b, 'later');
      b.decide(shareUsageStats: true);
      expect(sent, isEmpty);
      stepEvent(b, 'much later');
      expect(sent, isEmpty);
    });

    test('the 201st event evicts the oldest; the buffer is capped at 200', () {
      final b = buffer()..begin();
      for (var i = 0; i < 201; i++) {
        stepEvent(b, 'e$i');
      }
      expect(b.pendingCount, 200);
      b.decide(shareUsageStats: true);
      expect(sent, hasLength(200));
      expect(sent.first.name, 'e1');
      expect(sent.last.name, 'e200');
    });

    test(
      'a pending crash-report hold is active only while the choice is open',
      () {
        final b = buffer()..begin();
        expect(b.holdsCrashReports, isTrue);
        b.decide(shareUsageStats: false);
        expect(b.holdsCrashReports, isFalse);
      },
    );

    test('a fresh buffer (app restart) starts empty and sends nothing', () {
      final first = buffer()..begin();
      stepEvent(first, 'welcome');
      // Process ends before the choice: a new instance knows nothing of it.
      final restarted = buffer();
      expect(restarted.pendingCount, 0);
      expect(restarted.isPending, isFalse);
      expect(sent, isEmpty);
    });
  });
}
