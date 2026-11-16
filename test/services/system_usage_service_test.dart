/// The card's reading loop on simulated time: it polls only while switched on
/// and active, stops when it is not, and never starts on its own.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/system_usage.dart';
import 'package:whispaste/services/stt/memory_pressure.dart';
import 'package:whispaste/services/system_usage_service.dart';

/// Returns the scripted samples in order and counts the calls.
class _ScriptedReader {
  _ScriptedReader(this._samples);

  final List<SystemUsageSample> _samples;
  int calls = 0;

  Future<SystemUsageSample> call() async {
    final sample = _samples[calls.clamp(0, _samples.length - 1)];
    calls++;
    return sample;
  }
}

SystemUsageSample _sample({
  CpuTicks? cpu,
  MemorySnapshot? ram = const MemorySnapshot(totalMB: 16000, availableMB: 8000),
  int? disk = 50 * 1024 * 1024 * 1024,
}) => SystemUsageSample(cpu: cpu, ram: ram, diskFreeBytes: disk);

ProviderContainer _container(_ScriptedReader reader) => ProviderContainer(
  overrides: [systemUsageReaderProvider.overrideWithValue(reader.call)],
);

void main() {
  test('nothing is read while the card is not active', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([_sample()]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(reader.calls, 0);
      container.dispose();
    });
  });

  test('the first reading comes at once, the load after the second tick', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([
        _sample(cpu: const CpuTicks(busy: 0, total: 100)),
        _sample(cpu: const CpuTicks(busy: 42, total: 200)),
      ]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      container.read(systemUsageProvider.notifier).setActive(active: true);
      async.flushMicrotasks();

      var state = container.read(systemUsageProvider);
      expect(state.loaded, isTrue);
      expect(state.cpuReadable, isTrue);
      expect(state.cpuPercent, isNull, reason: 'one sample is no load yet');
      expect(state.ramTotalMB, 16000);
      expect(state.ramAvailableMB, 8000);
      expect(state.ramLow, isFalse);
      expect(state.diskLow, isFalse);

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      state = container.read(systemUsageProvider);
      expect(state.cpuPercent, 42);
      container.dispose();
    });
  });

  test('stops at once when the card or the window goes inactive', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([_sample()]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      final notifier = container.read(systemUsageProvider.notifier);
      notifier.setActive(active: true);
      async.flushMicrotasks();
      final callsWhileActive = reader.calls;

      notifier.setActive(active: false);
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(reader.calls, callsWhileActive);
      container.dispose();
    });
  });

  test('a restart drops the earlier CPU reading', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([
        _sample(cpu: const CpuTicks(busy: 0, total: 100)),
        _sample(cpu: const CpuTicks(busy: 50, total: 200)),
        _sample(cpu: const CpuTicks(busy: 90, total: 300)),
      ]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      final notifier = container.read(systemUsageProvider.notifier);
      notifier.setActive(active: true);
      async.flushMicrotasks();
      notifier.setActive(active: false);
      notifier.setActive(active: true);
      async.flushMicrotasks();

      expect(
        container.read(systemUsageProvider).cpuPercent,
        isNull,
        reason: 'the pause must not be averaged into the load',
      );
      container.dispose();
    });
  });

  test('an unreadable CPU counter is reported as unreadable', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([_sample(cpu: null)]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      container.read(systemUsageProvider.notifier).setActive(active: true);
      async.flushMicrotasks();

      final state = container.read(systemUsageProvider);
      expect(state.cpuReadable, isFalse);
      expect(state.cpuPercent, isNull);
      container.dispose();
    });
  });

  test('missing memory and disk readings stay unknown, not zero', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([_sample(ram: null, disk: null)]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      container.read(systemUsageProvider.notifier).setActive(active: true);
      async.flushMicrotasks();

      final state = container.read(systemUsageProvider);
      expect(state.ramTotalMB, isNull);
      expect(state.diskFreeBytes, isNull);
      expect(state.ramLow, isFalse);
      expect(state.diskLow, isFalse);
      container.dispose();
    });
  });

  test('low memory and a nearly full disk set their warnings', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([
        _sample(
          ram: const MemorySnapshot(totalMB: 16000, availableMB: 800),
          disk: 1024 * 1024 * 1024,
        ),
      ]);
      final container = _container(reader);
      container.listen(systemUsageProvider, (_, _) {});
      container.read(systemUsageProvider.notifier).setActive(active: true);
      async.flushMicrotasks();

      final state = container.read(systemUsageProvider);
      expect(state.ramLow, isTrue);
      expect(state.diskLow, isTrue);
      container.dispose();
    });
  });

  test('disposing the last listener cancels the timer', () {
    fakeAsync((async) {
      final reader = _ScriptedReader([_sample()]);
      final container = _container(reader);
      final sub = container.listen(systemUsageProvider, (_, _) {});
      container.read(systemUsageProvider.notifier).setActive(active: true);
      async.flushMicrotasks();
      sub.close();
      container.dispose();
      final callsAtDispose = reader.calls;

      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(reader.calls, callsAtDispose);
    });
  });
}
