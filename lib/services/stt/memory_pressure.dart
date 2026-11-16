/// System memory readings and the pressure policy for the on-device speech
/// engine.
///
/// The engine keeps a model of up to several GB resident. Under memory
/// pressure it is unloaded when no dictation runs, and reloaded once the
/// pressure is gone. Parsers and policy are pure so they can be tested on any
/// host; [readMemorySnapshot] is the only platform-bound part.
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/platform/native_libs.dart';

final _log = AppLogger('MemoryPressure');

/// Available memory below this fraction of total RAM counts as pressure.
const double kLowMemoryAvailableFraction = 0.10;

/// `kern.memorystatus_vm_pressure_level` at and above which macOS itself
/// reports pressure (1 normal, 2 warn, 4 critical).
const int kMacPressureWarnLevel = 2;

/// Point-in-time memory figures in MB.
class MemorySnapshot {
  const MemorySnapshot({
    required this.totalMB,
    required this.availableMB,
    this.systemPressureLevel,
  });

  final int totalMB;
  final int availableMB;

  /// The kernel's own pressure verdict on macOS
  /// (`kern.memorystatus_vm_pressure_level`), null elsewhere. The free share
  /// alone misses pressure there: with swap exhausted it stayed near 30 %
  /// while the kernel already reported "warn" and then suspended the app.
  final int? systemPressureLevel;

  double get availableFraction => availableMB / totalMB;
}

/// Latest memory reading, shared with the idle-unload decision. Kept apart from
/// the monitor so the speech engine can read it without importing the monitor.
class MemorySnapshotStore {
  MemorySnapshot? latest;
}

final memorySnapshotStoreProvider = Provider<MemorySnapshotStore>(
  (ref) => MemorySnapshotStore(),
);

enum MemoryPressure {
  /// No reading on this platform: the pressure unload is inactive.
  unknown,
  normal,
  low,
}

enum MemoryAction { none, unload, reload }

/// Parses `/proc/meminfo` (`MemTotal` and `MemAvailable`, both in kB).
MemorySnapshot? parseLinuxMeminfo(String text) {
  int? totalKB;
  int? availableKB;
  for (final line in text.split('\n')) {
    if (line.startsWith('MemTotal:')) {
      totalKB = _kBValue(line);
    } else if (line.startsWith('MemAvailable:')) {
      availableKB = _kBValue(line);
    }
  }
  if (totalKB == null || availableKB == null || totalKB <= 0) return null;
  return MemorySnapshot(
    totalMB: totalKB ~/ 1024,
    availableMB: availableKB ~/ 1024,
  );
}

int? _kBValue(String line) {
  final parts = line.split(RegExp(r'\s+'));
  return parts.length >= 2 ? int.tryParse(parts[1]) : null;
}

/// Builds a snapshot from macOS figures: `hw.memsize` in bytes,
/// `kern.memorystatus_level`, the free share of RAM in percent (the value
/// `memory_pressure -Q` reports), and `kern.memorystatus_vm_pressure_level`.
MemorySnapshot? snapshotFromMacFigures({
  required int? memsizeBytes,
  required int? freePercent,
  int? pressureLevel,
}) {
  if (memsizeBytes == null || memsizeBytes <= 0 || freePercent == null) {
    return null;
  }
  final totalMB = memsizeBytes ~/ (1024 * 1024);
  final percent = freePercent.clamp(0, 100);
  return MemorySnapshot(
    totalMB: totalMB,
    availableMB: totalMB * percent ~/ 100,
    systemPressureLevel: pressureLevel,
  );
}

/// Size of a `MEMORYSTATUSEX` buffer; `dwLength` must hold it on entry.
const _memoryStatusExSize = 64;

/// Builds a snapshot from `GlobalMemoryStatusEx` figures in bytes.
MemorySnapshot? snapshotFromWindowsFigures({
  required int totalPhysBytes,
  required int availPhysBytes,
}) {
  if (totalPhysBytes <= 0 || availPhysBytes < 0) return null;
  return MemorySnapshot(
    totalMB: totalPhysBytes ~/ (1024 * 1024),
    availableMB: availPhysBytes.clamp(0, totalPhysBytes) ~/ (1024 * 1024),
  );
}

/// Parses a `MEMORYSTATUSEX` buffer (little endian): `ullTotalPhys` at offset
/// 8 and `ullAvailPhys` at offset 16.
MemorySnapshot? parseWindowsMemoryStatus(ByteData buffer) {
  if (buffer.lengthInBytes < 24) return null;
  return snapshotFromWindowsFigures(
    totalPhysBytes: buffer.getUint64(8, Endian.little),
    availPhysBytes: buffer.getUint64(16, Endian.little),
  );
}

/// Low when little RAM is free or, on macOS, when the kernel reports warn or
/// critical pressure. Normal (and so a reload) needs both to have cleared.
MemoryPressure classifyMemoryPressure(MemorySnapshot? snapshot) {
  if (snapshot == null) return MemoryPressure.unknown;
  final kernelLevel = snapshot.systemPressureLevel;
  if (kernelLevel != null && kernelLevel >= kMacPressureWarnLevel) {
    return MemoryPressure.low;
  }
  return snapshot.availableFraction < kLowMemoryAvailableFraction
      ? MemoryPressure.low
      : MemoryPressure.normal;
}

/// What the monitor should do with the engine after a reading.
///
/// Unloads only an idle, loaded engine under pressure. Reloads only an engine
/// that this policy itself unloaded, once the pressure is gone and nothing is
/// being dictated. An unknown reading changes nothing.
MemoryAction memoryPressureAction({
  required MemoryPressure pressure,
  required bool isIdle,
  required bool engineLoaded,
  required bool unloadedByPressure,
}) {
  if (!isIdle) return MemoryAction.none;
  if (pressure == MemoryPressure.low && engineLoaded) {
    return MemoryAction.unload;
  }
  if (pressure == MemoryPressure.normal && unloadedByPressure) {
    return MemoryAction.reload;
  }
  return MemoryAction.none;
}

/// The reader used when a caller passes none: the precheck dialogs and the
/// pressure monitor. Tests run with it returning null (unknown), so no test
/// depends on the memory of the machine it runs on; see
/// test/flutter_test_config.dart. Production code never reassigns it.
Future<MemorySnapshot?> Function() defaultMemorySnapshotReader =
    readMemorySnapshot;

/// Longest the native memory call (macOS, Windows) is waited for. The poll
/// runs exactly while memory is short, when a native call can stall on
/// page-ins, so it runs on a helper isolate and gives up as "no reading"
/// (#337).
const Duration _nativeMemoryReadTimeout = Duration(seconds: 4);

/// Reads total and available memory from the OS.
///
/// Returns null where the reading fails, logged once by the monitor.
Future<MemorySnapshot?> readMemorySnapshot() async {
  try {
    if (Platform.isLinux) {
      return parseLinuxMeminfo(await File('/proc/meminfo').readAsString());
    }
    if (Platform.isMacOS) {
      return await runNativeProbe(
        _macMemorySnapshot,
        timeout: _nativeMemoryReadTimeout,
        fallback: null,
      );
    }
    if (Platform.isWindows) {
      return await runNativeProbe(
        _windowsMemorySnapshot,
        timeout: _nativeMemoryReadTimeout,
        fallback: null,
      );
    }
  } on Exception catch (e) {
    _log.debug('Memory reading failed: $e');
  }
  return null;
}

typedef _SysctlByNameC =
    ffi.Int32 Function(
      ffi.Pointer<Utf8> name,
      ffi.Pointer<ffi.Uint64> oldValue,
      ffi.Pointer<ffi.Size> oldLength,
      ffi.Pointer<ffi.Void> newValue,
      ffi.Size newLength,
    );
typedef _SysctlByNameDart =
    int Function(
      ffi.Pointer<Utf8> name,
      ffi.Pointer<ffi.Uint64> oldValue,
      ffi.Pointer<ffi.Size> oldLength,
      ffi.Pointer<ffi.Void> newValue,
      int newLength,
    );

MemorySnapshot? _macMemorySnapshot() => snapshotFromMacFigures(
  memsizeBytes: _sysctlUint('hw.memsize'),
  freePercent: _sysctlUint('kern.memorystatus_level')?.toInt(),
  pressureLevel: _sysctlUint('kern.memorystatus_vm_pressure_level'),
);

final _SysctlByNameDart? _sysctlByName = resolveNative(
  () => libc?.lookupFunction<_SysctlByNameC, _SysctlByNameDart>('sysctlbyname'),
);

/// Reads an integer sysctl (up to 8 bytes) through the C library, so no helper
/// process is started. Smaller values arrive zero-extended in the 8-byte
/// buffer. Returns null when the name is unknown.
int? _sysctlUint(String name) {
  final sysctl = _sysctlByName;
  if (sysctl == null) return null;
  final nameC = name.toNativeUtf8();
  final value = calloc<ffi.Uint64>();
  final length = calloc<ffi.Size>()..value = ffi.sizeOf<ffi.Uint64>();
  try {
    if (sysctl(nameC, value, length, ffi.nullptr, 0) != 0) return null;
    return value.value;
  } finally {
    calloc
      ..free(nameC)
      ..free(value)
      ..free(length);
  }
}

typedef _GlobalMemoryStatusExC = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>);
typedef _GlobalMemoryStatusExDart = int Function(ffi.Pointer<ffi.Uint8>);

final _GlobalMemoryStatusExDart? _globalMemoryStatusEx = resolveNative(
  () => kernel32
      ?.lookupFunction<_GlobalMemoryStatusExC, _GlobalMemoryStatusExDart>(
        'GlobalMemoryStatusEx',
      ),
);

/// Reads physical memory through `GlobalMemoryStatusEx` (kernel32), in-process
/// like the macOS sysctl reader. Returns null when the call fails.
MemorySnapshot? _windowsMemorySnapshot() {
  final status = _globalMemoryStatusEx;
  if (status == null) return null;
  final buffer = calloc<ffi.Uint8>(_memoryStatusExSize);
  try {
    final bytes = buffer.asTypedList(_memoryStatusExSize);
    ByteData.sublistView(
      bytes,
    ).setUint32(0, _memoryStatusExSize, Endian.little);
    if (status(buffer) == 0) return null;
    return parseWindowsMemoryStatus(ByteData.sublistView(bytes));
  } finally {
    calloc.free(buffer);
  }
}
