/// Polls system memory and unloads or reloads the on-device speech engine
/// accordingly (see `memory_pressure.dart` for the policy).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../hotkey_self_heal.dart';
import '../hotkey_service.dart';
import '../../core/recording/recording_state.dart';
import '../low_power_state.dart';
import '../stt_engine_lifecycle_provider.dart';
import 'memory_pressure.dart';
import 'on_device_engine_lifecycle.dart';

final _log = AppLogger('MemoryPressureMonitor');

/// Longest a memory read may take. A hung read must not hold the monitor's
/// busy flag forever: then no unload, no reload and no hotkey heal follows.
const Duration kMemoryReadTimeout = Duration(seconds: 5);

/// Longest an unload or reload of the speech model is waited for. Quit uses
/// the same bound for its engine stop (graceful_shutdown.dart).
const Duration kEngineLifecycleTimeout = Duration(seconds: 10);

/// Unloads the speech model under memory pressure. [onUnloaded] runs at once,
/// before the unload finishes, so the hotkey heal never waits for the engine.
/// A stop that hangs or fails is logged and given up after
/// [kEngineLifecycleTimeout]; the monitor's busy flag is released either way.
Future<void> unloadSpeechModelUnderPressure(
  OnDeviceEngineLifecycle lifecycle, {
  required void Function() onUnloaded,
}) async {
  onUnloaded();
  try {
    await lifecycle.stop().timeout(kEngineLifecycleTimeout);
  } on TimeoutException {
    _log.warning(
      'Speech model unload did not finish within '
      '${kEngineLifecycleTimeout.inSeconds} s; continuing',
    );
  } on Object catch (e) {
    _log.warning('Speech model unload failed (non-fatal): $e');
  }
}

/// How often memory is read. Pressure builds over seconds to minutes, so a
/// slow poll keeps the cost negligible.
const Duration kMemoryPollInterval = Duration(seconds: 30);

final memoryPressureMonitorProvider = Provider<MemoryPressureMonitor>((ref) {
  final monitor = MemoryPressureMonitor(
    ref,
    store: ref.read(memorySnapshotStoreProvider),
    onUnloadedByPressure: () => unawaited(
      ref
          .read(hotkeyServiceProvider.notifier)
          .requestHotkeyHeal(HotkeyHealTrigger.memoryPressure),
    ),
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
    this.onUnloadedByPressure,
  }) : _read = read ?? defaultMemorySnapshotReader;

  final Ref _ref;
  final MemorySnapshotStore store;
  final Future<MemorySnapshot?> Function() _read;

  /// Called after the speech model was unloaded under memory pressure. The
  /// hotkey is re-registered then, since the pressure may have cost it too.
  final void Function()? onUnloadedByPressure;

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
      final snapshot = await _read().timeout(
        kMemoryReadTimeout,
        onTimeout: () {
          _log.warning('Memory read did not answer; skipped this check');
          return null;
        },
      );
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
      // No reading means no action (memoryPressureAction maps unknown to none);
      // returning here also keeps the engine provider out of this path.
      if (pressure == MemoryPressure.unknown) return;
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
        await unloadSpeechModelUnderPressure(
          lifecycle,
          onUnloaded: () => onUnloadedByPressure?.call(),
        );
      case MemoryAction.reload:
        // Stays unloaded and retries on the next tick once low-power mode ends.
        if (lowPowerBlocksAutoWarm(await readLowPowerState())) {
          _log.debug('Memory recovered, low-power mode on: reload deferred');
          return;
        }
        _log.info('Memory recovered: reloading the speech model');
        _unloadedByPressure = false;
        try {
          await lifecycle.prewarm().timeout(kEngineLifecycleTimeout);
        } on Exception catch (e) {
          _log.warning('Reload after memory pressure failed: $e');
        }
    }
  }
}
