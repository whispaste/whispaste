import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/low_power_state.dart';

void main() {
  group('lowPowerBlocksAutoWarm', () {
    test('blocks automatic warm-up only while low-power mode is on', () {
      expect(lowPowerBlocksAutoWarm(LowPowerState.on), isTrue);
      expect(lowPowerBlocksAutoWarm(LowPowerState.off), isFalse);
    });

    test('an unknown state does not block (no silent failure either way)', () {
      expect(lowPowerBlocksAutoWarm(LowPowerState.unknown), isFalse);
    });
  });

  group('lowPowerFromPowerProfile (Linux, power-profiles-daemon)', () {
    test('power-saver is on', () {
      expect(
        lowPowerFromPowerProfile("(<'power-saver'>,)\n"),
        LowPowerState.on,
      );
    });

    test('balanced and performance are off', () {
      expect(lowPowerFromPowerProfile("(<'balanced'>,)\n"), LowPowerState.off);
      expect(
        lowPowerFromPowerProfile("(<'performance'>,)\n"),
        LowPowerState.off,
      );
    });

    test('anything else is unknown', () {
      expect(lowPowerFromPowerProfile(''), LowPowerState.unknown);
      expect(
        lowPowerFromPowerProfile("(<'something-new'>,)\n"),
        LowPowerState.unknown,
      );
    });
  });

  group(
    'lowPowerFromWindowsSaverFlag (SYSTEM_POWER_STATUS.SystemStatusFlag)',
    () {
      test('1 means energy saver is on, 0 means off', () {
        expect(lowPowerFromWindowsSaverFlag(1), LowPowerState.on);
        expect(lowPowerFromWindowsSaverFlag(0), LowPowerState.off);
      });

      test('any other value is unknown', () {
        expect(lowPowerFromWindowsSaverFlag(255), LowPowerState.unknown);
      });
    },
  );

  test('reads a definite state on macOS (real machine)', () async {
    final state = await readLowPowerState();
    expect(state, isNot(LowPowerState.unknown));
  }, skip: Platform.isMacOS ? false : 'macOS only');

  group('boundedLowPowerState', () {
    test('a reading that never answers is unknown after the limit', () {
      fakeAsync((async) {
        LowPowerState? result;
        boundedLowPowerState(
          () => Completer<LowPowerState>().future,
        ).then((value) => result = value);

        async.elapse(kLowPowerReadTimeout - const Duration(milliseconds: 1));
        expect(result, isNull, reason: 'still inside the limit');
        async.elapse(const Duration(milliseconds: 2));
        expect(result, LowPowerState.unknown);
      });
    });

    test('a failing reading is unknown', () {
      fakeAsync((async) {
        LowPowerState? result;
        boundedLowPowerState(
          () => throw const FileSystemException('gdbus missing'),
        ).then((value) => result = value);
        async.flushMicrotasks();
        expect(result, LowPowerState.unknown);
      });
    });

    test('a timely reading passes through', () {
      fakeAsync((async) {
        LowPowerState? result;
        boundedLowPowerState(
          () async => LowPowerState.on,
        ).then((value) => result = value);
        async.flushMicrotasks();
        expect(result, LowPowerState.on);
      });
    });
  });
}
