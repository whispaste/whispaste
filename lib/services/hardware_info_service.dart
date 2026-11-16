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
import '../core/logging/user_path_scrubber.dart';

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

/// Registers the GPU-detection-failure callback. The CPU fallback works, so
/// the report is a warning: it stays in the log and as a breadcrumb and
/// never becomes a Sentry event on its own (rule 2026-10-27).
///
/// Call once at app startup (after Sentry and CrashReporter are initialized).
/// The callback fires at most once per session per [clearGpuCache] cycle.
void initHardwareInfoTelemetry() {
  diag.setGpuDetectionFailureCallback(({
    required String reason,
    bool cudaAvailable = false,
    List<String> adapterNames = const [],
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
        'gpu_adapters': gpuAdapterNamesForTelemetry(adapterNames),
      },
    );
  });
}

/// At most this many adapter names are sent (multi-GPU laptops rarely exceed
/// two; the cap bounds the event size).
const int _maxTelemetryAdapters = 4;

/// Longer names are cut: a real adapter string is well under this.
const int _maxTelemetryAdapterNameLength = 100;

/// Prepares raw adapter names from the GPU probes for Sentry extras.
///
/// Adapter names are hardware identifiers, not personal data, so they are
/// sent as-is apart from two guards: the OS account name and home paths are
/// scrubbed with the same [scrubUserPaths] used for crash text (a driver or
/// adapter string can embed a profile path), and the list and each name are
/// capped. Empty names are dropped.
@visibleForTesting
List<String> gpuAdapterNamesForTelemetry(List<String> adapterNames) {
  final out = <String>[];
  for (final raw in adapterNames) {
    if (out.length == _maxTelemetryAdapters) break;
    var name = scrubUserPaths(raw.trim());
    if (name.length > _maxTelemetryAdapterNameLength) {
      name = name.substring(0, _maxTelemetryAdapterNameLength);
    }
    if (name.isNotEmpty) out.add(name);
  }
  return out;
}

/// A driver version string is sent only in this shape: a leading digit, then
/// letters, digits, dots, dashes or underscores, at most 40 characters. A
/// version never contains a path or a user name, so anything else is dropped.
final _driverVersionPattern = RegExp(r'^[0-9][0-9A-Za-z._-]{0,39}$');

/// The driver version to report, or `unknown` when the OS did not provide a
/// plain version string (macOS Metal has none; the probe may come back empty).
String gpuDriverVersionForTelemetry(String? raw) {
  final version = raw?.trim() ?? '';
  return _driverVersionPattern.hasMatch(version) ? version : 'unknown';
}
