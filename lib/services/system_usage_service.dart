/// Reads the "Systemkarte" figures (whole-machine CPU load, memory, free disk
/// space) and keeps them fresh while the card is on screen.
///
/// Polling is driven by the card: nothing runs until [SystemUsageNotifier.
/// setActive] is called with `true`, and it stops again when the card leaves
/// the page or the window is no longer active. No subprocess is started
/// (`ps`, `top`, `wmic`), and no call sits on the hotkey or recording path.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/overview/system_usage.dart';
import '../core/platform/native_libs.dart';
import 'free_disk_space.dart';
import 'path_service.dart' show appDataDir;
import 'stt/memory_pressure.dart';

final _log = AppLogger('SystemUsage');

/// One reading of everything the card shows. A `null` part could not be read
/// on this platform or build (for example a sandbox that refuses the call),
/// so the card shows it as unavailable instead of a guessed number.
class SystemUsageSample {
  const SystemUsageSample({this.cpu, this.ram, this.diskFreeBytes});

  final CpuTicks? cpu;
  final MemorySnapshot? ram;
  final int? diskFreeBytes;
}

/// Reads one [SystemUsageSample]. A provider so tests and the UX screenshots
/// can feed fixed values.
typedef SystemUsageReader = Future<SystemUsageSample> Function();

final systemUsageReaderProvider = Provider<SystemUsageReader>(
  (ref) => readSystemUsage,
);

/// The real reading: CPU counters, memory and free space of the data volume.
Future<SystemUsageSample> readSystemUsage() async {
  final cpu = await _readCpuTicks();
  final ram = await readMemorySnapshot();
  final disk = await freeDiskBytes(appDataDir());
  return SystemUsageSample(cpu: cpu, ram: ram, diskFreeBytes: disk);
}

Future<CpuTicks?> _readCpuTicks() async {
  try {
    if (Platform.isLinux) {
      return cpuTicksFromProcStat(await File('/proc/stat').readAsString());
    }
    if (Platform.isWindows) return _windowsCpuTicks();
    if (Platform.isMacOS) return _macCpuTicks();
  } on Object catch (e) {
    _log.debug('CPU reading failed: $e');
  }
  return null;
}

typedef _GetSystemTimesC =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint64>,
      ffi.Pointer<ffi.Uint64>,
      ffi.Pointer<ffi.Uint64>,
    );
typedef _GetSystemTimesDart =
    int Function(
      ffi.Pointer<ffi.Uint64>,
      ffi.Pointer<ffi.Uint64>,
      ffi.Pointer<ffi.Uint64>,
    );

final _GetSystemTimesDart? _getSystemTimes = resolveNative(
  () => kernel32?.lookupFunction<_GetSystemTimesC, _GetSystemTimesDart>(
    'GetSystemTimes',
  ),
);

/// `GetSystemTimes` (kernel32), in-process like the other Windows probes.
CpuTicks? _windowsCpuTicks() {
  final getSystemTimes = _getSystemTimes;
  if (getSystemTimes == null) return null;
  return using((arena) {
    final idle = arena<ffi.Uint64>();
    final kernel = arena<ffi.Uint64>();
    final user = arena<ffi.Uint64>();
    if (getSystemTimes(idle, kernel, user) == 0) return null;
    return cpuTicksFromWindows(
      idle: idle.value,
      kernel: kernel.value,
      user: user.value,
    );
  });
}

typedef _MachHostSelfC = ffi.Uint32 Function();
typedef _MachHostSelfDart = int Function();
typedef _HostProcessorInfoC =
    ffi.Int32 Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Pointer<ffi.Int32>>,
      ffi.Pointer<ffi.Uint32>,
    );
typedef _HostProcessorInfoDart =
    int Function(
      int,
      int,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Pointer<ffi.Int32>>,
      ffi.Pointer<ffi.Uint32>,
    );
typedef _VmDeallocateC =
    ffi.Int32 Function(ffi.Uint32, ffi.UintPtr, ffi.UintPtr);
typedef _VmDeallocateDart = int Function(int, int, int);

/// `PROCESSOR_CPU_LOAD_INFO` flavour of `host_processor_info`: per core four
/// counters (user, system, idle, nice), summed over all cores here.
const _processorCpuLoadInfo = 2;
const _cpuStateMax = 4;

final _HostProcessorInfoDart? _hostProcessorInfo = resolveNative(
  () => libc?.lookupFunction<_HostProcessorInfoC, _HostProcessorInfoDart>(
    'host_processor_info',
  ),
);
final _VmDeallocateDart? _vmDeallocate = resolveNative(
  () =>
      libc?.lookupFunction<_VmDeallocateC, _VmDeallocateDart>('vm_deallocate'),
);

/// The host port and the task port are fixed for the process; both are
/// looked up once.
final int? _machHost = resolveNative(
  () => libc?.lookupFunction<_MachHostSelfC, _MachHostSelfDart>(
    'mach_host_self',
  )(),
);
final int? _machTask = resolveNative(
  () => libc?.lookup<ffi.Uint32>('mach_task_self_').value,
);

CpuTicks? _macCpuTicks() {
  final hostProcessorInfo = _hostProcessorInfo;
  final vmDeallocate = _vmDeallocate;
  final host = _machHost;
  final task = _machTask;
  if (hostProcessorInfo == null ||
      vmDeallocate == null ||
      host == null ||
      task == null) {
    return null;
  }

  final cpuCount = calloc<ffi.Uint32>();
  final infoArray = calloc<ffi.Pointer<ffi.Int32>>();
  final infoCount = calloc<ffi.Uint32>();
  try {
    final kr = hostProcessorInfo(
      host,
      _processorCpuLoadInfo,
      cpuCount,
      infoArray,
      infoCount,
    );
    if (kr != 0) return null;
    final address = infoArray.value;
    final values = address.asTypedList(infoCount.value);
    var user = 0, system = 0, idle = 0, nice = 0;
    for (var cpu = 0; cpu < cpuCount.value; cpu++) {
      final at = cpu * _cpuStateMax;
      user += values[at] & 0xFFFFFFFF;
      system += values[at + 1] & 0xFFFFFFFF;
      idle += values[at + 2] & 0xFFFFFFFF;
      nice += values[at + 3] & 0xFFFFFFFF;
    }
    // The array belongs to this process; the kernel handed it over.
    vmDeallocate(task, address.address, infoCount.value * 4);
    return cpuTicksFromMacTotals(
      user: user,
      system: system,
      idle: idle,
      nice: nice,
    );
  } finally {
    calloc
      ..free(cpuCount)
      ..free(infoArray)
      ..free(infoCount);
  }
}

/// Interval of the card's readings. Tests run it on simulated time (fakeAsync).
const Duration systemUsagePollInterval = Duration(seconds: 3);

/// The card's figures. Watched only by the card: auto-disposed, so leaving the
/// Übersicht drops the timer with the last listener.
class SystemUsageState {
  const SystemUsageState({
    this.loaded = false,
    this.cpuReadable,
    this.cpuPercent,
    this.ramTotalMB,
    this.ramAvailableMB,
    this.diskFreeBytes,
    this.ramLow = false,
    this.diskLow = false,
  });

  /// False until the first reading came in.
  final bool loaded;

  /// Whether the CPU counters can be read here; `null` before the first try.
  final bool? cpuReadable;

  /// Load of the whole machine, `0` to `100`. Needs two readings, so it stays
  /// `null` for the first tick.
  final double? cpuPercent;
  final int? ramTotalMB;
  final int? ramAvailableMB;
  final int? diskFreeBytes;

  /// Free memory is below the speech engine's pressure threshold.
  final bool ramLow;

  /// The data volume is nearly full.
  final bool diskLow;
}

class SystemUsageNotifier extends Notifier<SystemUsageState> {
  Timer? _timer;
  bool _active = false;
  bool _reading = false;
  CpuTicks? _previousCpu;

  @override
  SystemUsageState build() {
    ref.onDispose(_stopTimer);
    return const SystemUsageState();
  }

  /// Starts polling while the card is shown and the window is active, stops
  /// it otherwise. The earlier CPU reading is dropped on a stop, so the load
  /// after a pause is not averaged over the pause.
  void setActive({required bool active}) {
    if (active == _active) return;
    _active = active;
    if (active) {
      _startTimer();
    } else {
      _stopTimer();
      _previousCpu = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    unawaited(_poll());
    _timer = Timer.periodic(systemUsagePollInterval, (_) => _poll());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_reading) return;
    _reading = true;
    try {
      final sample = await ref.read(systemUsageReaderProvider)();
      if (!ref.mounted || !_active) return;
      final cpu = sample.cpu;
      final previous = _previousCpu;
      final percent = cpu != null && previous != null
          ? cpuPercentBetween(previous, cpu)
          : null;
      _previousCpu = cpu;
      final ram = sample.ram;
      state = SystemUsageState(
        loaded: true,
        cpuReadable: cpu != null,
        cpuPercent: percent,
        ramTotalMB: ram?.totalMB,
        ramAvailableMB: ram?.availableMB,
        diskFreeBytes: sample.diskFreeBytes,
        ramLow:
            ram != null &&
            isRamLow(
              totalMB: ram.totalMB,
              availableMB: ram.availableMB,
              lowFraction: kLowMemoryAvailableFraction,
            ),
        diskLow: isDiskLow(sample.diskFreeBytes),
      );
    } on Object catch (e) {
      // Fail open: the next tick tries again, the old figures stay.
      _log.debug('System reading failed: $e');
    } finally {
      _reading = false;
    }
  }
}

final systemUsageProvider =
    NotifierProvider.autoDispose<SystemUsageNotifier, SystemUsageState>(
      SystemUsageNotifier.new,
    );
