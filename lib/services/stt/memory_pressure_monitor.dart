/// Polls system memory and unloads or reloads the on-device speech engine
/// accordingly (see `memory_pressure.dart` for the policy).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import '../low_power_state.dart';
import '../stt_engine_lifecycle_provider.dart';
import 'memory_pressure.dart';

final _log = AppLogger('MemoryPressureMonitor');

/// How often memory is read. Pressure builds over seconds to minutes, so a
/// slow poll keeps the cost negligible.
const Duration kMemoryPollInterval = Duration(seconds: 30);

final memoryPressureMonitorProvider = Provider<MemoryPressureMonitor>((ref) {
  final monitor = MemoryPressureMonitor(
    ref,
    store: ref.read(memorySnapshotStoreProvider),
  );
  monitor.start();
  ref.onDispose(monitor.stop);
  return monitor;
});

class MemoryPressureMonitor {
  MemoryPressureMonitor(
    this._ref, {
    required this.store,
    Future<MemorySnapshot?> Function()? read,
  }) : _read = read ?? readMemorySnapshot;

  final Ref _ref;
  final MemorySnapshotStore store;
  final Future<MemorySnapshot?> Function() _read;

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;
  bool _loggedUnknown = false;
  bool _unloadedByPressure = false;

  void start() {
    _stopped = false;
    _timer ??= Timer.periodic(kMemoryPollInterval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final snapshot = await _read();
      // The provider may have been disposed while the read was running.
      if (_stopped) return;
      if (snapshot != null) store.latest = snapshot;
      final pressure = classifyMemoryPressure(snapshot);
      if (pressure == MemoryPressure.unknown && !_loggedUnknown) {
        _loggedUnknown = true;
        _log.info(
          'No memory reading on this platform: the pressure unload is inactive.',
        );
      }
      await _apply(pressure);
    } finally {
      _busy = false;
    }
  }

  Future<void> _apply(MemoryPressure pressure) async {
    final settings = _ref.read(settingsProvider).value ?? AppSettings.defaults;
    if (!settings.sttProviderType.isLocal) return;
    final lifecycle = _ref.read(onDeviceEngineLifecycleProvider);
    final action = memoryPressureAction(
      pressure: pressure,
      isIdle: _ref.read(recordingProvider).phase == RecordingPhase.idle,
      engineLoaded: lifecycle.status.isReady,
      unloadedByPressure: _unloadedByPressure,
    );
    switch (action) {
      case MemoryAction.none:
        return;
      case MemoryAction.unload:
        _log.info('Low memory: unloading the speech model until it clears');
        _unloadedByPressure = true;
        await lifecycle.stop();
      case MemoryAction.reload:
        // Stays unloaded and retries on the next tick once low-power mode ends.
        if (lowPowerBlocksAutoWarm(await readLowPowerState())) {
          _log.debug('Memory recovered, low-power mode on: reload deferred');
          return;
        }
        _log.info('Memory recovered: reloading the speech model');
        _unloadedByPressure = false;
        try {
          await lifecycle.prewarm();
        } on Exception catch (e) {
          _log.warning('Reload after memory pressure failed: $e');
        }
    }
  }
}
