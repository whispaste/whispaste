import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/idle_unload_policy.dart';
import 'package:whispaste/services/stt/memory_pressure.dart';

void main() {
  group('parseLinuxMeminfo', () {
    test('reads MemTotal and MemAvailable in MB', () {
      final snapshot = parseLinuxMeminfo(
        'MemTotal:       16384000 kB\n'
        'MemFree:         1024000 kB\n'
        'MemAvailable:    8192000 kB\n',
      );
      expect(snapshot!.totalMB, 16000);
      expect(snapshot.availableMB, 8000);
    });

    test('returns null when MemAvailable is missing', () {
      expect(parseLinuxMeminfo('MemTotal: 16384000 kB\n'), isNull);
    });
  });

  group('snapshotFromMacFigures', () {
    test('derives the available MB from the free percentage', () {
      final snapshot = snapshotFromMacFigures(
        memsizeBytes: 17179869184, // 16 GiB
        freePercent: 42,
      );
      expect(snapshot!.totalMB, 16384);
      expect(snapshot.availableMB, 6881);
    });

    test('returns null when a figure is missing', () {
      expect(
        snapshotFromMacFigures(memsizeBytes: null, freePercent: 42),
        isNull,
      );
      expect(
        snapshotFromMacFigures(memsizeBytes: 17179869184, freePercent: null),
        isNull,
      );
    });
  });

  test('reads this machine on macOS, Windows and Linux', () async {
    final snapshot = await readMemorySnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.totalMB, greaterThan(0));
    expect(snapshot.availableMB, inInclusiveRange(0, snapshot.totalMB));
  });

  group('classifyMemoryPressure', () {
    test('no reading is unknown, not normal', () {
      expect(classifyMemoryPressure(null), MemoryPressure.unknown);
    });

    test('below 10 % available is low', () {
      const snapshot = MemorySnapshot(totalMB: 16000, availableMB: 1500);
      expect(classifyMemoryPressure(snapshot), MemoryPressure.low);
    });

    test('10 % available and above is normal', () {
      const snapshot = MemorySnapshot(totalMB: 16000, availableMB: 1600);
      expect(classifyMemoryPressure(snapshot), MemoryPressure.normal);
    });
  });

  group('memoryPressureAction', () {
    MemoryAction action({
      MemoryPressure pressure = MemoryPressure.normal,
      bool isIdle = true,
      bool engineLoaded = true,
      bool unloadedByPressure = false,
    }) => memoryPressureAction(
      pressure: pressure,
      isIdle: isIdle,
      engineLoaded: engineLoaded,
      unloadedByPressure: unloadedByPressure,
    );

    test('unloads an idle, loaded engine under pressure', () {
      expect(action(pressure: MemoryPressure.low), MemoryAction.unload);
    });

    test('never unloads during a dictation', () {
      expect(
        action(pressure: MemoryPressure.low, isIdle: false),
        MemoryAction.none,
      );
    });

    test('does not unload an engine that is not loaded', () {
      expect(
        action(pressure: MemoryPressure.low, engineLoaded: false),
        MemoryAction.none,
      );
    });

    test('reloads once the pressure is gone, but only what it unloaded', () {
      expect(
        action(engineLoaded: false, unloadedByPressure: true),
        MemoryAction.reload,
      );
      expect(action(engineLoaded: false), MemoryAction.none);
    });

    test('an unknown reading changes nothing', () {
      expect(
        action(
          pressure: MemoryPressure.unknown,
          engineLoaded: false,
          unloadedByPressure: true,
        ),
        MemoryAction.none,
      );
    });
  });

  group('resolveIdleUnloadMinutes', () {
    const roomy = MemorySnapshot(totalMB: 32768, availableMB: 16000);

    test('an explicit value is always kept', () {
      expect(
        resolveIdleUnloadMinutes(configured: 5, snapshot: roomy, modelMB: 1500),
        5,
      );
      expect(
        resolveIdleUnloadMinutes(configured: 0, snapshot: null, modelMB: null),
        0,
      );
    });

    test('automatic keeps the model loaded when RAM suffices', () {
      expect(
        resolveIdleUnloadMinutes(
          configured: kSttIdleAutomatic,
          snapshot: roomy,
          modelMB: 1500,
        ),
        0,
      );
    });

    test('automatic falls back to 5 min when total RAM is short', () {
      const small = MemorySnapshot(totalMB: 6000, availableMB: 5000);
      expect(
        resolveIdleUnloadMinutes(
          configured: kSttIdleAutomatic,
          snapshot: small,
          modelMB: 2600,
        ),
        kSttIdleFallbackMinutes,
      );
    });

    test('automatic falls back to 5 min when free RAM is short', () {
      const tight = MemorySnapshot(totalMB: 32768, availableMB: 2000);
      expect(
        resolveIdleUnloadMinutes(
          configured: kSttIdleAutomatic,
          snapshot: tight,
          modelMB: 2600,
        ),
        kSttIdleFallbackMinutes,
      );
    });

    test('automatic without a reading falls back to 5 min', () {
      expect(
        resolveIdleUnloadMinutes(
          configured: kSttIdleAutomatic,
          snapshot: null,
          modelMB: 1500,
        ),
        kSttIdleFallbackMinutes,
      );
    });
  });
}
