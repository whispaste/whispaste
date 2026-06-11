/// Cross-platform hardware detection for optimal AI inference backend selection.
///
/// This file is the app-layer adapter for `package:whispaste_diagnostics`.
/// All core logic (GpuInfo, GpuVendor, detection, binary compatibility,
/// RAM helpers) lives in the pure-Dart package; this file re-exports it
/// and adds the Flutter/Riverpod bindings and the Sentry telemetry callback
/// that the core package cannot reference directly.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart' as diag;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show GpuInfo, detectGpu;

import '../core/logging/app_logger.dart';
import '../core/logging/crash_fingerprints.dart';
import '../core/logging/crash_reporter.dart';

// ---------------------------------------------------------------------------
// Re-exports — keep callers unchanged
// ---------------------------------------------------------------------------

export 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show
        GpuInfo,
        GpuVendor,
        ProcessRunner,
        kMinRamMB,
        kRamCheckThresholdMB,
        kWindowsGpuProbeTimeout,
        sttModelVramMB,
        serverAssetPatterns,
        detectGpu,
        cachedGpuInfo,
        clearGpuCache,
        setProcessRunnerForTesting,
        detectGpuWindowsForTesting,
        captureGpuDetectionFailureOnce,
        isServerBinaryCompatible,
        writeServerBinaryInfo,
        readServerBinaryInfo,
        validateAndCleanIncompatibleBinary,
        deleteServerBinary,
        vcRuntimeDllNames,
        vcRuntimeDllsPresent,
        backendLoaderDllNames,
        firstUnresolvableBackendLoaderDllFor,
        firstUnresolvableBackendLoaderDll,
        listServerDirFiles,
        parseSysctlMemsizeMb,
        parseLinuxMemTotalMb,
        parseWmicOsMemoryMb,
        detectRamMB,
        shouldUseGpu;

// ---------------------------------------------------------------------------
// Riverpod provider — app-side only
// ---------------------------------------------------------------------------

/// Provides GPU info as a [FutureProvider], making it testable and overridable.
final gpuInfoProvider = FutureProvider<GpuInfo>((ref) => detectGpu());

// ---------------------------------------------------------------------------
// Sentry telemetry wiring
// ---------------------------------------------------------------------------

final _log = AppLogger('HardwareInfo');

/// Registers the GPU-detection-failure callback that routes events to Sentry.
///
/// Call once at app startup (after Sentry and CrashReporter are initialized).
/// The callback fires at most once per session per [clearGpuCache] cycle.
void initHardwareInfoTelemetry() {
  diag.setGpuDetectionFailureCallback(({
    required String reason,
    bool cudaAvailable = false,
  }) {
    _log.warning('GPU detection failed, defaulting to CPU: $reason');
    CrashReporter.instance?.captureError(
      message: 'GPU detection failed — falling back to CPU ($reason)',
      severity: 'warning',
      type: 'gpu_detection_failed',
      fingerprint: const [gpuDetectionFailed],
      extras: {
        'reason': reason,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'cuda_available': cudaAvailable,
        'num_processors': Platform.numberOfProcessors,
      },
    );
  });
}
