/// Unit tests for [OnboardingTelemetryBuffer] — onboarding events are held in
/// until the user's privacy choice (ticket 01, decision 5a), with a local copy
/// across restarts (GR-033).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/telemetry/onboarding_telemetry_buffer.dart';
import 'package:whispaste/core/telemetry/onboarding_telemetry_prefs_store.dart';

/// In-memory stand-in for the device copy; survives "restarts" of a buffer.
final class _FakeStore implements OnboardingTelemetryStore {
  List<BufferedTelemetryEvent>? copy;

  @override
  Future<List<BufferedTelemetryEvent>> load() async => copy ?? const [];

  @override
  void save(List<BufferedTelemetryEvent> events) => copy = List.of(events);

  @override
  void clear() => copy = null;
}

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

  group('local copy across restarts (GR-033)', () {
    late _FakeStore store;

    OnboardingTelemetryBuffer stored({int capacity = 200}) =>
        OnboardingTelemetryBuffer(
          send: sent.add,
          capacity: capacity,
          store: store,
          clock: () => clock,
        );

    setUp(() => store = _FakeStore());

    test(
      'a restart before the choice keeps the early steps, in order',
      () async {
        final first = stored()..begin();
        stepEvent(first, 'welcome');
        clock = clock.add(const Duration(minutes: 1));
        stepEvent(first, 'about_you');
        expect(sent, isEmpty);
        expect(store.copy, hasLength(2));

        clock = clock.add(const Duration(minutes: 5));
        final restarted = stored()..begin();
        stepEvent(restarted, 'mic');
        await restarted.restored;
        expect(restarted.pendingCount, 3);
        expect(
          restarted.earliestHeld(action: 'step', name: 'welcome'),
          DateTime.utc(2026, 10, 22, 12),
        );
        expect(sent, isEmpty, reason: 'nothing leaves before the choice');

        restarted.decide(shareUsageStats: true);
        expect(sent.map((e) => e.name), ['welcome', 'about_you', 'mic']);
        expect(sent.first.at, DateTime.utc(2026, 10, 22, 12));
        expect(store.copy, isNull);
      },
    );

    test(
      'choice "off" after a restart sends nothing and removes the copy',
      () async {
        final first = stored()..begin();
        stepEvent(first, 'welcome');
        final restarted = stored()..begin();
        await restarted.restored;
        restarted.decide(shareUsageStats: false);
        stepEvent(restarted, 'later');
        expect(sent, isEmpty);
        expect(store.copy, isNull);
      },
    );

    test(
      'events held longer than Matomo accepts are dated 23 h back',
      () async {
        final first = stored()..begin();
        stepEvent(first, 'welcome');
        clock = clock.add(const Duration(days: 2));
        final restarted = stored()..begin();
        await restarted.restored;
        restarted.decide(shareUsageStats: true);
        expect(sent.single.at, clock.subtract(const Duration(hours: 23)));
      },
    );

    test('a copy older than a week is an abandoned run and dropped', () async {
      final first = stored()..begin();
      stepEvent(first, 'welcome');
      clock = clock.add(const Duration(days: 8));
      final restarted = stored()..begin();
      await restarted.restored;
      expect(restarted.pendingCount, 0);
      expect(store.copy, isNull);
      restarted.decide(shareUsageStats: true);
      expect(sent, isEmpty);
    });

    test(
      'a choice before the read finished still sends the copy once',
      () async {
        final first = stored()..begin();
        stepEvent(first, 'welcome');
        final restarted = stored()..begin();
        restarted.decide(shareUsageStats: true);
        await restarted.restored;
        expect(sent.map((e) => e.name), ['welcome']);
        expect(store.copy, isNull);
      },
    );

    test('the restored copy respects the capacity, oldest out first', () async {
      final first = stored(capacity: 2)..begin();
      stepEvent(first, 'a');
      clock = clock.add(const Duration(seconds: 1));
      stepEvent(first, 'b');
      clock = clock.add(const Duration(seconds: 1));
      final restarted = stored(capacity: 2)..begin();
      stepEvent(restarted, 'c');
      await restarted.restored;
      restarted.decide(shareUsageStats: true);
      expect(sent.map((e) => e.name), ['b', 'c']);
    });

    test(
      'the SharedPreferences store round-trips and skips broken data',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefsStore = SharedPrefsOnboardingTelemetryStore();
        final event = BufferedTelemetryEvent(
          category: 'onboarding',
          action: 'step',
          name: null,
          at: DateTime.utc(2026, 10, 22, 12),
        );
        prefsStore.save([event]);
        final loaded = await prefsStore.load();
        expect(loaded.single.action, 'step');
        expect(loaded.single.name, isNull);
        expect(loaded.single.at, event.at);
        prefsStore.clear();
        expect(await prefsStore.load(), isEmpty);
        expect(decodeHeldEvents('not json'), isEmpty);
        expect(
          decodeHeldEvents('[{"c":1},{"c":"x","a":"y","t":5}]'),
          hasLength(1),
        );
      },
    );
  });
}
