/// Tests for [HistoryRevealedNotifier]'s PIN lock: unlock, persisted
/// throttle, auto-lock after inactivity, set/remove PIN, the forgot-PIN wipe,
/// and [historyContentHiddenProvider] for the secondary surfaces.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/features/history/data/history_pin.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

// A cheap hash so the suite stays fast; verify reads the work factor from
// the stored value, so production verification is exercised unchanged.
final _pin4711 = hashHistoryPin('4711', iterations: 10);

AppSettings _settings({
  String pin = '',
  bool hideOnOpen = true,
  int autoLockMinutes = 0,
  int failedAttempts = 0,
  int lockedUntilMs = 0,
}) => AppSettings(
  history: HistorySettings(
    historyHideOnOpen: hideOnOpen,
    historyPin: pin,
    historyAutoLockMinutes: autoLockMinutes,
    historyPinFailedAttempts: failedAttempts,
    historyPinLockedUntil: lockedUntilMs,
  ),
);

class _Harness {
  _Harness(AppSettings settings, {DateTime? now})
    : notifier = _FakeSettingsNotifier(settings) {
    clock = now ?? DateTime(2026, 9, 30, 12);
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => notifier),
        historyLockClockProvider.overrideWithValue(() => clock),
        historyWiperProvider.overrideWithValue(() async => wipes++),
      ],
    );
  }

  final _FakeSettingsNotifier notifier;
  late final ProviderContainer container;
  late DateTime clock;
  int wipes = 0;

  Future<void> ready() => container.read(settingsProvider.future);
  HistoryRevealedNotifier get lock =>
      container.read(historyRevealedProvider.notifier);
  bool get revealed => container.read(historyRevealedProvider);
  HistorySettings get history => notifier.state.value!.history;
}

void main() {
  group('unlockWithPin', () {
    test('the right PIN reveals and clears earlier misses', () async {
      final h = _Harness(_settings(pin: _pin4711, failedAttempts: 3));
      await h.ready();

      final result = await h.lock.unlockWithPin('4711');

      expect(result.outcome, HistoryPinOutcome.ok);
      expect(h.revealed, isTrue);
      expect(h.history.historyPinFailedAttempts, 0);
    });

    test('a wrong PIN stays locked and counts the miss', () async {
      final h = _Harness(_settings(pin: _pin4711));
      await h.ready();

      final result = await h.lock.unlockWithPin('0000');

      expect(result.outcome, HistoryPinOutcome.wrong);
      expect(h.revealed, isFalse);
      expect(h.history.historyPinFailedAttempts, 1);
    });

    test('the 5th miss starts a persisted 30 s lockout', () async {
      final h = _Harness(_settings(pin: _pin4711, failedAttempts: 4));
      await h.ready();

      final result = await h.lock.unlockWithPin('0000');

      expect(result.outcome, HistoryPinOutcome.lockedOut);
      expect(result.retryAfter, const Duration(seconds: 30));
      expect(
        h.history.historyPinLockedUntil,
        h.clock.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
      );
    });

    test('during a lockout even the right PIN is refused', () async {
      final now = DateTime(2026, 9, 30, 12);
      final h = _Harness(
        _settings(
          pin: _pin4711,
          failedAttempts: 5,
          lockedUntilMs: now
              .add(const Duration(seconds: 10))
              .millisecondsSinceEpoch,
        ),
        now: now,
      );
      await h.ready();

      final result = await h.lock.unlockWithPin('4711');

      expect(result.outcome, HistoryPinOutcome.lockedOut);
      expect(result.retryAfter, const Duration(seconds: 10));
      expect(h.revealed, isFalse);
      expect(h.history.historyPinFailedAttempts, 5, reason: 'not counted');
    });

    test('after the lockout expires the right PIN works again', () async {
      final now = DateTime(2026, 9, 30, 12);
      final h = _Harness(
        _settings(
          pin: _pin4711,
          failedAttempts: 5,
          lockedUntilMs: now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
        now: now,
      );
      await h.ready();

      expect(
        (await h.lock.unlockWithPin('4711')).outcome,
        HistoryPinOutcome.ok,
      );
      expect(h.history.historyPinLockedUntil, 0);
    });
  });

  group('set / remove PIN', () {
    test(
      'setPin stores only a verifiable hash and turns the gate on',
      () async {
        final h = _Harness(_settings(hideOnOpen: false));
        await h.ready();

        await h.lock.setPin('1234');

        expect(h.history.historyPin, isNot(contains('1234')));
        expect(verifyHistoryPin('1234', h.history.historyPin), isTrue);
        expect(h.history.historyHideOnOpen, isTrue);
      },
    );

    test('removePin clears the hash and the throttle state', () async {
      final h = _Harness(_settings(pin: _pin4711, failedAttempts: 2));
      await h.ready();

      await h.lock.removePin();

      expect(h.history.historyPin, isEmpty);
      expect(h.history.historyPinFailedAttempts, 0);
      expect(h.history.historyPinLockedUntil, 0);
    });
  });

  test('resetForgottenPin wipes the history, drops the PIN, reveals', () async {
    final h = _Harness(_settings(pin: _pin4711, failedAttempts: 7));
    await h.ready();

    await h.lock.resetForgottenPin();

    expect(h.wipes, 1);
    expect(h.history.historyPin, isEmpty);
    expect(h.history.historyPinFailedAttempts, 0);
    expect(h.history.historyHideOnOpen, isTrue, reason: 'gate stays on');
    expect(h.revealed, isTrue);
  });

  group('auto-lock', () {
    test('conceals after the configured inactivity', () {
      fakeAsync((async) {
        final h = _Harness(_settings(autoLockMinutes: 5));
        h.ready();
        async.flushMicrotasks();

        h.lock.reveal();
        async.elapse(const Duration(minutes: 4));
        expect(h.revealed, isTrue);

        h.lock.registerActivity();
        async.elapse(const Duration(minutes: 4));
        expect(h.revealed, isTrue, reason: 'activity restarted the timer');

        async.elapse(const Duration(minutes: 1, seconds: 1));
        expect(h.revealed, isFalse);
      });
    });

    test('"Never" keeps the history revealed', () {
      fakeAsync((async) {
        final h = _Harness(_settings());
        h.ready();
        async.flushMicrotasks();

        h.lock.reveal();
        async.elapse(const Duration(hours: 5));
        expect(h.revealed, isTrue);
      });
    });
  });

  group('historyContentHiddenProvider', () {
    test('hidden only while a PIN is set and the history is locked', () async {
      final h = _Harness(_settings(pin: _pin4711));
      await h.ready();
      expect(h.container.read(historyContentHiddenProvider), isTrue);

      await h.lock.unlockWithPin('4711');
      expect(h.container.read(historyContentHiddenProvider), isFalse);

      h.lock.conceal();
      expect(h.container.read(historyContentHiddenProvider), isTrue);
    });

    test('the PIN-less gate does not hide secondary surfaces', () async {
      final h = _Harness(_settings());
      await h.ready();
      expect(h.container.read(historyContentHiddenProvider), isFalse);
    });
  });
}
