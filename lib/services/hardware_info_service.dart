/// Cross-platform hardware detection for optimal AI inference backend selection.
///
/// Detects the primary GPU vendor and capabilities to determine which
/// whisper-server binary variant (CUDA, Vulkan, CPU) should be downloaded
/// and whether flash-attention or GPU acceleration should be enabled.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';

final _log = AppLogger('HardwareInfo');

// ---------------------------------------------------------------------------
// RAM requirement
// ---------------------------------------------------------------------------

/// Minimum system RAM required to run WhisPaste reliably (in MB).
///
/// Enforced at startup: the app shows a blocking screen and refuses to
/// proceed on systems below this threshold. 8 GB is required to load at
/// least the balanced STT model without memory pressure.
const int kMinRamMB = 8192;

/// Effective check threshold used in the startup preflight (in MB).
///
/// Windows and Linux report visible RAM, which is always slightly less than
/// physical RAM (BIOS holes, iGPU reservations, etc.). A machine with exactly
/// 8 GB of DIMMs typically reports 7617–7900 MB as `TotalVisibleMemorySize`.
/// Using 7500 MB as the check threshold avoids false-positives on legitimate
/// 8 GB machines while still blocking systems with less than ~7.3 GB physical.
///
/// macOS is safe: `sysctl hw.memsize` returns raw physical bytes.
const int kRamCheckThresholdMB = 7500;

// ---------------------------------------------------------------------------
// STT model VRAM requirements
// ---------------------------------------------------------------------------

/// Estimated VRAM requirements for each STT model (in MB).
/// These are conservative estimates: whisper models need the model weights in
/// VRAM PLUS scratch space for attention matrices and CUDA runtime overhead.
/// The actual peak usage can be 1.3–1.5× the model file size.
const Map<String, int> sttModelVramMB = {
  'whisper-small': 900,
  'whisper-medium': 1500,
  'whisper-large-v3-turbo': 2600,
};

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

  /// Whether flash attention is supported.
  ///
  /// Flash Attention in whisper.cpp requires CUDA compute capability sm_75+
  /// (Turing architecture, 2018+). Older NVIDIA cards (Kepler sm_30, Maxwell
  /// sm_50, Pascal sm_61) will crash with an illegal instruction or fatal
  /// abort when `--flash-attn` is passed.
  ///
  /// Heuristic: RTX branding guarantees Turing+. GTX 16xx (1630/1650/1660)
  /// are Turing-architecture cards sold under the GTX label. Professional
  /// datacenter cards (A-series, T4, L-series, H-series) are Ampere+.
  /// All other GTX cards are Maxwell/Pascal and must not use flash-attn.
  bool get supportsFlashAttn {
    if (vendor != GpuVendor.nvidia || !cudaAvailable) return false;
    final upper = name.toUpperCase();
    // RTX branding: Turing (20xx), Ampere (30xx), Ada (40xx), Blackwell (50xx)
    if (upper.contains('RTX')) return true;
    // GTX 16xx series: Turing architecture with GTX branding (1630/1650/1660)
    if (RegExp(r'GTX\s*16\d\d').hasMatch(upper)) return true;
    // NVIDIA datacenter/professional Turing+ cards
    if (RegExp(
      r'\b(T4|A10G?|A16|A30|A40|A100|A800|L4|L40S?|H100|H200)\b',
    ).hasMatch(upper)) {
      return true;
    }
    // All other GTX cards (6xx Kepler, 7xx Kepler/Maxwell, 9xx Maxwell,
    // 10xx Pascal) do not support flash attention.
    return false;
  }

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
// Riverpod provider
// ---------------------------------------------------------------------------

/// Provides GPU info as a [FutureProvider], making it testable and overridable.
final gpuInfoProvider = FutureProvider<GpuInfo>((ref) => detectGpu());

// ---------------------------------------------------------------------------
// Asset pattern mapping
// ---------------------------------------------------------------------------

/// Returns the asset name patterns in priority order for the detected GPU.
///
/// [gpuMode] is the user's GPU preference: 'auto', 'enabled', 'disabled'.
/// [isWhisPaste] selects between WhisPaste and upstream whisper.cpp naming.
List<String> serverAssetPatterns(
  GpuInfo gpu,
  String gpuMode,
  bool isWhisPaste,
) {
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

/// Metadata file written after each successful whisper-server download.
const _serverInfoFilename = '.server-info.json';

/// Checks if the existing whisper-server binary in [sttDirPath] is compatible
/// with the detected [gpu].
///
/// Uses two layers of validation:
/// 1. **Metadata check**: reads `.server-info.json` written during download
///    and compares the stored backend against the GPU's optimal backend.
/// 2. **DLL heuristic**: if CUDA DLLs are present on a non-NVIDIA system,
///    the binary is incompatible regardless of metadata.
///
/// Returns `true` if compatible or no binary exists. Returns `false` if the
/// binary was downloaded for a different backend than what the current GPU
/// requires (e.g., CPU binary on a Vulkan-capable system, or CUDA binary
/// on a non-NVIDIA system).
bool isServerBinaryCompatible(String sttDirPath, GpuInfo gpu) {
  final serverFile = File(
    p.join(
      sttDirPath,
      Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
    ),
  );
  if (!serverFile.existsSync()) return true; // Nothing to validate.

  // --- Layer 1: Metadata-based check ----------------------------------------
  final info = readServerBinaryInfo(sttDirPath);
  if (info != null) {
    final storedBackend = info['backend'] as String? ?? '';
    final currentBackend = gpu.optimalBackend;

    if (storedBackend.isNotEmpty && storedBackend != currentBackend) {
      _log.warning(
        'Binary mismatch: installed backend="$storedBackend" but '
        'current GPU needs "$currentBackend" (${gpu.name}). '
        'Binary needs re-download for optimal performance.',
      );
      return false;
    }

    // Metadata present and backend matches → binary was correctly downloaded
    // for this GPU. Trust the metadata and skip DLL heuristics below.
    // DLL checks (L2/L3) are fallbacks for legacy downloads without metadata.
    if (storedBackend.isNotEmpty) {
      return true;
    }
  }

  // --- Layer 2: DLL heuristic (Windows-only) --------------------------------
  if (Platform.isWindows) {
    final cudaDlls = ['cublas64_12.dll', 'cublaslt64_12.dll', 'ggml-cuda.dll'];
    final hasCudaDlls = cudaDlls.any(
      (dll) => File(p.join(sttDirPath, dll)).existsSync(),
    );

    if (hasCudaDlls && gpu.vendor != GpuVendor.nvidia) {
      _log.warning(
        'Incompatible binary: CUDA DLLs found but GPU is ${gpu.vendor} '
        '(${gpu.name}). Binary needs re-download.',
      );
      return false;
    }

    // Inverse: non-CUDA binary on a CUDA-capable NVIDIA system.
    if (!hasCudaDlls && gpu.vendor == GpuVendor.nvidia && gpu.cudaAvailable) {
      _log.warning(
        'Sub-optimal binary: no CUDA DLLs but GPU is NVIDIA with CUDA. '
        'Binary needs re-download for optimal performance.',
      );
      return false;
    }

    // --- Layer 3: Vulkan DLL heuristic --------------------------------------
    // Vulkan binaries always include ggml-vulkan.dll. If the GPU needs
    // Vulkan but the DLL is absent, the binary is a CPU-only build.
    // This catches the case where .server-info.json is missing (e.g. legacy
    // download) and the binary was fetched from upstream CPU/BLAS.
    if (gpu.optimalBackend == 'vulkan') {
      final hasVulkanDll = File(
        p.join(sttDirPath, 'ggml-vulkan.dll'),
      ).existsSync();
      if (!hasVulkanDll) {
        _log.warning(
          'Sub-optimal binary: no ggml-vulkan.dll but GPU needs Vulkan '
          'backend (${gpu.name}). Binary needs re-download for GPU '
          'acceleration.',
        );
        return false;
      }
    }
  }

  return true;
}

/// Writes metadata about the downloaded whisper-server binary.
///
/// Called after a successful server binary download/extraction so that
/// [isServerBinaryCompatible] can later validate without DLL heuristics.
Future<void> writeServerBinaryInfo(
  String sttDirPath,
  GpuInfo gpu, {
  String? sourceRepo,
  String? assetName,
}) async {
  final infoFile = File(p.join(sttDirPath, _serverInfoFilename));
  final info = <String, Object>{
    'backend': gpu.optimalBackend,
    'gpu_vendor': gpu.vendor.name,
    'gpu_name': gpu.name,
    'cuda_available': gpu.cudaAvailable,
    'vulkan_available': gpu.vulkanAvailable,
    'downloaded_at': DateTime.now().toUtc().toIso8601String(),
  };
  if (sourceRepo != null) info['source_repo'] = sourceRepo;
  if (assetName != null) info['asset_name'] = assetName;
  try {
    await infoFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(info),
    );
    _log.info('Wrote server binary info: backend=${gpu.optimalBackend}');
  } on FileSystemException catch (e) {
    _log.warning('Could not write server binary info: $e');
  }
}

/// Reads the stored server binary metadata, or `null` if no info file exists.
Map<String, dynamic>? readServerBinaryInfo(String sttDirPath) {
  final infoFile = File(p.join(sttDirPath, _serverInfoFilename));
  if (!infoFile.existsSync()) return null;
  try {
    return jsonDecode(infoFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    _log.warning('Could not read server binary info: $e');
    return null;
  }
}

/// Validates the server binary at startup and deletes it if incompatible.
///
/// Returns `true` if the binary was deleted (caller should mark server as
/// not ready). Returns `false` if no action was needed.
Future<bool> validateAndCleanIncompatibleBinary(String sttDirPath) async {
  final gpu = await detectGpu();
  final serverPath = p.join(
    sttDirPath,
    Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
  );
  if (!File(serverPath).existsSync()) return false;

  if (!isServerBinaryCompatible(sttDirPath, gpu)) {
    _log.info(
      'Startup validation: deleting incompatible server binary '
      '(GPU=${gpu.name}, backend=${gpu.optimalBackend})',
    );
    await deleteServerBinary(sttDirPath);
    return true;
  }

  _log.info(
    'Startup validation: server binary compatible '
    '(GPU=${gpu.name}, backend=${gpu.optimalBackend})',
  );
  return false;
}

/// Deletes the whisper-server binary, associated DLLs, and the metadata
/// file from [sttDirPath].
///
/// Used to force a re-download of the correct binary variant.
Future<void> deleteServerBinary(String sttDirPath) async {
  final dir = Directory(sttDirPath);
  if (!dir.existsSync()) return;

  var deleted = 0;
  for (final entity in dir.listSync()) {
    if (entity is File) {
      final name = p.basename(entity.path).toLowerCase();
      if (name.endsWith('.exe') ||
          name.endsWith('.dll') ||
          name.endsWith('.dylib') ||
          name.endsWith('.so') ||
          name == 'whisper-server' ||
          name == _serverInfoFilename) {
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

  if (vendor == GpuVendor.nvidia) {
    vramMB = await _windowsNvidiaVramMB() ?? vramMB;
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

Future<int?> _windowsNvidiaVramMB() async {
  try {
    final result = await Process.run('nvidia-smi', [
      '--query-gpu=memory.total',
      '--format=csv,noheader,nounits',
    ]).timeout(const Duration(seconds: 5));

    if (result.exitCode != 0) return null;

    for (final line in result.stdout.toString().split('\n')) {
      final mb = int.tryParse(line.trim());
      if (mb != null && mb > 0) return mb;
    }
  } catch (e) {
    _log.debug('nvidia-smi VRAM query failed: $e');
  }
  return null;
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
        gpus.add(
          _GpuParsed(
            name: currentName,
            vendor: _classifyVendor(currentName),
            vramMB: currentVram,
          ),
        );
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
    gpus.add(
      _GpuParsed(
        name: currentName,
        vendor: _classifyVendor(currentName),
        vramMB: currentVram,
      ),
    );
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

      gpus.add(
        _GpuParsed(
          name: name,
          vendor: _classifyVendor(name),
          vramMB: vramBytes != null && vramBytes > 0
              ? vramBytes ~/ (1024 * 1024)
              : null,
        ),
      );
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
        final sysctl = await Process.run('sysctl', [
          '-n',
          'machdep.cpu.brand_string',
        ]);
        final brand = sysctl.stdout.toString().trim();
        if (brand.isNotEmpty) chipName = brand;
      } catch (_) {}

      return GpuInfo(
        vendor: GpuVendor.apple,
        name: chipName,
        vramMB: await _macUnifiedMemoryMB(),
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
      final vramMB = _extractMacVramMB(output);
      final lower = output.toLowerCase();

      if (lower.contains('amd') || lower.contains('radeon')) {
        return GpuInfo(
          vendor: GpuVendor.amd,
          name: chipName ?? 'AMD GPU',
          vramMB: vramMB,
          vulkanAvailable: true,
        );
      }
      // NVIDIA on Mac is rare (pre-2016) and CUDA is unsupported on modern macOS.
    }
  } catch (_) {}

  // Fallback: Intel integrated on Intel Mac.
  return const GpuInfo(vendor: GpuVendor.intel, name: 'Intel (Mac)');
}

Future<int?> _macUnifiedMemoryMB() async {
  try {
    final result = await Process.run('sysctl', ['-n', 'hw.memsize']);
    if (result.exitCode != 0) return null;
    final bytes = int.tryParse(result.stdout.toString().trim());
    if (bytes == null || bytes <= 0) return null;
    return bytes ~/ (1024 * 1024);
  } catch (e) {
    _log.debug('macOS unified memory query failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// RAM detection (cross-platform)
// ---------------------------------------------------------------------------

/// Detects total physical system RAM in MB.
///
/// Uses platform-native commands (same pattern as GPU detection).
/// Returns `null` when detection fails — callers should treat `null` as
/// "unknown" and NOT block the app (fail-open to avoid false positives).
Future<int?> detectRamMB() async {
  try {
    if (Platform.isMacOS || Platform.isLinux) {
      return await _unixRamMB();
    } else if (Platform.isWindows) {
      return await _windowsRamMB();
    }
  } catch (e) {
    _log.warning('RAM detection failed: $e');
  }
  return null;
}

Future<int?> _unixRamMB() async {
  if (Platform.isMacOS) {
    // Use absolute path to avoid PATH hijack — /usr/sbin/sysctl is canonical.
    // hw.memsize returns total physical bytes (e.g. 17179869184 = 16 GB).
    final r = await Process.run('/usr/sbin/sysctl', [
      '-n',
      'hw.memsize',
    ]).timeout(const Duration(seconds: 5));
    if (r.exitCode != 0) return null;
    return parseSysctlMemsizeMb(r.stdout.toString());
  } else {
    // Linux: read /proc/meminfo directly — no subprocess, no PATH dependency.
    try {
      final lines = await File('/proc/meminfo').readAsLines();
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          return parseLinuxMemTotalMb(line);
        }
      }
    } catch (e) {
      _log.debug('Linux /proc/meminfo read failed: $e');
    }
    return null;
  }
}

Future<int?> _windowsRamMB() async {
  // PowerShell: TotalVisibleMemorySize is in KB.
  // Note: non-zero exit (e.g. execution policy) falls through to wmic.
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'(Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize',
    ]).timeout(const Duration(seconds: 10));
    if (r.exitCode == 0) {
      final kb = int.tryParse(r.stdout.toString().trim());
      if (kb != null && kb > 0) return kb ~/ 1024;
    }
  } catch (_) {}

  // Fallback: wmic (deprecated but more widely available).
  try {
    final r = await Process.run('wmic', [
      'os',
      'get',
      'TotalVisibleMemorySize',
      '/Value',
    ]).timeout(const Duration(seconds: 5));
    if (r.exitCode == 0) {
      final result = parseWmicOsMemoryMb(r.stdout.toString());
      if (result != null) return result;
    }
  } catch (_) {}

  return null;
}

// ---------------------------------------------------------------------------
// Pure RAM parsing helpers — exported for unit testing.
// ---------------------------------------------------------------------------

/// Parses `sysctl -n hw.memsize` stdout into MB.
///
/// Returns `null` for empty, non-numeric, or non-positive output.
@visibleForTesting
int? parseSysctlMemsizeMb(String output) {
  final bytes = int.tryParse(output.trim());
  if (bytes == null || bytes <= 0) return null;
  return bytes ~/ (1024 * 1024);
}

/// Parses a Linux `/proc/meminfo` snippet containing a `MemTotal:` line into MB.
///
/// Returns `null` when the line is absent or the value cannot be parsed.
@visibleForTesting
int? parseLinuxMemTotalMb(String memInfoOutput) {
  final match = RegExp(r'MemTotal:\s+(\d+)').firstMatch(memInfoOutput);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1) ?? '');
  if (kb == null || kb <= 0) return null;
  return kb ~/ 1024;
}

/// Parses `wmic os get TotalVisibleMemorySize /Value` stdout into MB.
///
/// Returns `null` when the key is absent or the value cannot be parsed.
@visibleForTesting
int? parseWmicOsMemoryMb(String wmicOutput) {
  final match = RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(wmicOutput);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1) ?? '');
  if (kb == null || kb <= 0) return null;
  return kb ~/ 1024;
}

int? _extractMacVramMB(String profilerOutput) {
  for (final line in profilerOutput.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.toLowerCase().startsWith('vram')) continue;

    final match = RegExp(
      r'(\d+)\s*(gb|mb)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) continue;

    final amount = int.tryParse(match.group(1) ?? '');
    final unit = match.group(2)?.toLowerCase();
    if (amount == null || unit == null) continue;
    return unit == 'gb' ? amount * 1024 : amount;
  }
  return null;
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
            vramMB: await _linuxNvidiaVramMB(),
            cudaAvailable: _linuxHasCuda(),
            vulkanAvailable: true,
          );
        }
        if (vendorId == '0x1002') {
          return GpuInfo(
            vendor: GpuVendor.amd,
            name: await _linuxGpuName() ?? 'AMD GPU',
            vramMB: _linuxAmdVramMB(),
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
          vramMB: await _linuxNvidiaVramMB(),
          cudaAvailable: _linuxHasCuda(),
          vulkanAvailable: true,
        );
      }
      if (output.contains('[1002:') ||
          output.contains('amd') ||
          output.contains('radeon')) {
        return GpuInfo(
          vendor: GpuVendor.amd,
          name: 'AMD GPU',
          vramMB: _linuxAmdVramMB(),
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

Future<int?> _linuxNvidiaVramMB() async {
  try {
    final result = await Process.run('nvidia-smi', [
      '--query-gpu=memory.total',
      '--format=csv,noheader,nounits',
    ]).timeout(const Duration(seconds: 5));

    if (result.exitCode != 0) return null;

    for (final line in result.stdout.toString().split('\n')) {
      final mb = int.tryParse(line.trim());
      if (mb != null && mb > 0) return mb;
    }
  } catch (e) {
    _log.debug('Linux nvidia-smi VRAM query failed: $e');
  }
  return null;
}

int? _linuxAmdVramMB() {
  try {
    final drmDir = Directory('/sys/class/drm');
    if (!drmDir.existsSync()) return null;

    for (final card in drmDir.listSync()) {
      final vramFile = File('${card.path}/device/mem_info_vram_total');
      if (!vramFile.existsSync()) continue;
      final bytes = int.tryParse(vramFile.readAsStringSync().trim());
      if (bytes != null && bytes > 0) {
        return bytes ~/ (1024 * 1024);
      }
    }
  } catch (e) {
    _log.debug('Linux AMD VRAM query failed: $e');
  }
  return null;
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
