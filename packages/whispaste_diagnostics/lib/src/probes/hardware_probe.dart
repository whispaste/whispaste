/// Hardware probe — RAM, CPU, GPU summary, disk space.
///
/// Pure-Dart (no Flutter). Uses an injectable [ProcessRunner] seam so tests
/// can feed canned command output without spawning real OS processes.
library;

import 'dart:io';

import 'package:meta/meta.dart';

import 'gpu_info.dart';

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Result of the hardware probe.
class HardwareProbeResult {
  const HardwareProbeResult({
    required this.ramTotalMb,
    required this.ramFreeMb,
    required this.ramScarce,
    required this.cpuModel,
    required this.cpuCores,
    required this.gpuName,
    required this.gpuVramMb,
    required this.diskFreeMb,
  });

  /// Total physical RAM in MB, or `null` when detection failed.
  final int? ramTotalMb;

  /// Free / available RAM in MB, or `null` when detection failed.
  final int? ramFreeMb;

  /// `true` when total RAM is below [kRamCheckThresholdMB] (§6.6).
  final bool ramScarce;

  /// CPU model string, or `null` when detection failed.
  final String? cpuModel;

  /// Logical CPU core count, or `null` when detection failed.
  final int? cpuCores;

  /// GPU name string, or `null` when not detected.
  final String? gpuName;

  /// GPU VRAM in MB, or `null` when not available.
  final int? gpuVramMb;

  /// Free disk space on the WhisPaste data partition in MB, or `null`.
  final int? diskFreeMb;
}

// ---------------------------------------------------------------------------
// Parsing helpers (pure, exported for unit tests)
// ---------------------------------------------------------------------------

/// Parses `sysctl -n hw.memsize` stdout into MB.
///
/// Named `parseHwMemsizeMb` to avoid collision with the same helper that
/// already exists in `gpu_info.dart` (which uses the same formula but was
/// defined there for the RAM check on startup).
@visibleForTesting
int? parseHwMemsizeMb(String output) {
  final bytes = int.tryParse(output.trim());
  if (bytes == null || bytes <= 0) return null;
  return bytes ~/ (1024 * 1024);
}

/// Parses `vm_stat` output (macOS) to derive free RAM in MB.
///
/// Looks for `Pages free:` and `Pages speculative:`, treats page size as 4096.
@visibleForTesting
int? parseVmStatFreeMb(String output, {int pageSize = 4096}) {
  int pages = 0;
  for (final line in output.split('\n')) {
    final trim = line.trim();
    int? extractPages(String prefix) {
      if (!trim.startsWith(prefix)) return null;
      final raw = trim.substring(prefix.length).trim().replaceAll('.', '');
      return int.tryParse(raw);
    }

    final free = extractPages('Pages free:');
    final spec = extractPages('Pages speculative:');
    if (free != null) pages += free;
    if (spec != null) pages += spec;
  }
  if (pages <= 0) return null;
  return (pages * pageSize) ~/ (1024 * 1024);
}

/// Parses `sysctl -n machdep.cpu.brand_string` stdout.
@visibleForTesting
String? parseSysctlCpuBrand(String output) {
  final s = output.trim();
  return s.isEmpty ? null : s;
}

/// Parses `sysctl -n hw.logicalcpu` stdout.
@visibleForTesting
int? parseSysctlLogicalCpu(String output) => int.tryParse(output.trim());

/// Parses `wmic os get FreePhysicalMemory /Value` stdout into MB.
@visibleForTesting
int? parseWmicFreeMemoryMb(String output) {
  final match = RegExp(r'FreePhysicalMemory=(\d+)').firstMatch(output);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1) ?? '');
  if (kb == null || kb <= 0) return null;
  return kb ~/ 1024;
}

/// Parses `wmic cpu get name,NumberOfLogicalProcessors /Value` stdout.
///
/// Returns a record with `model` and `cores`.
@visibleForTesting
({String? model, int? cores}) parseWmicCpuInfo(String output) {
  String? model;
  int? cores;
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    final eq = trimmed.indexOf('=');
    if (eq < 0) continue;
    final key = trimmed.substring(0, eq).trim().toLowerCase();
    final val = trimmed.substring(eq + 1).trim();
    if (key == 'name' && val.isNotEmpty) model = val;
    if (key == 'numberoflogicalprocessors') cores = int.tryParse(val);
  }
  return (model: model, cores: cores);
}

/// Parses a Linux `/proc/meminfo` snippet for `MemTotal` and `MemAvailable`
/// lines into `(totalMb, freeMb)`.
@visibleForTesting
({int? totalMb, int? freeMb}) parseLinuxMemInfo(String memInfoContent) {
  int? totalMb;
  int? freeMb;
  for (final line in memInfoContent.split('\n')) {
    final matchTotal = RegExp(r'^MemTotal:\s+(\d+)').firstMatch(line);
    final matchFree = RegExp(r'^MemAvailable:\s+(\d+)').firstMatch(line);
    if (matchTotal != null) {
      final kb = int.tryParse(matchTotal.group(1) ?? '');
      if (kb != null && kb > 0) totalMb = kb ~/ 1024;
    }
    if (matchFree != null) {
      final kb = int.tryParse(matchFree.group(1) ?? '');
      if (kb != null && kb > 0) freeMb = kb ~/ 1024;
    }
  }
  return (totalMb: totalMb, freeMb: freeMb);
}

/// Parses `df -k` output to extract free MB for a given mount path.
///
/// Looks for the row whose mount point matches [path] or is a prefix of [path].
@visibleForTesting
int? parseDfFreeMb(String output, String path) {
  // df -k: Filesystem  1K-blocks  Used  Available  Capacity  Mounted-on
  // macOS has slightly different column order but `Available` is col 3 (0-based)
  // and mount is the last field.
  int? bestFree;
  int bestMatchLen = -1;

  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 6) continue;
    final mount = parts.last;
    if (!path.startsWith(mount)) continue;
    if (mount.length <= bestMatchLen) continue;
    final availKb = int.tryParse(parts[3]);
    if (availKb == null || availKb < 0) continue;
    bestFree = availKb ~/ 1024;
    bestMatchLen = mount.length;
  }
  return bestFree;
}

// ---------------------------------------------------------------------------
// Probe input struct (injectable seam)
// ---------------------------------------------------------------------------

/// Raw inputs for [parseHardwareProbeResult].
///
/// Tests construct this directly with canned strings; the real probe fills it
/// by running OS commands.
class HardwareProbeInputs {
  const HardwareProbeInputs({
    this.ramTotalRaw,
    this.ramFreeRaw,
    this.cpuModelRaw,
    this.cpuCoresRaw,
    this.dfRaw,
    this.dfPath,
    this.gpuInfo,
  });

  /// Raw output of the RAM total command (platform-dependent format).
  final String? ramTotalRaw;

  /// Raw output of the RAM free/available command.
  final String? ramFreeRaw;

  /// Raw output of the CPU model command.
  final String? cpuModelRaw;

  /// Raw output of the CPU core count command.
  final String? cpuCoresRaw;

  /// Raw output of `df -k` (or equivalent).
  final String? dfRaw;

  /// Path used as reference for disk-free lookup in [dfRaw].
  final String? dfPath;

  /// Pre-detected GPU info (from [detectGpu] or a test fixture).
  final GpuInfo? gpuInfo;
}

// ---------------------------------------------------------------------------
// Pure parser — converts raw inputs to result model
// ---------------------------------------------------------------------------

/// Parses [HardwareProbeInputs] into a [HardwareProbeResult].
///
/// All parsing is platform-agnostic at the call site; the caller selects the
/// right parsing helper for each field.
///
/// [platform] selects which parsing strategy to use:
///   - `'macos'` — sysctl + vm_stat
///   - `'linux'` — /proc/meminfo
///   - `'windows'` — wmic
///   - any other value → all null
HardwareProbeResult parseHardwareProbeResult(
  HardwareProbeInputs inputs, {
  required String platform,
}) {
  int? ramTotalMb;
  int? ramFreeMb;
  String? cpuModel;
  int? cpuCores;

  switch (platform) {
    case 'macos':
      if (inputs.ramTotalRaw != null) {
        ramTotalMb = parseHwMemsizeMb(inputs.ramTotalRaw!);
      }
      if (inputs.ramFreeRaw != null) {
        ramFreeMb = parseVmStatFreeMb(inputs.ramFreeRaw!);
      }
      if (inputs.cpuModelRaw != null) {
        cpuModel = parseSysctlCpuBrand(inputs.cpuModelRaw!);
      }
      if (inputs.cpuCoresRaw != null) {
        cpuCores = parseSysctlLogicalCpu(inputs.cpuCoresRaw!);
      }

    case 'linux':
      if (inputs.ramTotalRaw != null) {
        final r = parseLinuxMemInfo(inputs.ramTotalRaw!);
        ramTotalMb = r.totalMb;
        ramFreeMb = r.freeMb;
      }
      if (inputs.cpuModelRaw != null) {
        cpuModel = _parseLinuxCpuModel(inputs.cpuModelRaw!);
      }
      if (inputs.cpuCoresRaw != null) {
        cpuCores = int.tryParse(inputs.cpuCoresRaw!.trim());
      }

    case 'windows':
      if (inputs.ramTotalRaw != null) {
        ramTotalMb = _parseWmicTotalMemoryMb(inputs.ramTotalRaw!);
      }
      if (inputs.ramFreeRaw != null) {
        ramFreeMb = parseWmicFreeMemoryMb(inputs.ramFreeRaw!);
      }
      if (inputs.cpuModelRaw != null) {
        final info = parseWmicCpuInfo(inputs.cpuModelRaw!);
        cpuModel = info.model;
        cpuCores = info.cores;
      }
  }

  int? diskFreeMb;
  if (inputs.dfRaw != null && inputs.dfPath != null) {
    diskFreeMb = parseDfFreeMb(inputs.dfRaw!, inputs.dfPath!);
  }

  final ramScarce = ramTotalMb != null && ramTotalMb < kRamCheckThresholdMB;

  return HardwareProbeResult(
    ramTotalMb: ramTotalMb,
    ramFreeMb: ramFreeMb,
    ramScarce: ramScarce,
    cpuModel: cpuModel ?? inputs.gpuInfo?.name,
    cpuCores: cpuCores,
    gpuName: inputs.gpuInfo?.name,
    gpuVramMb: inputs.gpuInfo?.vramMB,
    diskFreeMb: diskFreeMb,
  );
}

// ---------------------------------------------------------------------------
// Additional private parsers
// ---------------------------------------------------------------------------

int? _parseWmicTotalMemoryMb(String output) {
  final match = RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(output);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1) ?? '');
  if (kb == null || kb <= 0) return null;
  return kb ~/ 1024;
}

String? _parseLinuxCpuModel(String cpuInfoContent) {
  for (final line in cpuInfoContent.split('\n')) {
    if (line.startsWith('model name')) {
      final colon = line.indexOf(':');
      if (colon >= 0) return line.substring(colon + 1).trim();
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Live probe (calls OS commands)
// ---------------------------------------------------------------------------

/// Gathers hardware information from the running OS.
///
/// Best-effort: individual command failures degrade that field to `null`.
/// Wrap with [GpuInfo] already gathered via [detectGpu] to avoid a second
/// GPU-detection round.
Future<HardwareProbeResult> gatherHardwareProbe({GpuInfo? gpuInfo}) async {
  final platform = Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.isWindows
      ? 'windows'
      : 'unknown';

  String? ramTotalRaw;
  String? ramFreeRaw;
  String? cpuModelRaw;
  String? cpuCoresRaw;
  String? dfRaw;
  String? dfPath;

  try {
    if (Platform.isMacOS) {
      final r1 = await Process.run('/usr/sbin/sysctl', [
        '-n',
        'hw.memsize',
      ]).timeout(const Duration(seconds: 5));
      if (r1.exitCode == 0) ramTotalRaw = r1.stdout.toString();

      final r2 = await Process.run(
        'vm_stat',
        [],
      ).timeout(const Duration(seconds: 5));
      if (r2.exitCode == 0) ramFreeRaw = r2.stdout.toString();

      final r3 = await Process.run('/usr/sbin/sysctl', [
        '-n',
        'machdep.cpu.brand_string',
      ]).timeout(const Duration(seconds: 5));
      if (r3.exitCode == 0) cpuModelRaw = r3.stdout.toString();

      final r4 = await Process.run('/usr/sbin/sysctl', [
        '-n',
        'hw.logicalcpu',
      ]).timeout(const Duration(seconds: 5));
      if (r4.exitCode == 0) cpuCoresRaw = r4.stdout.toString();

      final dfPathMacOS = Platform.environment['HOME'] ?? '/';
      dfPath = dfPathMacOS;
      final r5 = await Process.run('df', [
        '-k',
        dfPathMacOS,
      ]).timeout(const Duration(seconds: 5));
      if (r5.exitCode == 0) dfRaw = r5.stdout.toString();
    } else if (Platform.isLinux) {
      try {
        ramTotalRaw = await File('/proc/meminfo').readAsString();
      } catch (_) {}

      try {
        cpuModelRaw = await File('/proc/cpuinfo').readAsString();
      } catch (_) {}

      try {
        cpuCoresRaw = (Platform.numberOfProcessors).toString();
      } catch (_) {}

      final dfPathLinux = Platform.environment['HOME'] ?? '/';
      dfPath = dfPathLinux;
      final r5 = await Process.run('df', [
        '-k',
        dfPathLinux,
      ]).timeout(const Duration(seconds: 5));
      if (r5.exitCode == 0) dfRaw = r5.stdout.toString();
    } else if (Platform.isWindows) {
      final r1 = await Process.run('wmic', [
        'os',
        'get',
        'TotalVisibleMemorySize',
        '/Value',
      ]).timeout(const Duration(seconds: 8));
      if (r1.exitCode == 0) ramTotalRaw = r1.stdout.toString();

      final r2 = await Process.run('wmic', [
        'os',
        'get',
        'FreePhysicalMemory',
        '/Value',
      ]).timeout(const Duration(seconds: 8));
      if (r2.exitCode == 0) ramFreeRaw = r2.stdout.toString();

      final r3 = await Process.run('wmic', [
        'cpu',
        'get',
        'name,NumberOfLogicalProcessors',
        '/Value',
      ]).timeout(const Duration(seconds: 8));
      if (r3.exitCode == 0) cpuModelRaw = r3.stdout.toString();
    }
  } catch (_) {
    // Best-effort — callers get null fields on any failure.
  }

  final gpu = gpuInfo ?? await detectGpu();

  return parseHardwareProbeResult(
    HardwareProbeInputs(
      ramTotalRaw: ramTotalRaw,
      ramFreeRaw: ramFreeRaw,
      cpuModelRaw: cpuModelRaw,
      cpuCoresRaw: cpuCoresRaw,
      dfRaw: dfRaw,
      dfPath: dfPath,
      gpuInfo: gpu,
    ),
    platform: platform,
  );
}
