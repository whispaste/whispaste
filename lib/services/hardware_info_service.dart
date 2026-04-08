/// Cross-platform hardware detection for optimal AI inference backend selection.
///
/// Detects the primary GPU vendor and capabilities to determine which
/// whisper-server binary variant (CUDA, Vulkan, CPU) should be downloaded
/// and whether flash-attention or GPU acceleration should be enabled.
library;

import 'dart:io';

import '../core/logging/app_logger.dart';

final _log = AppLogger('HardwareInfo');

// ---------------------------------------------------------------------------
// GPU vendor enum
// ---------------------------------------------------------------------------

/// GPU vendor categories that map to whisper-server binary variants.
enum GpuVendor {
  nvidia, // → CUDA backend (best perf with NVIDIA GPUs)
  amd, // → Vulkan backend
  intel, // → Vulkan backend
  apple, // → Metal backend (macOS/iOS, Apple Silicon)
  none, // → CPU (OpenBLAS) backend
}

// ---------------------------------------------------------------------------
// GPU info
// ---------------------------------------------------------------------------

/// Detected GPU information used for binary selection and server configuration.
class GpuInfo {
  const GpuInfo({
    required this.vendor,
    required this.name,
    this.vramMB,
    this.cudaAvailable = false,
    this.vulkanAvailable = false,
  });

  final GpuVendor vendor;
  final String name;
  final int? vramMB;
  final bool cudaAvailable;
  final bool vulkanAvailable;

  /// The optimal whisper-server binary variant for this GPU.
  String get optimalBackend {
    switch (vendor) {
      case GpuVendor.nvidia:
        return cudaAvailable ? 'cuda' : 'vulkan';
      case GpuVendor.amd:
      case GpuVendor.intel:
        return 'vulkan';
      case GpuVendor.apple:
        return 'metal';
      case GpuVendor.none:
        return 'cpu';
    }
  }

  /// Whether any GPU is available for acceleration.
  bool get hasGpu => vendor != GpuVendor.none;

  /// Whether flash attention is supported (CUDA-only currently).
  bool get supportsFlashAttn => vendor == GpuVendor.nvidia && cudaAvailable;

  @override
  String toString() =>
      'GpuInfo($vendor, "$name", vram=${vramMB ?? "?"}MB, '
      'cuda=$cudaAvailable, vulkan=$vulkanAvailable, '
      'backend=$optimalBackend)';
}

// ---------------------------------------------------------------------------
// Cached detection
// ---------------------------------------------------------------------------

GpuInfo? _cached;

/// Detects the primary GPU. Result is cached after the first call.
///
/// Detection is fast (~100–500ms) and runs once per session. Subsequent
/// calls return immediately from cache.
Future<GpuInfo> detectGpu() async {
  if (_cached != null) return _cached!;

  try {
    if (Platform.isWindows) {
      _cached = await _detectWindows();
    } else if (Platform.isMacOS) {
      _cached = await _detectMacOS();
    } else if (Platform.isLinux) {
      _cached = await _detectLinux();
    } else {
      _cached = const GpuInfo(vendor: GpuVendor.none, name: 'Unsupported OS');
    }
  } catch (e) {
    _log.warning('GPU detection failed, defaulting to CPU: $e');
    _cached = const GpuInfo(vendor: GpuVendor.none, name: 'Detection failed');
  }

  _log.info('Detected GPU: $_cached');
  return _cached!;
}

/// Returns cached GPU info if available, `null` otherwise.
///
/// Use [detectGpu] for the initial detection. This getter is for code
/// that needs a synchronous check after detection has already run.
GpuInfo? get cachedGpuInfo => _cached;

/// Clears the cached GPU info. Intended for testing only.
void clearGpuCache() => _cached = null;

// ---------------------------------------------------------------------------
// Asset pattern mapping
// ---------------------------------------------------------------------------

/// Returns the asset name patterns in priority order for the detected GPU.
///
/// [gpuMode] is the user's GPU preference: 'auto', 'enabled', 'disabled'.
/// [isWhisPaste] selects between WhisPaste and upstream whisper.cpp naming.
List<String> serverAssetPatterns(GpuInfo gpu, String gpuMode, bool isWhisPaste) {
  if (gpuMode == 'disabled') {
    return isWhisPaste ? ['cpu'] : ['blas-bin'];
  }

  // Map GPU vendor → binary variant priority.
  if (isWhisPaste) {
    switch (gpu.vendor) {
      case GpuVendor.nvidia:
        return gpu.cudaAvailable
            ? ['cuda12', 'vulkan', 'cpu']
            : ['vulkan', 'cpu'];
      case GpuVendor.amd:
      case GpuVendor.intel:
        return ['vulkan', 'cpu'];
      case GpuVendor.apple:
        return ['metal', 'cpu'];
      case GpuVendor.none:
        return ['cpu'];
    }
  } else {
    // Upstream whisper.cpp naming.
    switch (gpu.vendor) {
      case GpuVendor.nvidia:
        return gpu.cudaAvailable
            ? ['cublas-12', 'vulkan', 'blas-bin']
            : ['vulkan', 'blas-bin'];
      case GpuVendor.amd:
      case GpuVendor.intel:
        return ['vulkan', 'blas-bin'];
      case GpuVendor.apple:
        return ['metal', 'blas-bin'];
      case GpuVendor.none:
        return ['blas-bin'];
    }
  }
}

// ---------------------------------------------------------------------------
// Binary compatibility check
// ---------------------------------------------------------------------------

/// Checks if the existing whisper-server binary in [sttDir] is compatible
/// with the detected GPU.
///
/// Returns `true` if compatible or no binary exists. Returns `false` if a
/// CUDA binary is installed on a non-NVIDIA system (or vice versa).
bool isServerBinaryCompatible(String sttDirPath, GpuInfo gpu) {
  final cudaDlls = ['cublas64_12.dll', 'cublaslt64_12.dll', 'ggml-cuda.dll'];
  final hasCudaDlls = cudaDlls.any(
    (dll) => File('$sttDirPath${Platform.pathSeparator}$dll').existsSync(),
  );

  if (hasCudaDlls && gpu.vendor != GpuVendor.nvidia) {
    _log.warning(
      'Incompatible binary: CUDA build installed but GPU is ${gpu.vendor} '
      '(${gpu.name}). Binary needs re-download.',
    );
    return false;
  }

  return true;
}

/// Deletes the whisper-server binary and all associated DLLs from [sttDirPath].
///
/// Used to force a re-download of the correct binary variant.
Future<void> deleteServerBinary(String sttDirPath) async {
  final dir = Directory(sttDirPath);
  if (!dir.existsSync()) return;

  var deleted = 0;
  for (final entity in dir.listSync()) {
    if (entity is File) {
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (name.endsWith('.exe') || name.endsWith('.dll')) {
        try {
          await entity.delete();
          deleted++;
        } on FileSystemException catch (e) {
          _log.warning('Could not delete $name: $e');
        }
      }
    }
  }
  _log.info('Deleted $deleted server binary files from $sttDirPath');
}

// ---------------------------------------------------------------------------
// Windows detection
// ---------------------------------------------------------------------------

Future<GpuInfo> _detectWindows() async {
  // Phase 1: Quick check — is CUDA runtime available?
  final cudaAvailable = File(r'C:\Windows\System32\nvcuda.dll').existsSync();

  // Phase 2: Get GPU name(s) via wmic (faster than PowerShell).
  String gpuName = 'Unknown';
  GpuVendor vendor = GpuVendor.none;
  int? vramMB;

  final parsed = await _wmicGetGpus();
  if (parsed != null) {
    gpuName = parsed.name;
    vendor = parsed.vendor;
    vramMB = parsed.vramMB;
  } else {
    // Fallback: PowerShell (slower but more reliable on newer Windows).
    final psParsed = await _powershellGetGpus();
    if (psParsed != null) {
      gpuName = psParsed.name;
      vendor = psParsed.vendor;
      vramMB = psParsed.vramMB;
    }
  }

  // Dual-GPU detection: if CUDA DLLs exist but wmic found Intel/AMD as
  // primary display adapter, an NVIDIA discrete GPU is likely available.
  if (cudaAvailable && vendor != GpuVendor.nvidia) {
    _log.info(
      'nvcuda.dll found but primary adapter is $vendor ($gpuName). '
      'NVIDIA discrete GPU likely available — preferring CUDA.',
    );
    vendor = GpuVendor.nvidia;
    gpuName = '$gpuName + NVIDIA (discrete)';
  }

  return GpuInfo(
    vendor: vendor,
    name: gpuName,
    vramMB: vramMB,
    cudaAvailable: cudaAvailable,
    vulkanAvailable: vendor != GpuVendor.none,
  );
}

/// Queries GPU info via wmic (deprecated but still fast and widely available).
Future<_GpuParsed?> _wmicGetGpus() async {
  try {
    final result = await Process.run('wmic', [
      'path',
      'win32_videocontroller',
      'get',
      'name,adapterram',
      '/format:list',
    ]).timeout(const Duration(seconds: 5));

    if (result.exitCode != 0) return null;
    return _parseWmicList(result.stdout.toString());
  } catch (e) {
    _log.debug('wmic query failed: $e');
    return null;
  }
}

/// Parses wmic `/format:list` output.
///
/// Each GPU is a block of key=value lines separated by blank lines:
/// ```
/// AdapterRAM=1073741824
/// Name=Intel(R) Iris(R) Xe Graphics
/// ```
_GpuParsed? _parseWmicList(String output) {
  final gpus = <_GpuParsed>[];
  String? currentName;
  int? currentVram;

  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      // End of a GPU block.
      if (currentName != null && currentName.isNotEmpty) {
        gpus.add(_GpuParsed(
          name: currentName,
          vendor: _classifyVendor(currentName),
          vramMB: currentVram,
        ));
      }
      currentName = null;
      currentVram = null;
      continue;
    }

    final eqIdx = trimmed.indexOf('=');
    if (eqIdx < 0) continue;
    final key = trimmed.substring(0, eqIdx).trim().toLowerCase();
    final value = trimmed.substring(eqIdx + 1).trim();

    if (key == 'name') {
      currentName = value;
    } else if (key == 'adapterram') {
      final bytes = int.tryParse(value);
      if (bytes != null && bytes > 0) {
        currentVram = bytes ~/ (1024 * 1024);
      }
    }
  }

  // Flush last block.
  if (currentName != null && currentName.isNotEmpty) {
    gpus.add(_GpuParsed(
      name: currentName,
      vendor: _classifyVendor(currentName),
      vramMB: currentVram,
    ));
  }

  if (gpus.isEmpty) return null;

  // Prefer discrete GPU: NVIDIA > AMD > Intel > None.
  gpus.sort((a, b) => a.vendor.index.compareTo(b.vendor.index));
  return gpus.first;
}

/// Fallback: PowerShell Get-CimInstance (slower but available on all Win10+).
Future<_GpuParsed?> _powershellGetGpus() async {
  try {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_VideoController | '
          r'ForEach-Object { "$($_.Name)|$($_.AdapterRAM)" }',
    ]).timeout(const Duration(seconds: 10));

    if (result.exitCode != 0) return null;

    final gpus = <_GpuParsed>[];
    for (final line in result.stdout.toString().split('\n')) {
      final parts = line.trim().split('|');
      if (parts.isEmpty || parts[0].isEmpty) continue;

      final name = parts[0];
      final vramBytes = parts.length > 1 ? int.tryParse(parts[1]) : null;

      gpus.add(_GpuParsed(
        name: name,
        vendor: _classifyVendor(name),
        vramMB: vramBytes != null && vramBytes > 0
            ? vramBytes ~/ (1024 * 1024)
            : null,
      ));
    }

    if (gpus.isEmpty) return null;
    gpus.sort((a, b) => a.vendor.index.compareTo(b.vendor.index));
    return gpus.first;
  } catch (e) {
    _log.debug('PowerShell GPU query failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// macOS detection
// ---------------------------------------------------------------------------

Future<GpuInfo> _detectMacOS() async {
  // Check for Apple Silicon (ARM64).
  try {
    final uname = await Process.run('uname', ['-m']);
    if (uname.stdout.toString().trim() == 'arm64') {
      String chipName = 'Apple Silicon';
      try {
        final sysctl =
            await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
        final brand = sysctl.stdout.toString().trim();
        if (brand.isNotEmpty) chipName = brand;
      } catch (_) {}

      return GpuInfo(
        vendor: GpuVendor.apple,
        name: chipName,
      );
    }
  } catch (_) {}

  // Intel Mac — check for discrete GPU.
  try {
    final result = await Process.run('system_profiler', [
      'SPDisplaysDataType',
      '-detailLevel',
      'mini',
    ]).timeout(const Duration(seconds: 10));

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      final chipName = _extractMacGpuName(output);
      final lower = output.toLowerCase();

      if (lower.contains('amd') || lower.contains('radeon')) {
        return GpuInfo(
          vendor: GpuVendor.amd,
          name: chipName ?? 'AMD GPU',
          vulkanAvailable: true,
        );
      }
      // NVIDIA on Mac is rare (pre-2016) and CUDA is unsupported on modern macOS.
    }
  } catch (_) {}

  // Fallback: Intel integrated on Intel Mac.
  return const GpuInfo(vendor: GpuVendor.intel, name: 'Intel (Mac)');
}

String? _extractMacGpuName(String profilerOutput) {
  for (final line in profilerOutput.split('\n')) {
    if (line.contains('Chipset Model:') || line.contains('Chip:')) {
      return line.split(':').last.trim();
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Linux detection
// ---------------------------------------------------------------------------

Future<GpuInfo> _detectLinux() async {
  // Phase 1: Check PCI vendor IDs via sysfs (fastest, no external tools).
  try {
    final drmDir = Directory('/sys/class/drm');
    if (drmDir.existsSync()) {
      for (final card in drmDir.listSync()) {
        final vendorFile = File('${card.path}/device/vendor');
        if (!vendorFile.existsSync()) continue;
        final vendorId = vendorFile.readAsStringSync().trim().toLowerCase();

        // PCI Vendor IDs: 0x10de=NVIDIA, 0x1002=AMD, 0x8086=Intel
        if (vendorId == '0x10de') {
          return GpuInfo(
            vendor: GpuVendor.nvidia,
            name: await _linuxGpuName() ?? 'NVIDIA GPU',
            cudaAvailable: _linuxHasCuda(),
            vulkanAvailable: true,
          );
        }
        if (vendorId == '0x1002') {
          return GpuInfo(
            vendor: GpuVendor.amd,
            name: await _linuxGpuName() ?? 'AMD GPU',
            vulkanAvailable: true,
          );
        }
        if (vendorId == '0x8086') {
          return GpuInfo(
            vendor: GpuVendor.intel,
            name: await _linuxGpuName() ?? 'Intel GPU',
            vulkanAvailable: true,
          );
        }
      }
    }
  } catch (_) {}

  // Phase 2: Fallback to lspci.
  try {
    final result = await Process.run('lspci', ['-nn']);
    if (result.exitCode == 0) {
      final output = result.stdout.toString().toLowerCase();
      if (output.contains('[10de:') || output.contains('nvidia')) {
        return GpuInfo(
          vendor: GpuVendor.nvidia,
          name: 'NVIDIA GPU',
          cudaAvailable: _linuxHasCuda(),
          vulkanAvailable: true,
        );
      }
      if (output.contains('[1002:') ||
          output.contains('amd') ||
          output.contains('radeon')) {
        return const GpuInfo(
          vendor: GpuVendor.amd,
          name: 'AMD GPU',
          vulkanAvailable: true,
        );
      }
      if (output.contains('[8086:') || output.contains('intel')) {
        return const GpuInfo(
          vendor: GpuVendor.intel,
          name: 'Intel GPU',
          vulkanAvailable: true,
        );
      }
    }
  } catch (_) {}

  return const GpuInfo(vendor: GpuVendor.none, name: 'No GPU detected');
}

Future<String?> _linuxGpuName() async {
  try {
    final result = await Process.run('lspci', []);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.contains('VGA') ||
          line.contains('3D controller') ||
          line.contains('Display controller')) {
        // Format: "00:02.0 VGA compatible controller: Intel Corporation ..."
        final colons = line.split(':');
        if (colons.length >= 3) return colons.sublist(2).join(':').trim();
      }
    }
  } catch (_) {}
  return null;
}

bool _linuxHasCuda() {
  return File('/usr/lib/x86_64-linux-gnu/libcuda.so').existsSync() ||
      File('/usr/lib64/libcuda.so').existsSync() ||
      File('/usr/bin/nvidia-smi').existsSync();
}

// ---------------------------------------------------------------------------
// Vendor classification
// ---------------------------------------------------------------------------

GpuVendor _classifyVendor(String gpuName) {
  final lower = gpuName.toLowerCase();
  if (lower.contains('nvidia') ||
      lower.contains('geforce') ||
      lower.contains('quadro') ||
      lower.contains('rtx ') ||
      lower.contains('tesla')) {
    return GpuVendor.nvidia;
  }
  if (lower.contains('amd') ||
      lower.contains('radeon') ||
      lower.contains('rx ')) {
    return GpuVendor.amd;
  }
  if (lower.contains('intel') ||
      lower.contains('iris') ||
      lower.contains('uhd') ||
      lower.contains('hd graphics')) {
    return GpuVendor.intel;
  }
  if (lower.contains('apple') ||
      lower.contains('m1') ||
      lower.contains('m2') ||
      lower.contains('m3') ||
      lower.contains('m4')) {
    return GpuVendor.apple;
  }
  return GpuVendor.none;
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _GpuParsed {
  _GpuParsed({required this.name, required this.vendor, this.vramMB});
  final String name;
  final GpuVendor vendor;
  final int? vramMB;
}
