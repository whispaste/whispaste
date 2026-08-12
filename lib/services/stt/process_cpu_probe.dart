/// Cross-platform, subprocess-free sampling of this process's own cumulative
/// CPU time — the data source behind the status bar's backend-utilization
/// indicator (see `backend_utilization_notifier.dart`).
///
/// Deliberately never shells out to `ps`/`top`/`wmic`/`nvidia-smi`: this repo
/// already hit a real fork()+exec() deadlock hazard from unguarded
/// `Process.run` calls on the STT startup path (see `_runProcessGuarded`'s
/// doc comment in `packages/whispaste_diagnostics/lib/src/probes/gpu_info.dart`)
/// — a background poll timer is exactly the kind of call site that must not
/// reintroduce it. `getrusage`/`GetProcessTimes` are synchronous FFI calls
/// into libc/kernel32, not subprocesses.
///
/// This reads *this process's* CPU time, not true GPU utilization: there is
/// no portable, sudo-free, subprocess-free way to read NVIDIA/AMD/Apple GPU
/// load across macOS/Windows/Linux. See `backend_utilization_notifier.dart`
/// for how the reading is labelled so it's never presented as a GPU-load
/// number.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

/// This process's cumulative user+system CPU time at a point in wall-clock
/// time — two samples let a caller derive a percentage (see
/// [processCpuPercentBetween]).
class ProcessCpuSample {
  const ProcessCpuSample({required this.cpuTime, required this.wallTime});

  final Duration cpuTime;
  final DateTime wallTime;
}

/// Percentage of one CPU core [b] consumed relative to [a] (`b` must be the
/// later sample). `100` means one full core saturated throughout the window;
/// on an N-core machine the ceiling is `100 * N`. Clamped to that range —
/// scheduler jitter around a sample boundary can otherwise produce a stray
/// negative or over-100 blip.
double processCpuPercentBetween(ProcessCpuSample a, ProcessCpuSample b) {
  final wallDeltaUs = b.wallTime.difference(a.wallTime).inMicroseconds;
  if (wallDeltaUs <= 0) return 0;
  final cpuDeltaUs = b.cpuTime.inMicroseconds - a.cpuTime.inMicroseconds;
  final percent = (cpuDeltaUs / wallDeltaUs) * 100;
  final ceiling = (Platform.numberOfProcessors * 100).toDouble();
  return percent.clamp(0, ceiling);
}

/// Reads [ProcessCpuSample]s via `getrusage(RUSAGE_SELF)` (macOS/Linux) or
/// `GetProcessTimes` (Windows).
class ProcessCpuProbe {
  const ProcessCpuProbe();

  ProcessCpuSample sample() => ProcessCpuSample(
    cpuTime: Platform.isWindows ? _readWindows() : _readPosix(),
    wallTime: DateTime.now(),
  );

  static ffi.DynamicLibrary? _libc;

  /// `getrusage`'s `struct rusage` starts with two back-to-back `timeval`
  /// structs (`ru_utime`, `ru_stime`). Each is 16 bytes on both macOS and
  /// Linux 64-bit — 8-byte `tv_sec` + 8-byte `tv_usec` on Linux, 8-byte
  /// `tv_sec` + 4-byte `tv_usec` + 4 bytes of C struct-alignment padding on
  /// macOS (a `timeval` containing an 8-byte member is itself 8-byte
  /// aligned, so its size rounds up to a multiple of 8) — so only reading
  /// each `tv_sec` (whole seconds, ignoring the platform-specific `tv_usec`
  /// layout entirely) is safe on both without branching. Coarser than
  /// microsecond precision, which is fine for a background indicator polled
  /// every few seconds, not a real-time meter.
  Duration _readPosix() {
    final buf = malloc<ffi.Uint8>(256);
    try {
      final lib = _libc ??= ffi.DynamicLibrary.process();
      final getrusage = lib
          .lookupFunction<
            ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Uint8>),
            int Function(int, ffi.Pointer<ffi.Uint8>)
          >('getrusage');
      const rusageSelf = 0; // RUSAGE_SELF — stable across macOS and Linux.
      if (getrusage(rusageSelf, buf) != 0) return Duration.zero;

      final secs = buf.cast<ffi.Int64>();
      final userSec = secs[0]; // ru_utime.tv_sec (offset 0)
      final sysSec = secs[2]; // ru_stime.tv_sec (offset 16)
      return Duration(seconds: userSec + sysSec);
    } finally {
      malloc.free(buf);
    }
  }

  /// `FILETIME` is two `DWORD`s (low, high) in that order — reading it
  /// through a `Uint64` pointer combines them as a little-endian 64-bit
  /// value directly, matching `GetProcessTimes`' 100ns-tick units.
  Duration _readWindows() {
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess = kernel32
        .lookupFunction<ffi.IntPtr Function(), int Function()>(
          'GetCurrentProcess',
        );
    final getProcessTimes = kernel32
        .lookupFunction<
          ffi.Int32 Function(
            ffi.IntPtr,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Uint64>,
          ),
          int Function(
            int,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Uint64>,
            ffi.Pointer<ffi.Uint64>,
          )
        >('GetProcessTimes');

    final creation = malloc<ffi.Uint64>();
    final exit = malloc<ffi.Uint64>();
    final kernelTime = malloc<ffi.Uint64>();
    final userTime = malloc<ffi.Uint64>();
    try {
      final ok = getProcessTimes(
        getCurrentProcess(),
        creation,
        exit,
        kernelTime,
        userTime,
      );
      if (ok == 0) return Duration.zero;
      final totalTicks = kernelTime.value + userTime.value;
      return Duration(microseconds: totalTicks ~/ 10);
    } finally {
      malloc.free(creation);
      malloc.free(exit);
      malloc.free(kernelTime);
      malloc.free(userTime);
    }
  }
}
