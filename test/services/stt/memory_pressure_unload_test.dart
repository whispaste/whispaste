/// A hung speech-model unload or memory read under memory pressure must not
/// keep the monitor busy forever, and the hotkey heal must not wait for the
/// unload. Without the time limits, [tick] never completes and no heal runs.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/low_power_state.dart';
import 'package:whispaste/services/stt/memory_pressure.dart';
import 'package:whispaste/services/stt/memory_pressure_monitor.dart';
import 'package:whispaste/services/stt_engine_lifecycle_provider.dart';
import 'package:whispaste/services/stt/on_device_engine_lifecycle.dart';

/// Lifecycle whose stop never answers, like a native unload that is stuck.
class _HangingLifecycle implements OnDeviceEngineLifecycle {
  @override
  Future<void> stop() => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Loaded engine that counts reloads; stop answers at once.
class _CountingLifecycle implements OnDeviceEngineLifecycle {
  bool ready = true;
  int prewarms = 0;

  @override
  EngineLifecycleStatus get status => EngineLifecycleStatus(isReady: ready);

  @override
  Future<void> stop() async => ready = false;

  @override
  Future<void> prewarm() async {
    prewarms++;
    ready = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DefaultSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _IdleRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();
}

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  test('a hung unload runs the heal at once and gives up after the limit', () {
    fakeAsync((async) {
      var healed = 0;
      var done = false;
      unloadSpeechModelUnderPressure(
        _HangingLifecycle(),
        onUnloaded: () => healed++,
      ).then((_) => done = true);

      async.flushMicrotasks();
      expect(healed, 1, reason: 'the heal does not wait for the unload');
      expect(done, isFalse, reason: 'still waiting inside the limit');

      async.elapse(kEngineLifecycleTimeout + const Duration(seconds: 1));
      expect(done, isTrue, reason: 'the monitor is released after the limit');
    });
  });

  test('a memory read that never answers releases the monitor', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ref = container.read(_refProvider);

    fakeAsync((async) {
      var reads = 0;
      final monitor = MemoryPressureMonitor(
        ref,
        store: MemorySnapshotStore(),
        read: () {
          reads++;
          return Completer<MemorySnapshot?>().future;
        },
      );
      var done = false;
      monitor.tick().then((_) => done = true);

      async.elapse(kMemoryReadTimeout + const Duration(seconds: 1));
      expect(done, isTrue, reason: 'tick completes after the read limit');

      unawaited(monitor.tick());
      async.flushMicrotasks();
      expect(reads, 2, reason: 'the next tick runs again, not blocked');
    });
  });

  test('a low-power reading that never answers does not hold the reload', () {
    final lifecycle = _CountingLifecycle();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_DefaultSettings.new),
        recordingProvider.overrideWith(_IdleRecording.new),
        onDeviceEngineLifecycleProvider.overrideWithValue(lifecycle),
      ],
    );
    addTearDown(container.dispose);
    final ref = container.read(_refProvider);

    fakeAsync((async) {
      // Nullable on purpose: the reader's type decides onTimeout's return type.
      MemorySnapshot? snapshot = const MemorySnapshot(
        totalMB: 16000,
        availableMB: 100,
      );
      final monitor = MemoryPressureMonitor(
        ref,
        store: MemorySnapshotStore(),
        read: () async => snapshot,
        readLowPower: () => Completer<LowPowerState>().future,
      );

      unawaited(monitor.tick());
      async.flushMicrotasks();
      expect(lifecycle.ready, isFalse, reason: 'unloaded under pressure');

      snapshot = const MemorySnapshot(totalMB: 16000, availableMB: 8000);
      var done = false;
      monitor.tick().then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isFalse, reason: 'still waiting inside the limit');

      async.elapse(kLowPowerReadTimeout + const Duration(seconds: 1));
      expect(done, isTrue, reason: 'the reload is not held by the reading');
      expect(lifecycle.prewarms, 1, reason: 'unknown does not defer it');
    });
  });
}
