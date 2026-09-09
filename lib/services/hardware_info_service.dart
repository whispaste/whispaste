/// Cross-platform hardware detection for optimal AI inference backend selection.
///
/// This file is the app-layer adapter for `package:whispaste_diagnostics`.
/// All core logic (GpuInfo, GpuVendor, detection, binary compatibility,
/// RAM helpers) lives in the pure-Dart package; this file re-exports it
/// and adds the Flutter/Riverpod bindings and the Sentry telemetry callback
/// that the core package cannot reference directly.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

// ---------------------------------------------------------------------------
// GPU-vendor-distribution telemetry (Ticket 10 — CUDA-build decision)
// ---------------------------------------------------------------------------
//
// Extends the existing opt-out Sentry channel (same consent gate and
// anonymous device id as every other CrashReporter event — no new consent
// mechanism) with one anonymous, info-level "vendor" + "platform" signal per
// app session, so a later CUDA-build decision can be made on real numbers.
// Deliberately reported, not just detected: `detectGpu()` itself stays
// cross-platform (it already runs on macOS too, for the local backend
// selection every platform needs) — only *this report* is gated to
// Windows/Linux, since macOS has a fundamentally different GPU landscape
// (Apple Silicon unified memory, no CUDA/Vulkan choice to inform) and is not
// a target of the CUDA-build decision (see
// `.scratch/fluidvoice-catchup/issues/10-gpu-vendor-telemetrie.md`). Gating
// the report rather than restructuring `detectGpu()`/the provider keeps this
// additive and keeps every existing caller of the cross-platform detector
// unchanged.

/// Whether the GPU-vendor-distribution signal should be reported for
/// [operatingSystem] (a [Platform.operatingSystem]-shaped string).
///
/// Pure predicate — extracted so the OS gate is unit-testable without
/// mocking `Platform` (same pattern as `updateChannelDimension` in
/// `telemetry_service.dart`).
bool shouldReportGpuVendorTelemetry(String operatingSystem) =>
    operatingSystem == 'windows' || operatingSystem == 'linux';

/// One-shot guard so [reportGpuVendorTelemetry] sends at most once per app
/// session. Re-armed by [resetGpuVendorTelemetryForTesting].
bool _gpuVendorTelemetrySent = false;

/// Reports the anonymous GPU-vendor-distribution signal for [gpu] over the
/// existing opt-out Sentry channel — at most once per app session, and only
/// on Windows/Linux (see [shouldReportGpuVendorTelemetry]).
///
/// The payload is deliberately exactly two categorical fields — `vendor`
/// (e.g. `nvidia`/`amd`/`intel`/`none`) and `platform` — never a device
/// name, serial, or any content. Covered by
/// `test/services/gpu_vendor_telemetry_test.dart`, which pins the exact
/// field set as a regression guard.
///
/// [operatingSystem] defaults to [Platform.operatingSystem]; tests inject a
/// fixed value since `Platform` itself cannot be mocked.
void reportGpuVendorTelemetry(GpuInfo gpu, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  if (_gpuVendorTelemetrySent) return;
  if (!shouldReportGpuVendorTelemetry(os)) return;
  _gpuVendorTelemetrySent = true;

  CrashReporter.instance?.captureError(
    message: 'GPU vendor telemetry (Ticket 10 — CUDA build decision)',
    severity: 'info',
    type: 'gpu_vendor_telemetry',
    fingerprint: const [gpuVendorTelemetry],
    extras: {'vendor': gpu.vendor.name, 'platform': os},
  );
}

/// Re-arms the once-per-session guard for [reportGpuVendorTelemetry].
/// Test-only.
@visibleForTesting
void resetGpuVendorTelemetryForTesting() {
  _gpuVendorTelemetrySent = false;
}
